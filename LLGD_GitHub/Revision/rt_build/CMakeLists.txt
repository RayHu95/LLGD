cmake_minimum_required(VERSION 3.16)
project(rt_evldt_comparison LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_BUILD_TYPE Release)
find_package(YARP COMPONENTS os sig cv REQUIRED)
find_package(event-driven REQUIRED)
find_package(OpenCV REQUIRED)
set(RT_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/RT-EvLDT-main/ledge)
add_executable(rt_evldt_offline ../rt_evldt_offline.cpp
    ${RT_SOURCE}/core.cpp ${RT_SOURCE}/detection.cpp
    ${RT_SOURCE}/tracking.cpp ${RT_SOURCE}/manager.cpp)
target_include_directories(rt_evldt_offline PRIVATE ${RT_SOURCE} ${OpenCV_INCLUDE_DIRS})
target_compile_options(rt_evldt_offline PRIVATE -O3 -mtune=native -march=native -mfpmath=both)
target_link_libraries(rt_evldt_offline PRIVATE ev::event-driven ${OpenCV_LIBS})
