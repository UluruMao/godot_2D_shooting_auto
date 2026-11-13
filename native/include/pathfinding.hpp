#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace shooter {

struct GridCoord {
    int x = 0;
    int y = 0;
    bool operator==(const GridCoord &other) const noexcept { return x == other.x && y == other.y; }
    bool operator!=(const GridCoord &other) const noexcept { return !(*this == other); }
};

struct HeapEntry {
    int cell = 0;
    double priority = 0.0;
    double cost = 0.0;
    std::uint64_t sequence = 0;
};

// Stable priority ordering: lowest f, then lowest h, then insertion order.
class MinHeap {
public:
    void push(HeapEntry entry);
    bool try_pop(HeapEntry &entry);
    bool empty() const noexcept { return entries_.empty(); }
    std::size_t size() const noexcept { return entries_.size(); }
private:
    static bool before(const HeapEntry &a, const HeapEntry &b) noexcept;
    std::vector<HeapEntry> entries_;
};

struct Grid {
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> blocked;
    std::vector<double> risk; // Optional nonnegative cost per unit travelled.
};

enum class SearchStatus { Found, Unreachable, InvalidInput, BudgetExceeded };

struct SearchResult {
    SearchStatus status = SearchStatus::InvalidInput;
    std::vector<GridCoord> path;
    std::vector<int> explored;
    double cost = 0.0;
    std::size_t frontier_peak = 0;
};

SearchResult find_path(const Grid &grid, GridCoord start, GridCoord goal,
                       int expansion_budget = 4096, bool diagonal = true);
const char *status_name(SearchStatus status) noexcept;

} // namespace shooter
