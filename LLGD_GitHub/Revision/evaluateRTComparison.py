import csv
import json
from pathlib import Path

import cv2
import numpy as np
from scipy.spatial import cKDTree
from scipy.sparse.csgraph import maximum_bipartite_matching


ROOT = Path(__file__).resolve().parent / 'results' / 'rt_evldt'


def read_lines(path):
    result = {}
    with path.open() as f:
        for row in csv.DictReader(f):
            result.setdefault(int(row['Index']), []).append(
                [float(row[key]) for key in ('X1', 'Y1', 'X2', 'Y2')])
    return result


def line_map(lines):
    canvas = np.zeros((180, 240), dtype=np.uint8)
    for line in lines:
        p1, p2 = np.rint(line).astype(int).reshape(2, 2)
        valid, p1, p2 = cv2.clipLine((0, 0, 240, 180), tuple(p1), tuple(p2))
        if valid:
            cv2.line(canvas, p1, p2, 1, 1, cv2.LINE_8)
    return canvas.astype(bool)


def match_maps(pred, ref, tolerance):
    p, r = np.argwhere(pred), np.argwhere(ref)
    if not len(p) or not len(r):
        return 0, len(p), len(r)
    graph = cKDTree(p).sparse_distance_matrix(cKDTree(r), tolerance,
                                             output_type='coo_matrix').tocsr()
    graph.data[:] = 1
    matches = maximum_bipartite_matching(graph, perm_type='column')
    return int(np.sum(matches >= 0)), len(p), len(r)


def scores(matched, predicted, reference):
    precision = matched / predicted if predicted else 0
    recall = matched / reference if reference else 0
    f1 = 2 * matched / (predicted + reference) if predicted + reference else 0
    return precision, recall, f1


def write_rows(path, rows):
    with path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    details, summary, metadata = [], [], []
    for name in ('urban', 'office_spiral', 'hqf_boxes'):
        folder = ROOT / name
        frames = json.loads((folder / 'frames.json').read_text(encoding='utf-8'))
        for method in ('rt', 'llgd'):
            predictions = read_lines(folder / f'{method}_lines.csv')
            for tolerance in (3, 6, 9):
                counts = np.zeros(3, dtype=np.int64)
                empty = 0
                for frame in frames:
                    pred = line_map(predictions.get(frame['index'], []))
                    ref = line_map(frame['lines'])
                    count = match_maps(pred, ref, tolerance)
                    counts += count
                    empty += not pred.any()
                    p, r, f = scores(*count)
                    details.append(dict(Sequence=name, Method=method, Index=frame['index'],
                                        Tolerance=tolerance, Matched=count[0], Predicted=count[1],
                                        Reference=count[2], Precision=p, Recall=r, F1=f))
                p, r, f = scores(*counts)
                row = dict(Sequence=name, Method=method, Tolerance=tolerance, Frames=len(frames),
                           Matched=int(counts[0]), Predicted=int(counts[1]), Reference=int(counts[2]),
                           Empty=empty, Precision=p, Recall=r, F1=f)
                summary.append(row)
                print(row, flush=True)
        rt = np.genfromtxt(folder / 'rt_timing.csv', delimiter=',', names=True)
        llgd = np.genfromtxt(folder / 'llgd_timing.csv', delimiter=',', names=True)
        times = rt['Seconds'][(rt['Tick'] >= 3000) & (rt['Tick'] < 6000)]
        metadata.append(dict(Sequence=name, Frames=len(frames),
                             MeanEvents=float(np.mean([f['event_count'] for f in frames])),
                             MaxFrameLag=max(f['frame_time'] - f['time'] for f in frames),
                             RTMeanStepSeconds=float(np.mean(times)),
                             RTP95StepSeconds=float(np.percentile(times, 95)),
                             RTWallSeconds=float(np.sum(times)),
                             LLGDMeanSeconds=float(np.mean(llgd['Seconds'])),
                             LLGDStdSeconds=float(np.std(llgd['Seconds'], ddof=1))))
    write_rows(ROOT / 'detail.csv', details)
    write_rows(ROOT / 'summary.csv', summary)
    (ROOT / 'timing.json').write_text(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
