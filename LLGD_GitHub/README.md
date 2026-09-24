# The line-based local-to-global detection method for event cameras

MATLAB implementation of LLGD by Rui Hu, Zehao Wu, Tianyu Wang and Yuanqing Xia.

LLGD fits up to two local line models and expands their inlier events on a spatio-temporal plane. The output assigns a cluster label to each event; nonpositive labels denote unassigned events. This package contains the detector, a synthetic example, and the evaluation scripts for the revised manuscript, including the FE-LSD and RT-EvLDT comparisons and the real-scene local-verification ablation.

## Requirements

MATLAB R2019b with Statistics and Machine Learning Toolbox. The frame-derived evaluation also requires Image Processing Toolbox. ROS Toolbox is needed only for the MATLAB HQF packet converter. LLGD requires no GPU. The FE-LSD inference scripts use Python and an NVIDIA CUDA GPU; RT-EvLDT is built on Ubuntu 22.04 (WSL 2 was used for the paper). See [EXPERIMENTS.md](EXPERIMENTS.md) for the experiment-to-table mapping and [DEPENDENCIES.md](DEPENDENCIES.md) for the tested versions.

## Example

Open this folder in MATLAB and run:

```matlab
[events, labels] = demoLLGD;
```

The example generates a rectangular event pattern and runs the complete detector without downloading data. It illustrates the input and output; it is not a benchmark result from the paper.

With the supplied seed, the console reports `1440 events, 4 detected clusters`.

`events` has columns `[x, y, polarity, second, nanosecond]`, with zero-based pixel coordinates. For another event packet, set `detector.pointData` to `[x/width, y/height, t-t0]`, with time in seconds, and set `c_width` and `c_height` to the sensor dimensions. Events should be ordered by timestamp. `EventSegmentation` returns the event labels.

## Four-sequence comparison

Prepare the four recordings following [DATASETS.md](DATASETS.md), then run from this folder:

```matlab
addpath('Revision');
config = struct('maxPackets',30,'resultPrefix','comparison_four');
runComparisonExperiments([],config);
computePairedF1Intervals;
plotComparisonExamples;
plotRevisionExamples;
```

The comparison uses the same 30 packets per sequence as Table IV. The Everding, ELiSeD and LECalib entries are our MATLAB reimplementations of the stages specified in Table II, not the complete official systems:

- Everding et al.: initial spatial clustering and the packet-level x-y-t plane test.
- ELiSeD: timestamp-surface orientation and support-region formation, with a 5,000-event buffer and a 30 ms timestamp cutoff.
- LECalib: KNN-PCA normal estimation and region growing, with K = 30 and a 0.1 s time scale.

Each detector is reinitialized per packet. The detector seed is `2025 + 100000 + 1000*packetIndex + 1`. Timing covers the detection call after one warm-up and excludes construction of the frame-derived reference. Runtime varies with the computer and execution environment.

The paired F1 intervals use 10,000 bootstrap resamples of the 30 packet indices with seed 2025. They describe packet-to-packet variation at fixed detector seeds.

## Component and parameter experiments

```matlab
addpath('Revision');
config = struct('maxPackets',30);
config.categories = {'Full','Ablation','Sensitivity','Sparsity','AddedEvents','Runtime'};
config.resultPrefix = 'revision_shapes';
runRevisionExperiments('datasets/shapes_6dof_events.mat',config);
config.resultPrefix = 'revision_urban';
runRevisionExperiments('datasets/urban_events.mat',config);
config.resultPrefix = 'revision_office';
runRevisionExperiments('datasets/office_spiral_events.mat',config);
plotRevisionAnalysis;
plotRevisionExamples;
```

For the separate estimation/support weight ablations:

```matlab
config = struct('categories',{{'Full','Ablation'}}, ...
    'resultPrefix','component_split', ...
    'outputFolder',fullfile(pwd,'Revision','results','component_split'));
runRevisionExperiments([],config);
```

For the 4,500 constructed local neighborhoods and the three-line example:

```matlab
runLocalVerification;
plotLocalVerification;
runThreeLineExample;
```

These local experiments generate their own inputs. [ComponentAblation_README.md](Revision/ComponentAblation_README.md) specifies the geometry, noise conditions and matching tolerances.

## Results and scope

Scripts write new results to `Revision/results`. The corresponding reported CSV files are kept separately in `expected_results`. Detection and evaluation parameters are defined in the experiment scripts; an `EventLineDBSCAN` instance provides the LLGD defaults.

The frame-derived reference evaluates event support independently in each packet. In the Table IV comparison, all methods receive only events. The reference does not supply temporal identities or manually annotated endpoints.

The release provides the code, fixed sample selections, evaluation settings and reference outputs for the quantitative experiments in Tables IV-IX. Public recordings, pretrained weights and third-party source code are obtained from their original sources using [DATASETS.md](DATASETS.md) and [DEPENDENCIES.md](DEPENDENCIES.md); they are not redistributed here. The FE-LSD models are evaluated with released checkpoints, not retrained. Reference outputs permit a separate check of the evaluation without repeating detector inference. Timings depend on hardware, and GPU predictions can vary slightly with the software and hardware environment.

## License

The code is distributed under the MIT license; see [LICENSE](LICENSE). External datasets and software retain their own licenses.
