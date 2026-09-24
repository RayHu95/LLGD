#include "ledge.h"
#include <chrono>
#include <fstream>
#include <iomanip>
#include <iostream>

#pragma pack(push, 1)
struct Event { double t; int x, y, p; };
#pragma pack(pop)

int main(int argc, char **argv) {
    if (argc != 4) return 1;
    std::ifstream input(argv[1], std::ios::binary | std::ios::ate);
    if (!input) return 1;
    const size_t bytes = input.tellg();
    std::vector<Event> events(bytes / sizeof(Event));
    input.seekg(0);
    input.read(reinterpret_cast<char *>(events.data()), bytes);
    std::ifstream frames(argv[2]);
    std::vector<std::pair<int, int>> samples;
    int index, tick;
    while (frames >> index >> tick) samples.emplace_back(index, tick);
    if (samples.empty()) return 1;
    std::ofstream output(std::string(argv[3]) + "_lines.csv");
    std::ofstream timing(std::string(argv[3]) + "_timing.csv");
    output << "Index,Tick,X1,Y1,X2,Y2,Score,Status\n" << std::setprecision(17);
    timing << "Tick,Events,Seconds\n" << std::setprecision(17);

    cv::setNumThreads(1);
    LEDGE ledge;
    ledge.initialise(cv::Size(240, 180), 8, 1.0, 0.2, 0.2, true, 1.1);
    cv::Size grid;
    std::tie(std::ignore, std::ignore, grid, std::ignore, std::ignore,
             std::ignore, std::ignore, std::ignore) = ledge.returnLedgeParameters();
    size_t event_pos = 0, sample_pos = 0;
    for (int step = 0; step <= 6000; ++step) {
        double time = step / 600.0;
        size_t begin = event_pos;
        auto start = std::chrono::steady_clock::now();
        while (event_pos < events.size() && events[event_pos].t <= time) {
            auto &e = events[event_pos++];
            ledge.update(e.x, e.y, e.p);
        }
        ledge.trackLinesAllBlock();
        ledge.checkDetectionProhibitions();
        ledge.manageLineAdmins();
        ledge.detectLines();
        double seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - start).count();
        timing << step << ',' << event_pos - begin << ',' << seconds << '\n';
        while (sample_pos < samples.size() && samples[sample_pos].second == step) {
            for (int y = 0; y < grid.height; ++y) {
                for (int x = 0; x < grid.width; ++x) {
                    auto line = ledge.returnLineSegment(x, y);
                    int status = std::get<4>(line);
                    if (status != 2 && status != 4) continue;
                    auto p1 = std::get<0>(line), p2 = std::get<1>(line);
                    output << samples[sample_pos].first << ',' << step << ','
                           << p1.x << ',' << p1.y << ',' << p2.x << ',' << p2.y << ','
                           << std::get<2>(line) << ',' << status << '\n';
                }
            }
            ++sample_pos;
        }
    }
    std::cout << event_pos << " events; " << sample_pos << " samples\n";
    return 0;
}
