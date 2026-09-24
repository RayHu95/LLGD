import json
import cv2
import numpy as np
import matplotlib.pyplot as plt
from evaluateRTComparison import ROOT, read_lines


def main():
    fig, axes = plt.subplots(3, 3, figsize=(9, 6.8), constrained_layout=True)
    for row, name in enumerate(('urban', 'office_spiral', 'hqf_boxes')):
        folder = ROOT / name
        frames = json.loads((folder / 'frames.json').read_text(encoding='utf-8'))
        frame = min(frames, key=lambda f: abs(f['frame_time'] - 7.5))
        filename = ROOT.parents[2] / frame['image']
        gray = cv2.imdecode(np.fromfile(filename, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
        predictions = [frame['lines']] + [read_lines(folder / f'{m}_lines.csv').get(frame['index'], [])
                                       for m in ('rt', 'llgd')]
        for col, lines in enumerate(predictions):
            ax = axes[row, col]
            ax.imshow(gray, cmap='gray', vmin=0, vmax=255)
            for line in lines:
                p = np.asarray(line).reshape(2, 2)
                ax.plot(p[:, 0], p[:, 1], color=['#35ce70', '#28bce6', '#ff8b32'][col], lw=.8)
            ax.set_xlim(-.5, 239.5)
            ax.set_ylim(179.5, -.5)
            ax.set_xticks([])
            ax.set_yticks([])
            if row == 0:
                ax.set_title(['LSD reference', 'RT-EvLDT', 'LLGD'][col], fontsize=11)
            if col == 0:
                ax.set_ylabel(f"{name}\n{frame['frame_time']:.3f} s", fontsize=10)
    fig.savefig(ROOT / 'comparison.png', dpi=180)
    plt.close(fig)


if __name__ == '__main__':
    main()
