# Reproducing the revised experiments

Run MATLAB from the repository root with `addpath('Revision')`. Run Python commands from the same root using the environment in [DEPENDENCIES.md](DEPENDENCIES.md). Newly computed outputs go to `Revision/results`; the reported outputs remain in `expected_results`.

| Manuscript result | Scripts | Reported output |
| --- | --- | --- |
| Fig. 2 | `plotIntermediateExamples` | `intermediate/intermediate_examples.csv` and figure |
| Table IV; Figs. 3-4 | `runComparisonExperiments`, `computePairedF1Intervals`, `plotComparisonExamples`, `plotRevisionExamples` | `comparison_four_summary.csv`, `comparison_four_paired_f1.csv` |
| Table V | FE-Blurframe procedure below | `fe_blurframe_three_method_metrics.csv` |
| Table VI | Continuous-stream procedure below | `rt_evldt/summary.csv` at tolerance 6 |
| Table VII | `runRevisionExperiments`, Full/Ablation and separate weight settings in README | `revision_*_summary.csv`, `component_split/*` |
| Table VIII; Fig. 5 | `runRevisionExperiments`, sensitivity/sparsity/added-event settings in README; `plotRevisionAnalysis` | `revision_*_summary.csv` |
| Table IX | `runLocalVerificationGeometry`, `evaluateLocalVerificationGeometry.py` | `local_verification_geometry/summary.csv` at tolerance 6 |
| Constructed local tests; response three-line example | `runLocalVerification`, `plotLocalVerification`, `runThreeLineExample` | `component_split/local_verification_detail.csv`, `three_line/three_line_results.csv` |

The packet comparison and component-study commands are in the main README. Tables I-III describe the datasets and comparison scope. Fig. 1 is a method diagram.

## Intermediate fitting example: Fig. 2

After preparing `shapes_6dof_events.mat`, run in MATLAB:

```matlab
plotIntermediateExamples;
```

The three neighborhoods use packet 24 and event indices 16, 449 and 166. `intermediate_examples.csv` records the packet, source frame and event indices, seeds, and local support tests. The public reference outputs contain the CSV and rendered figure. Running the script also saves the source events, assignments and fitted models in `intermediate_examples.mat`.

## FE-Blurframe: Table V

Download the FE-Blurframe test annotations, blurred images, two checkpoints and the RE-LSD auxiliary event archive as described in [DATASETS.md](DATASETS.md). After obtaining the FE-LSD source:

```sh
python Revision/prepareFEBlurframeSubset.py
python Revision/runFEBlurframeBaselines.py
```

LLGD inference uses one MATLAB computational thread. From the repository root:

```sh
matlab -singleCompThread -batch "addpath('Revision'); runFEBlurframeGeometry"
```

Then:

```sh
python Revision/evaluateFEBlurframeResults.py
```

The preparation selects the intersection of the official test split and files with continuous timestamps in `events_FE-LSD_600.zip`, preserving test-file order. The 154 filenames, event counts and timestamp spans are recorded in `expected_results/fe_blurframe_subset.csv`. The FE-Blurframe `events_raw.zip` has boolean timestamps and is not substituted for this auxiliary archive.

FE-HAWP and FE-ULSD receive the blurred image and events; LLGD receives only events. The released FE-LSD evaluator scores all predictions without a score cutoff. LLGD converts event-supported planes to segments at the end of the 30-ms exposure. All methods use the same test examples and annotations. This evaluates a specific availability subset, not the complete FE-Blurframe test set.

## Continuous-stream comparison: Table VI

Place `urban` and `office_spiral` recordings under `datasets`, and HQF `boxes.bag` under `datasets/hqf`. Prepare all three sequences:

```sh
python Revision/prepareRTComparison.py
```

In MATLAB:

```matlab
addpath('Revision');
runRTComparisonLLGD;
```

From the repository root in Ubuntu, after the RT-EvLDT build:

```sh
for seq in urban office_spiral hqf_boxes; do
  .build/rt/rt_evldt_offline "Revision/results/rt_evldt/$seq/events.bin" "Revision/results/rt_evldt/$seq/frames.txt" "Revision/results/rt_evldt/$seq/rt"
done
```

Then, in the Python environment:

```sh
python Revision/evaluateRTComparison.py
python Revision/plotRTComparison.py
```

The comparison uses every frame in [5,10) s: 130 urban, 113 office_spiral and 105 HQF boxes frames. RT-EvLDT starts from the beginning of the stream. Each frame is paired with the last 600-Hz update at or before its timestamp; LLGD receives the preceding 20 ms. HQF image and event times share an origin, subtracted in integer nanoseconds.

RT-EvLDT uses block size 8, buffer ratio 1, fitting and inlier thresholds 0.2, and endpoint perturbation 1.1 pixels. LLGD uses seed `2025 + 100000*s + 1000*i + 1`, where `s` is the sequence index and `i` is the original frame index.

OpenCV LSD supplies the frame-derived reference. One-pixel-wide line maps are matched one-to-one by maximum-cardinality pixel matching within 6 pixels. Counts are accumulated over each sequence before precision, recall and F1 are computed. Results at 3 and 9 pixels are also retained. The separate C++/MATLAB timing files are not used for a cross-language runtime claim in Table VI.

## Real-scene local-verification ablation: Table IX

After the continuous-stream inputs and full LLGD outputs have been generated, run in MATLAB:

```matlab
runLocalVerificationGeometry;
```

Then:

```sh
python Revision/evaluateLocalVerificationGeometry.py
```

This reruns all 348 frames with only `UseVerification` disabled. Initial multiplicity filtering, weighted fitting, global expansion, seeds and segment conversion are unchanged. Both variants use the same frame-derived reference and matching tolerances as Table VI.

## Re-evaluating the saved predictions

The reported segment predictions, frame-derived reference lines and summaries are included in `expected_results`. Copy its contents to an empty `Revision/results` folder, then run `evaluateRTComparison.py` and `evaluateLocalVerificationGeometry.py`. These checks need the Python dependencies, but no raw recordings, MATLAB, CUDA or RT-EvLDT build. They check scoring, not detector inference. Plotting still requires the source images.

For Table V, first prepare the 154-sample subset, then copy the three `fe_blurframe_*_result.json` prediction files from `expected_results` to `Revision/results`. Run `evaluateFEBlurframeResults.py`. The official annotations are read from the prepared subset and are not redistributed in the release. Run the detector commands above when independently recomputing predictions.
