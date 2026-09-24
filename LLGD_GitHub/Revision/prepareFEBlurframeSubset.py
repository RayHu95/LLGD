import csv
import json
import os
import shutil
import sys
import zipfile
from pathlib import Path
from types import SimpleNamespace

import numpy as np


revision_dir = Path(__file__).resolve().parent
root_dir = revision_dir.parent
material_dir = root_dir / "external"
fe_dir = material_dir / "FE-Blurframe"
re_events = material_dir / "RE-LSD" / "events_FE-LSD_600.zip"
source_dir = revision_dir / "third_party" / "FE-LSD"
dataset_dir = source_dir / "dataset" / "FE-Blurframe-154"

sys.path.insert(0, str(source_dir))
from event2frame import Event2EST


def main():
    with open(fe_dir / "test.jsonl", encoding="utf-8") as f:
        test_data = [json.loads(line) for line in f]

    with zipfile.ZipFile(re_events) as event_zip:
        available = {Path(name).name for name in event_zip.namelist() if name.endswith(".npz")}
        subset = [ann for ann in test_data if ann["filename"].replace(".png", ".npz") in available]

        raw_dir = dataset_dir / "events_raw"
        event_dir = dataset_dir / "events"
        image_dir = dataset_dir / "images-blur"
        raw_dir.mkdir(parents=True, exist_ok=True)
        event_dir.mkdir(parents=True, exist_ok=True)
        image_dir.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(fe_dir / "images-blur.zip") as image_zip:
            for ann in subset:
                name = ann["filename"]
                with image_zip.open(f"images-blur/{name}") as src, open(image_dir / name, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                event_name = name.replace(".png", ".npz")
                with event_zip.open(f"events_raw/{event_name}") as src, open(raw_dir / event_name, "wb") as dst:
                    shutil.copyfileobj(src, dst)

    annotations = []
    for ann in subset:
        item = dict(ann)
        item["width"], item["height"] = item.pop("image_size")
        annotations.append(item)

    with open(dataset_dir / "test.json", "w", encoding="utf-8") as f:
        json.dump(annotations, f)

    cfg = SimpleNamespace(dim=10, scale=0.5, plot=False)
    rows = []
    os.chdir(source_dir)
    for ann in annotations:
        image_file = dataset_dir / "images-blur" / ann["filename"]
        event_file = dataset_dir / "events_raw" / ann["filename"].replace(".png", ".npz")
        dst_file = dataset_dir / "events" / event_file.name
        Event2EST(str(image_file.relative_to(source_dir)),
                  str(event_file.relative_to(source_dir)),
                  str(dst_file.relative_to(source_dir)), cfg)
        with np.load(event_file) as data:
            mask = (data["x"] >= 0) & (data["x"] < 320) & (data["y"] >= 0) & (data["y"] < 256)
            t = data["t"][mask]
            rows.append((ann["filename"], int(mask.sum()), int(t.min()), int(t.max())))

    with open(dataset_dir / "subset_manifest.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Filename", "Events", "FirstTimeNs", "LastTimeNs"])
        writer.writerows(rows)

    print(f"Prepared {len(annotations)} samples in {dataset_dir}")


if __name__ == "__main__":
    main()
