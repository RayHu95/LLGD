import json
import sys
from pathlib import Path

import cv2
import numpy as np
from scipy.io import savemat
from rosbags.highlevel import AnyReader


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Revision' / 'results' / 'rt_evldt'
DTYPE = np.dtype([('t', '<f8'), ('x', '<i4'), ('y', '<i4'), ('p', '<i4')])


def time_ns(stamp):
    return stamp.sec * 1000000000 + stamp.nanosec


def read_sequence(name):
    folder = ROOT / 'datasets' / name
    if name != 'hqf_boxes':
        a = np.loadtxt(folder / 'events.txt')
        events = np.empty(len(a), dtype=DTYPE)
        for k, field in enumerate(DTYPE.names):
            events[field] = a[:, k]
        frames = []
        for index, line in enumerate((folder / 'images.txt').read_text().splitlines()):
            if line.startswith('#') or not line.strip():
                continue
            stamp, filename = line.split()
            frames.append((index + 1, float(stamp), folder / filename))
        return events, frames

    parts, frames = [], []
    frame_folder = OUT / name / 'images'
    frame_folder.mkdir(parents=True, exist_ok=True)
    with AnyReader([ROOT / 'datasets' / 'hqf' / 'boxes.bag']) as reader:
        for connection, _, raw in reader.messages():
            if connection.topic not in ('/dvs/events', '/dvs/image_raw'):
                continue
            msg = reader.deserialize(raw, connection.msgtype)
            if connection.topic == '/dvs/events':
                a = np.empty(len(msg.events), dtype=[('t', '<i8'), ('x', '<i4'), ('y', '<i4'), ('p', '<i4')])
                for i, event in enumerate(msg.events):
                    a[i] = (time_ns(event.ts), event.x, event.y, event.polarity)
                parts.append(a)
            else:
                index = len(frames) + 1
                filename = frame_folder / f'{index:06d}.png'
                im = np.asarray(msg.data).reshape(msg.height, msg.step)[:, :msg.width]
                cv2.imencode('.png', im)[1].tofile(filename)
                frames.append((index, time_ns(msg.header.stamp), filename))
    raw_events = np.concatenate(parts)
    origin = int(raw_events['t'][0])
    events = np.empty(len(raw_events), dtype=DTYPE)
    events['t'] = (raw_events['t'] - origin) / 1e9
    for field in ('x', 'y', 'p'):
        events[field] = raw_events[field]
    frames = [(i, (t - origin) / 1e9, p) for i, t, p in frames]
    return events, frames


def main():
    lsd = cv2.createLineSegmentDetector(cv2.LSD_REFINE_STD)
    for name in sys.argv[1:] or ('urban', 'office_spiral', 'hqf_boxes'):
        folder = OUT / name
        folder.mkdir(parents=True, exist_ok=True)
        events, frames = read_sequence(name)
        if np.any(np.diff(events['t']) < 0):
            raise ValueError(f'Unsorted timestamps: {name}')
        events = events[events['t'] <= 10.0]
        events.tofile(folder / 'events.bin')
        frames = [(i, t, p) for i, t, p in frames if 5.0 <= t < 10.0]
        records = []
        for index, frame_time, filename in frames:
            tick = int(np.floor(frame_time * 600))
            end = tick / 600
            lo, hi = np.searchsorted(events['t'], [end - .020, end], side='right')
            packet = events[lo:hi]
            t = packet['t'] - (end - .020)
            event_array = np.column_stack([packet['x'], packet['y'], packet['p'],
                                          np.zeros(len(t)), t * 1e9])
            savemat(folder / f'{index:06d}.mat', {'eventArray': event_array,
                    'frameTime': frame_time, 'tick': tick, 'endTime': end})
            gray = cv2.imdecode(np.fromfile(filename, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
            if gray.shape != (180, 240):
                raise ValueError(f'Unexpected image size: {filename}')
            lines = lsd.detect(gray)[0]
            lines = [] if lines is None else lines.reshape(-1, 4).tolist()
            records.append({'index': index, 'frame_time': frame_time, 'tick': tick,
                            'time': end, 'event_count': len(packet),
                            'image': filename.relative_to(ROOT).as_posix(), 'lines': lines})
        (folder / 'frames.json').write_text(json.dumps(records), encoding='utf-8')
        np.savetxt(folder / 'frames.txt', [(r['index'], r['tick']) for r in records], fmt='%d')
        print(name, len(events), 'events;', len(records), 'frames;',
              np.mean([r['event_count'] for r in records]), 'events/window', flush=True)


if __name__ == '__main__':
    main()
