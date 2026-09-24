# The line-based local-to-global detection method for event cameras

**Abstract**:
Event cameras report asynchronous brightness changes, and moving edges form line-like structures within short
spatio-temporal windows. Line segments are common geometric
features in structured environments, but separating two lines
that share a local neighborhood while rejecting geometrically
unsupported events remains difficult. This paper presents a linebased
local-to-global detection (LLGD) method that fits up to two
local line models and then expands their inlier events globally.
The local module combines pixel-multiplicity-weighted random sample consensus (RANSAC) with weighted total least
squares. If the one-line support tests fail, eligible neighborhoods
are partitioned into two clusters, and the fitted lines are verified
with an unscaled median absolute deviation (MAD) score. The global module expands each accepted inlier set on
its spatio-temporal plane. We evaluate 30 packets from each of four sequences in two public datasets, using acquisition
windows of up to 20 ms. Mean F1, the harmonic mean of
event-support precision and recall, ranges from 0.301 to 0.627 against frame-derived references, with scene-dependent
performance relative to the comparison methods. Global expansion improves coverage and reduces fragmentation; the
precision benefit of local verification depends on the scene. Comparisons with recent detectors
show limitations in endpoint localization and line coverage. The current MATLAB implementation has per-sequence mean
processing times of 0.125–1.163 s per packet.


## Code and example
The code and experiment instructions are in the LLGD_GitHub folder.

## Citations
If you find this work useful for you, please cite:
