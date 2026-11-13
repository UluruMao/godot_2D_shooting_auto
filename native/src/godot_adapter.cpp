#include "pathfinding.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {
class ShooterPathfinder : public RefCounted {
    GDCLASS(ShooterPathfinder, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("find_path", "blocked", "width", "height", "start", "goal", "risk", "budget", "diagonal"),
                            &ShooterPathfinder::find_path);
    }
public:
    Dictionary find_path(const PackedByteArray &blocked, int64_t width, int64_t height,
                         Vector2i start, Vector2i goal, const PackedFloat64Array &risk,
                         int64_t budget, bool diagonal) const {
        shooter::SearchResult result;
        if (width > 0 && height > 0 && width <= 1048576 && height <= 1048576 &&
            width * height <= 1048576 && budget >= 0 && budget <= 1048576) {
            shooter::Grid grid;
            grid.width = static_cast<int>(width);
            grid.height = static_cast<int>(height);
            if (!blocked.is_empty()) grid.blocked.assign(blocked.ptr(), blocked.ptr() + blocked.size());
            if (!risk.is_empty()) grid.risk.assign(risk.ptr(), risk.ptr() + risk.size());
            result = shooter::find_path(grid, {start.x, start.y}, {goal.x, goal.y}, static_cast<int>(budget), diagonal);
        }
        PackedVector2Array path;
        for (auto cell : result.path) path.push_back(Vector2(cell.x, cell.y));
        PackedInt32Array explored;
        for (auto cell : result.explored) explored.push_back(cell);
        Dictionary output;
        output["status"] = shooter::status_name(result.status);
        output["path"] = path;
        output["explored"] = explored;
        output["cost"] = result.cost;
        output["frontier_peak"] = static_cast<int64_t>(result.frontier_peak);
        return output;
    }
};

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(ShooterPathfinder);
}
static void terminate(ModuleInitializationLevel) {}
} // namespace godot

extern "C" {
GDExtensionBool GDE_EXPORT shooter_navigation_init(GDExtensionInterfaceGetProcAddress address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(address, library, initialization);
    init.register_initializer(godot::initialize);
    init.register_terminator(godot::terminate);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
