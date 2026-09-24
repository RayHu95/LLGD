import json
from pathlib import Path

import numpy as np

from evaluateRTComparison import read_lines, line_map, match_maps, scores, write_rows


ROOT = Path(__file__).resolve().parent / 'results'


def main():
    details, summary = [], []
    output = ROOT / 'local_verification_geometry'
    for name in ('urban', 'office_spiral', 'hqf_boxes'):
        source = ROOT / 'rt_evldt' / name
        frames = json.loads((source / 'frames.json').read_text(encoding='utf-8'))
        variants = (('Full LLGD', source),
                    ('w/o local verification', output / name))
        for variant, folder in variants:
            predictions = read_lines(folder / 'llgd_lines.csv')
            for tolerance in (3, 6, 9):
                counts = np.zeros(3, dtype=np.int64)
                for frame in frames:
                    pred = line_map(predictions.get(frame['index'], []))
                    ref = line_map(frame['lines'])
                    count = match_maps(pred, ref, tolerance)
                    counts += count
                    p, r, f = scores(*count)
                    details.append(dict(Sequence=name, Variant=variant,
                                        Index=frame['index'], Tolerance=tolerance,
                                        Matched=count[0], Predicted=count[1],
                                        Reference=count[2], Precision=p, Recall=r, F1=f))
                p, r, f = scores(*counts)
                row = dict(Sequence=name, Variant=variant, Tolerance=tolerance,
                           Frames=len(frames), Matched=int(counts[0]),
                           Predicted=int(counts[1]), Reference=int(counts[2]),
                           Precision=p, Recall=r, F1=f)
                summary.append(row)
                print(row, flush=True)
    write_rows(output / 'detail.csv', details)
    write_rows(output / 'summary.csv', summary)


if __name__ == '__main__':
    main()
