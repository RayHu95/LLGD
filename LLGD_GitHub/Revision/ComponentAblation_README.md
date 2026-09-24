# Component experiments

Run `runRevisionExperiments([], config)` with `config.categories = {'Full','Ablation'}` and a separate output folder. The existing 30 packets from each of `shapes_6dof`, `urban`, and `office_spiral` are used without changing their frame-derived references, thresholds, or seed rule.

`UseWeights` controls RANSAC scores, total-least-squares fitting, two-cluster initialization and center updates, and the ordinary MAD scores. `UseMultiplicitySupport` controls the multiplicity precheck, high-weight pixel eligibility and ratios, cluster support counts, and high-weight MAD scores. Its empty default follows `UseWeights`. The ablations vary these controls separately and jointly. In the unit-support variant, every unique pixel is eligible and has support weight one; each cluster in the two-line branch requires at least five unique pixels, while estimation weights remain unchanged. The event inlier ratio always counts the original events.

`runLocalVerification` generates a fixed grid of pixel-quantized local neighborhoods within the original normalized spatial radius 0.02 at 240 x 180 resolution. It tests one line, corners (60, 90, 120 degrees), crossings (30, 60, 90 degrees), and parallel lines with a nominal separation of 3 pixels before quantization. Orientations are 0:15:165 degrees.

Unique line pixels receive 1, 3, or 5 events each, followed by 0%, 25%, or 50% uniform added events relative to that count. A shared corner/crossing pixel is counted once before applying multiplicity. Each grid condition has five realizations; without added noise, these share their input geometry and differ in detector seed.

Noise-only neighborhoods contain 24, 72, or 120 independent uniformly sampled pixel events, with 60 realizations per budget. They contain no imposed line, although chance alignments can occur. There are 4,500 neighborhood trials in total: 180 noise-only, 540 single-line, 1,620 corner, 1,620 crossing, and 540 parallel-line trials. The geometry classes and multiplicity levels are reported separately.

The local variants are the complete module, acceptance of the initial RANSAC result, and the inlier-ratio test alone (rejection when it fails). All three retain the original multiplicity precheck. Every variant receives the same samples and detector seed. The full sample set is generated and saved before detection.

Line count and one-to-one geometric recovery are recorded separately. A match requires an orientation error at most 15 degrees and an RMS distance at most 1 pixel from the quantized true support to the predicted infinite line. The paired alternatives (10 degrees, 0.75 pixel) and (20 degrees, 1.25 pixels) are also reported. Exact recovery requires all true lines to match and the predicted count to equal the true count. Noise-only rejection is reported separately. These constructed neighborhoods test local geometry, not sensor-specific noise or end-to-end scene performance.

All condition-level records and models are retained under `Revision/results/component_split`. The sample generator uses seed 2025; detector seeds are `2025 + 100000 + 1000*sampleIndex + 1`.

`runThreeLineExample` reproduces Fig. R2 in the response. Three lines at pixel-plane angles 0, 60, and 120 degrees meet at the neighborhood center. The quantized union has 27 pixels, each repeated three times, without added noise. Five calls use default parameters and seeds 2025:2029 on this fixed input. Models, assignments, geometric errors and the first-call figure are saved under `Revision/results/three_line`.
