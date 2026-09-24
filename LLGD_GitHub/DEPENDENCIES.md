# Experiment dependencies

Run the commands below from the repository root. Use a new environment for these experiments.

## Python

The reported runs used Python 3.12.13 on Windows, PyTorch 2.11.0+cu128 and torchvision 0.26.0+cu128. FE-LSD inference requires an NVIDIA GPU compatible with CUDA 12.8. The preparation and evaluation scripts run on the CPU.

```sh
python -m pip install torch==2.11.0 torchvision==0.26.0 --index-url https://download.pytorch.org/whl/cu128
python -m pip install -r requirements.txt
```

The fixed source snapshots used for the comparisons are:

| Component | Repository | Commit |
| --- | --- | --- |
| FE-LSD | https://github.com/lh9171338/FE-LSD | `7964d4757ac73b67196d07ecd7003d888877674b` |
| RT-EvLDT | https://github.com/event-driven-robotics/RT-EvLDT | `ef2159afbc4e6960cb667a8d44a263439d1c510d` |
| YCM | https://github.com/robotology/ycm | `7377904ee1534861bfd0a8de11e31ee7c8e1e2d9` |
| YARP | https://github.com/robotology/yarp | `81917f6d0d980fc9d4ad396c5fb07f7908cfb7f9` |
| event-driven | https://github.com/robotology/event-driven | `c791ac61eac7e47523c0b8add1978b4b3c9456b7` |

For FE-LSD:

```sh
git clone https://github.com/lh9171338/FE-LSD Revision/third_party/FE-LSD
git -C Revision/third_party/FE-LSD checkout 7964d4757ac73b67196d07ecd7003d888877674b
```

The wrapper uses the official `forward_test` inference and checkpoint conversion. A placeholder for the HAFM training encoder allows importing FE-HAWP without building its training extension; inference does not call that encoder. The legacy evaluator's `np.float` alias is mapped to `float`. Neither change alters the detector or evaluation formula.

## RT-EvLDT on Ubuntu 22.04

The reported replay used GCC 11.4.0 and OpenCV 4.5.4. Install build dependencies if needed:

```sh
sudo apt-get install build-essential cmake git libopencv-dev libeigen3-dev libace-dev
```

Clone the fixed sources and build into a local prefix; no camera driver, OpenEB installation or running YARP server is needed:

```sh
git clone https://github.com/event-driven-robotics/RT-EvLDT Revision/third_party/RT-EvLDT-main
git -C Revision/third_party/RT-EvLDT-main checkout ef2159afbc4e6960cb667a8d44a263439d1c510d
git clone https://github.com/robotology/ycm .build/ycm-src
git -C .build/ycm-src checkout 7377904ee1534861bfd0a8de11e31ee7c8e1e2d9
git clone https://github.com/robotology/yarp .build/yarp-src
git -C .build/yarp-src checkout 81917f6d0d980fc9d4ad396c5fb07f7908cfb7f9
git clone https://github.com/robotology/event-driven .build/event-src
git -C .build/event-src checkout c791ac61eac7e47523c0b8add1978b4b3c9456b7
prefix="$PWD/.build/prefix"
cmake -S .build/ycm-src -B .build/ycm -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --install .build/ycm
cmake -S .build/yarp-src -B .build/yarp -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_PREFIX_PATH="$prefix" -DBUILD_SHARED_LIBS=ON -DYARP_COMPILE_EXECUTABLES=OFF -DYARP_COMPILE_TESTS=OFF
cmake --build .build/yarp -j 6
cmake --install .build/yarp
cmake -S .build/event-src -B .build/event -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_PREFIX_PATH="$prefix" -DBUILD_SHARED_LIBS=ON -DVLIB_ENABLE_TS=OFF
cmake --build .build/event --target event-driven -j 6
cmake -P .build/event/ev2/cmake_install.cmake
cmake -DCMAKE_INSTALL_LOCAL_ONLY=1 -P .build/event/cmake_install.cmake
cmake -S Revision/rt_build -B .build/rt -DCMAKE_PREFIX_PATH="$prefix"
cmake --build .build/rt -j 6
```

The offline adapter links the unmodified `ledge.h`, `core.cpp`, `detection.cpp`, `tracking.cpp` and `manager.cpp`. It replays events sequentially at 600 Hz and saves accepted detections and successful tracks. The build uses the original x86 native-optimization flags.

## Third-party terms

Third-party repositories, datasets and weights retain their own licenses; the LLGD MIT license does not replace them. The FE-LSD source snapshot carries GPL-3.0, the RT-EvLDT source carries CC BY-NC-SA 4.0, and event-driven carries GPL-3.0. Keep the license files in all downloaded repositories. Consult the source repositories and dataset/model cards for their full terms.
