#include "pathfinding.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace shooter {

bool MinHeap::before(const HeapEntry &a, const HeapEntry &b) noexcept {
    if (a.priority != b.priority) return a.priority < b.priority;
    const double ah = a.priority - a.cost, bh = b.priority - b.cost;
    if (ah != bh) return ah < bh;
    return a.sequence < b.sequence;
}

void MinHeap::push(HeapEntry entry) {
    entries_.push_back(entry);
    auto child = entries_.size() - 1;
    while (child > 0) {
        const auto parent = (child - 1) / 2;
        if (!before(entries_[child], entries_[parent])) break;
        std::swap(entries_[child], entries_[parent]);
        child = parent;
    }
}

bool MinHeap::try_pop(HeapEntry &entry) {
    if (entries_.empty()) return false;
    entry = entries_.front();
    entries_.front() = entries_.back();
    entries_.pop_back();
    std::size_t parent = 0;
    while (parent * 2 + 1 < entries_.size()) {
        auto child = parent * 2 + 1;
        if (child + 1 < entries_.size() && before(entries_[child + 1], entries_[child])) ++child;
        if (!before(entries_[child], entries_[parent])) break;
        std::swap(entries_[child], entries_[parent]);
        parent = child;
    }
    return true;
}

SearchResult find_path(const Grid &grid, GridCoord start, GridCoord goal, int budget, bool diagonal) {
    SearchResult result;
    constexpr std::int64_t max_cells = 1024 * 1024;
    const auto size64 = std::int64_t(grid.width) * grid.height;
    if (grid.width <= 0 || grid.height <= 0 || size64 > max_cells || size64 <= 0 ||
        static_cast<std::size_t>(size64) != grid.blocked.size() || budget < 0 ||
        (!grid.risk.empty() && grid.risk.size() != grid.blocked.size())) return result;
    for (double risk : grid.risk) if (!std::isfinite(risk) || risk < 0.0 || risk > 1e12) return result;
    const auto in_bounds = [&](GridCoord cell) {
        return cell.x >= 0 && cell.y >= 0 && cell.x < grid.width && cell.y < grid.height;
    };
    if (!in_bounds(start) || !in_bounds(goal)) return result;
    const auto index = [&](GridCoord cell) { return cell.y * grid.width + cell.x; };
    const int source = index(start), target = index(goal), size = static_cast<int>(size64);
    if (grid.blocked[source] || grid.blocked[target]) return result;
    const double diagonal_cost = std::sqrt(2.0);
    const auto heuristic = [&](GridCoord cell) {
        const double dx = std::abs(cell.x - goal.x), dy = std::abs(cell.y - goal.y);
        return diagonal ? std::max(dx, dy) + (diagonal_cost - 1.0) * std::min(dx, dy) : dx + dy;
    };
    std::vector<double> costs(size, std::numeric_limits<double>::infinity());
    std::vector<int> parents(size, -1);
    std::vector<std::uint8_t> closed(size, 0);
    MinHeap frontier;
    std::uint64_t sequence = 0;
    costs[source] = 0.0;
    frontier.push({source, heuristic(start), 0.0, sequence++});
    // Fixed order makes equal-input searches reproducible.
    constexpr GridCoord offsets[] = {{0,-1}, {1,0}, {0,1}, {-1,0}, {1,-1}, {1,1}, {-1,1}, {-1,-1}};
    HeapEntry current;
    while (!frontier.empty()) {
        result.frontier_peak = std::max(result.frontier_peak, frontier.size());
        frontier.try_pop(current);
        if (closed[current.cell] || current.cost > costs[current.cell]) continue;
        if (static_cast<int>(result.explored.size()) >= budget) {
            result.status = SearchStatus::BudgetExceeded;
            return result;
        }
        closed[current.cell] = 1;
        result.explored.push_back(current.cell);
        if (current.cell == target) {
            for (int cell = target; cell >= 0; cell = parents[cell])
                result.path.push_back({cell % grid.width, cell / grid.width});
            std::reverse(result.path.begin(), result.path.end());
            result.status = SearchStatus::Found;
            result.cost = costs[target];
            return result;
        }
        const GridCoord from{current.cell % grid.width, current.cell / grid.width};
        for (int direction = 0; direction < (diagonal ? 8 : 4); ++direction) {
            const auto step = offsets[direction];
            const GridCoord next{from.x + step.x, from.y + step.y};
            if (!in_bounds(next) || grid.blocked[index(next)]) continue;
            if (direction >= 4 && (grid.blocked[index({next.x, from.y})] || grid.blocked[index({from.x, next.y})])) continue;
            const int neighbor = index(next);
            if (closed[neighbor]) continue;
            const double risk = grid.risk.empty() ? 0.0 : grid.risk[neighbor];
            const double candidate = current.cost + (direction >= 4 ? diagonal_cost : 1.0) * (1.0 + risk);
            if (candidate >= costs[neighbor]) continue;
            costs[neighbor] = candidate;
            parents[neighbor] = current.cell;
            frontier.push({neighbor, candidate + heuristic(next), candidate, sequence++});
        }
    }
    result.status = SearchStatus::Unreachable;
    return result;
}

const char *status_name(SearchStatus status) noexcept {
    switch (status) {
        case SearchStatus::Found: return "found";
        case SearchStatus::Unreachable: return "unreachable";
        case SearchStatus::BudgetExceeded: return "budget_exceeded";
        default: return "invalid_input";
    }
}

} // namespace shooter
