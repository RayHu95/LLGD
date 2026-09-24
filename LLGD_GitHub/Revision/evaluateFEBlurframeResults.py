import csv
import json
import sys
from pathlib import Path

import numpy as np


revision_dir = Path(__file__).resolve().parent
source_dir = revision_dir / "third_party" / "FE-LSD"
dataset_dir = source_dir / "dataset" / "FE-Blurframe-154"
output_dir = revision_dir / "results"

sys.path.insert(0, str(source_dir))
if not hasattr(np, "float"):
    np.float = float

from metric.eval_sAP import eval_sAP


methods = (
    ("LLGD", "Event stream",
     dataset_dir / "test.json",
     output_dir / "fe_blurframe_llgd_result.json"),
    ("FE-HAWP", "Blurred frame + event stream",
     dataset_dir / "test.json",
     output_dir / "fe_blurframe_fe_hawp_result.json"),
    ("FE-ULSD", "Blurred frame + event stream",
     dataset_dir / "test.json",
     output_dir / "fe_blurframe_fe_ulsd_result.json"),
)


def main():
    rows = []
    llgd_detail = None
    for method, input_data, gt_file, result_file in methods:
        msap, precision, recall, sap = eval_sAP(str(gt_file), str(result_file))
        with open(gt_file, encoding="utf-8") as f:
            ground_truth = json.load(f)
        with open(result_file, encoding="utf-8") as f:
            predictions = json.load(f)
        gt_lines = sum(len(item["lines"]) for item in ground_truth)
        pred_lines = sum(len(item["line_pred"]) for item in predictions)
        rows.append([method, len(predictions), input_data,
                     sap[0], sap[1], sap[2], msap])
        if method == "LLGD":
            llgd_detail = [sap[0], sap[1], sap[2], msap,
                           precision, recall, gt_lines, pred_lines]

    with open(output_dir / "fe_blurframe_llgd_metrics_official.csv",
              "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["sAP5", "sAP10", "sAP15", "msAP", "Precision",
                         "Recall", "GroundTruthLines", "PredictedLines"])
        writer.writerow(llgd_detail)

    with open(output_dir / "fe_blurframe_three_method_metrics.csv",
              "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Method", "Samples", "Input", "sAP5", "sAP10",
                         "sAP15", "msAP"])
        writer.writerows(rows)


if __name__ == "__main__":
    main()
