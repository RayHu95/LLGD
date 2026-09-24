# Dataset preparation

The packet-level experiments use the Event-Camera Dataset and High Quality Frames (HQF); the annotated endpoint comparison uses FE-Blurframe and auxiliary RE-LSD events. Download the recordings from their original sources. Neither raw recordings nor extracted real-data packets are included in this package.

## Event-Camera Dataset

Project: https://rpg.ifi.uzh.ch/davis_data.html

- shapes_6dof: https://rpg.ifi.uzh.ch/datasets/davis/shapes_6dof.zip
- urban: https://rpg.ifi.uzh.ch/datasets/davis/urban.zip
- office_spiral: https://rpg.ifi.uzh.ch/datasets/davis/office_spiral.zip

Extract each recording so that `images.txt`, `events.txt` and the image files are under `datasets/shapes_6dof`, `datasets/urban` or `datasets/office_spiral`. Run from the repository root:

```matlab
preparePublicDataset('shapes_6dof',30,0.02,[2,101]);
preparePublicDataset('urban',30,0.02);
preparePublicDataset('office_spiral',30,0.02);
```

For shapes_6dof, 30 frame indices are sampled approximately uniformly from one-based indices 2 through 101. For the other sequences, the interval runs from the tenth through the third-to-last available frame. Each packet starts at the selected frame timestamp and ends 20 ms later or at the next frame timestamp, whichever comes first. The selected image supplies the frame-derived evaluation reference.

The original archives used in the paper have these SHA-256 values:

| Archive | SHA-256 |
| --- | --- |
| shapes_6dof.zip | A3B7E6F94C8ABD6158B14CEAF26522B580DCA21EB8D54FB9094CAD62A8FF0636 |
| urban.zip | 9D5E4721FFF7C9253E5822089B4C5557206943517D6B8E73D9EE1A649A52BF24 |
| office_spiral.zip | E8D0FFE220973C2895EAAB4BA13BAB9F8F06B89973EEAF4D70EBD4D03D0C7EF2 |

## High Quality Frames

Project: https://timostoff.github.io/20ecnn

Official data folder: https://drive.google.com/drive/folders/18Xdr6pxJX0ZXTrXW9tK0hC3ZpmKDIt6_

Download `boxes.bag` and place it at `datasets/hqf/boxes.bag`. With ROS Toolbox installed, run:

```matlab
addpath('Revision');
prepareHQFBoxes('datasets/hqf/boxes.bag', ...
    'datasets/hqf_boxes_events.mat',30,0.02);
```

The converter selects 30 image messages approximately uniformly from the tenth through the third-to-last available message and collects the following 20 ms of events. The source bag has SHA-256 `99CA9721E1E4EC3A27D4D6B920135D3C8D57F83DD74588F3A00A95326E95D603`.

## Packet files

The four converters produce `datasets/shapes_6dof_events.mat`, `datasets/urban_events.mat`, `datasets/office_spiral_events.mat` and `datasets/hqf_boxes_events.mat`. Each file contains 30 packets, their images and sensor dimensions. Event columns are `[x,y,polarity,second,nanosecond]` with zero-based pixel coordinates.

The continuous-stream experiments read the extracted urban and office_spiral recordings and `datasets/hqf/boxes.bag` directly using `Revision/prepareRTComparison.py`; they do not use these 30-packet MAT files. The Python HQF reader does not require ROS Toolbox.

## FE-Blurframe and RE-LSD

Official dataset: https://huggingface.co/datasets/lh9171338/FE-Blurframe/tree/main

Download `test.jsonl` and `images-blur.zip` into `external/FE-Blurframe`. Training data and start/end images are not needed for this comparison.

Official models: https://huggingface.co/lh9171338/FE-LSD/tree/ebf06ab096ea565e7cc68326735e9a86f7abb19b

Download these checkpoints into `external/FE-Blurframe`:

- [FE-HAWP_FE-Blurframe.pkl](https://huggingface.co/lh9171338/FE-LSD/resolve/ebf06ab096ea565e7cc68326735e9a86f7abb19b/FE-HAWP_FE-Blurframe.pkl?download=true)
- [FE-ULSD_FE-Blurframe.pkl](https://huggingface.co/lh9171338/FE-LSD/resolve/ebf06ab096ea565e7cc68326735e9a86f7abb19b/FE-ULSD_FE-Blurframe.pkl?download=true)

The continuous-timestamp archive comes from the [EvLSD-IED data share](https://1drv.ms/f/c/93289205239bc375/EoSWLjyUd4JDgzARyahZtTcBjfqtTmDchmW_w_GWYltV8A?e=vkLnVt). Open `datasets/RE-LSD/events`, download `events_FE-LSD_600.zip`, and place it at `external/RE-LSD/events_FE-LSD_600.zip`. Do not substitute the boolean-timestamp `events_raw.zip` from FE-Blurframe. EvLSD-IED model weights are not needed for the FE-LSD comparison.

| File | SHA-256 of the evaluated copy |
| --- | --- |
| test.jsonl | `b05462b016f67287f6780745c4c1e8076f15e09305bbe51261aa176282ae2699` |
| images-blur.zip | `a8373a3ec9b0ce137df22542d19125043258163173fbb223a2a13c1ca0b924f2` |
| events_FE-LSD_600.zip | `25075d9f5d4c3a45a9fd338995f3261da3a602f28d8f4072e74fb8d08c197ba3` |
| FE-HAWP_FE-Blurframe.pkl | `ef57c1bbae0efd351adb8ecbb6879b0300d375fa5eaf5a1bf55466d697ef17c1` |
| FE-ULSD_FE-Blurframe.pkl | `08dcf36b5f6025d6228ea1c393f12ebf14c9f58102854fc11a8f84e6a90bff76` |

The data preparation script selects the 154 available test samples and creates `Revision/third_party/FE-LSD/dataset/FE-Blurframe-154`. The complete commands and evaluation settings are in [EXPERIMENTS.md](EXPERIMENTS.md).
