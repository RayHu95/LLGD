# The line-based local-to-global detection method for event cameras

**Abstract**:
Event cameras inherently respond to the contour information of moving objects. Given that structured environments are typically rich in line-based geometric features, detecting line segments from sparse event streams is a crucial task.
Existing event-based line detection methods generally aggregate events with similar characteristics to estimate segments, but they often struggle when multiple lines intersect and are limited in filtering noisy events.
To address these issues, this paper proposes a line-based local-to-global detection (LLGD) method, which first distinguishes multiple lines locally and then globally expands the set of inlier events belonging to locally detected segments.
Specifically, for a given event, the local module estimates the segment with the highest number of inliers within its neighborhood, handling most single-line cases robustly. When two lines are connected, a two-step verification process is applied, followed by clustering and adaptive denoising to differentiate them. Subsequently, plane fitting in the global spatio-temporal space is employed to further extend the inlier event set for each segment.
Comparative experiments with existing line detection methods across various geometric shapes demonstrate the effectiveness of the proposed method. The implementation code is open-sourced to the community to support further research.

## Run
Coming soon

## Citations
If you find this work useful for you, please cite:
