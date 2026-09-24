import argparse
import csv
import json
import sys
import types
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader, Subset
from yacs.config import CfgNode


revision_dir = Path(__file__).resolve().parent
root_dir = revision_dir.parent
source_dir = revision_dir / "third_party" / "FE-LSD"
dataset_dir = source_dir / "dataset" / "FE-Blurframe-154"
material_dir = root_dir / "external" / "FE-Blurframe"
output_dir = revision_dir / "results"


def install_hafm_stub():
    module = types.ModuleType("network.FE_HAWP._C")

    def encodels(*args, **kwargs):
        raise RuntimeError("The HAFM training encoder is not available in inference mode.")

    module.encodels = encodels
    sys.modules[module.__name__] = module


install_hafm_stub()
sys.path.insert(0, str(source_dir))

from network.build import build_model
from network.dataset import Dataset
from test import convert_model, to_device
from metric.eval_sAP import eval_sAP


models = (
    ("FE-HAWP", material_dir / "FE-HAWP_FE-Blurframe.pkl"),
    ("FE-ULSD", material_dir / "FE-ULSD_FE-Blurframe.pkl"),
)


def load_config(arch):
    with open(source_dir / "config" / f"{arch}.yaml", encoding="utf-8") as f:
        cfg = CfgNode.load_cfg(f)
    cfg.arch = arch
    cfg.dataset_name = "FE-Blurframe-154"
    cfg.dataset_path = str(dataset_dir)
    cfg.test_batch_size = 1
    cfg.num_workers = 0
    cfg.freeze()
    return cfg


def load_model(arch, checkpoint_file, device):
    cfg = load_config(arch)
    model = build_model(cfg).to(device)
    checkpoint = torch.load(checkpoint_file, map_location=device, weights_only=True)
    state_dict = checkpoint["model"] if "model" in checkpoint else checkpoint
    try:
        model.load_state_dict(state_dict, strict=True)
    except RuntimeError:
        state_dict = convert_model(model, state_dict)
        model.load_state_dict(state_dict, strict=True)
    model.eval()
    return model, cfg


def run_model(arch, checkpoint_file, device, limit):
    model, cfg = load_model(arch, checkpoint_file, device)
    dataset = Dataset(cfg, split="test")
    if limit:
        dataset = Subset(dataset, range(min(limit, len(dataset))))
    loader = DataLoader(dataset, batch_size=1, num_workers=0, shuffle=False,
                        collate_fn=Dataset.collate, pin_memory=device.type == "cuda")

    results = []
    with torch.inference_mode():
        for images, annotations in loader:
            images = images.to(device, non_blocking=True)
            annotations = to_device(annotations, device)
            with torch.amp.autocast(device_type=device.type, enabled=device.type == "cuda"):
                output = model(images, annotations)[0]
            line_pred = output["line_pred"]
            line_score = output["line_score"]
            if isinstance(line_pred, torch.Tensor):
                line_pred = line_pred.detach().cpu().tolist()
            if isinstance(line_score, torch.Tensor):
                line_score = line_score.detach().cpu().tolist()
            results.append({
                "line_pred": line_pred,
                "line_score": line_score,
                "filename": output["filename"],
                "width": output["width"],
                "height": output["height"],
            })

    del model
    if device.type == "cuda":
        torch.cuda.empty_cache()
    return results


def write_results(arch, results):
    name = arch.lower().replace("-", "_")
    filename = output_dir / f"fe_blurframe_{name}_result.json"
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(results, f)
    return filename


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()

    device = torch.device("cuda")
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is not available")

    output_dir.mkdir(parents=True, exist_ok=True)
    limit = 1 if args.smoke else 0
    metric_rows = []
    if not hasattr(np, "float"):
        np.float = float

    for arch, checkpoint_file in models:
        results = run_model(arch, checkpoint_file, device, limit)
        line_count = sum(len(item["line_pred"]) for item in results)
        print(f"{arch}: {len(results)} samples, {line_count} lines")
        if args.smoke:
            continue
        result_file = write_results(arch, results)
        msap, _, _, sap = eval_sAP(str(dataset_dir / "test.json"), str(result_file))
        metric_rows.append([arch, len(results), sap[0], sap[1], sap[2], msap])
        print(f"{arch}: {sap[0]:.3f}, {sap[1]:.3f}, {sap[2]:.3f}, {msap:.3f}")

    if metric_rows:
        with open(output_dir / "fe_blurframe_recent_metrics.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["Method", "Samples", "sAP5", "sAP10", "sAP15", "msAP"])
            writer.writerows(metric_rows)


if __name__ == "__main__":
    main()
