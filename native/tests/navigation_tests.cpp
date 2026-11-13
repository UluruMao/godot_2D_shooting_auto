#include "pathfinding.hpp"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>

using namespace shooter;
static int checks = 0;
static void check(bool condition, const char *message) {
    ++checks;
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}

// Independent O(V^2) four-neighbor Dijkstra oracle: no heap or A* code reused.
static double oracle(const Grid &g) {
    const int size = g.width * g.height;
    std::vector<double> distance(size, std::numeric_limits<double>::infinity());
    std::vector<bool> done(size, false);
    distance[0] = 0.0;
    for (int i = 0; i < size; ++i) {
        int current = -1;
        for (int j = 0; j < size; ++j)
            if (!done[j] && (current < 0 || distance[j] < distance[current])) current = j;
        if (current < 0 || !std::isfinite(distance[current])) break;
        done[current] = true;
        const int x = current % g.width, y = current / g.width;
        const GridCoord adjacent[] = {{x-1,y},{x+1,y},{x,y-1},{x,y+1}};
        for (auto cell : adjacent) {
            if (cell.x < 0 || cell.y < 0 || cell.x >= g.width || cell.y >= g.height) continue;
            const int next = cell.y * g.width + cell.x;
            if (!g.blocked[next]) distance[next] = std::min(distance[next], distance[current] + 1.0 + g.risk[next]);
        }
    }
    return distance.back();
}

int main() {
    MinHeap heap;
    HeapEntry entry;
    check(!heap.try_pop(entry), "empty heap is safe");
    std::mt19937 random(12345);
    std::vector<double> ordered;
    for (int i = 0; i < 500; ++i) {
        double priority = random() % 1000;
        ordered.push_back(priority);
        heap.push({i, priority, 0.0, static_cast<std::uint64_t>(i)});
    }
    std::sort(ordered.begin(), ordered.end());
    for (double priority : ordered) check(heap.try_pop(entry) && entry.priority == priority, "heap yields sorted priorities");
    heap.push({1, 2.0, 0.0, 10}); heap.push({2, 2.0, 0.0, 11});
    check(heap.try_pop(entry) && entry.cell == 1, "heap preserves insertion tie");
    heap.try_pop(entry);

    Grid grid{3, 3, std::vector<std::uint8_t>(9, 0), {}};
    auto result = find_path(grid, {0,0}, {2,2});
    check(result.status == SearchStatus::Found && std::abs(result.cost - 2*std::sqrt(2.0)) < 1e-9, "diagonal shortest route");
    check(result.path.front() == GridCoord{0,0} && result.path.back() == GridCoord{2,2}, "path includes endpoints");
    check(find_path(grid, {0,0}, {0,0}).path.size() == 1, "start equals goal");
    check(find_path(grid, {0,0}, {2,2}, 0).status == SearchStatus::BudgetExceeded, "budget distinct from unreachable");
    check(find_path(grid, {-1,0}, {2,2}).status == SearchStatus::InvalidInput, "out of bounds rejected");
    grid.blocked[1] = grid.blocked[3] = 1;
    check(find_path(grid, {0,0}, {2,2}).status == SearchStatus::Unreachable, "cannot cut a blocked corner");
    grid.risk.assign(9, -1.0);
    check(find_path(grid, {0,0}, {2,2}).status == SearchStatus::InvalidInput, "negative costs rejected");
    check(find_path(Grid{2000000000, 2000000000, {}, {}}, {0,0}, {0,0}).status == SearchStatus::InvalidInput, "dimension overflow rejected before allocation");

    for (int trial = 0; trial < 100; ++trial) {
        Grid fixture{8, 8, std::vector<std::uint8_t>(64, 0), std::vector<double>(64, 0.0)};
        for (int i = 1; i < 63; ++i) {
            fixture.blocked[i] = random() % 5 == 0;
            fixture.risk[i] = (random() % 10) / 3.0;
        }
        const auto expected = oracle(fixture);
        const auto actual = find_path(fixture, {0,0}, {7,7}, 4096, false);
        check(std::isfinite(expected) ? actual.status == SearchStatus::Found && std::abs(expected-actual.cost) < 1e-8
                                      : actual.status == SearchStatus::Unreachable, "weighted A* matches independent Dijkstra");
        const auto repeated = find_path(fixture, {0,0}, {7,7}, 4096, false);
        check(actual.path == repeated.path, "same snapshot produces same route");
    }
    std::cout << "Navigation checks: " << checks << "; failures: 0\n";
}
