#include "factory/opening_engineering.hpp"

namespace factory::opening_engineering {

values::Value format_progress(const Progress& progress, const std::string& actor) {
    using V = values::Value;
    const auto& content = definition();
    return V(V::Object{
        {"schema", V(Count{1})}, {"format", V("factory-opening-engineering")},
        {"actor", V(actor)}, {"phase", V(phase_name(progress.phase))},
        {"known_actor", V(progress.phase != Phase::unavailable)},
        {"products", V(progress.products)}, {"first_target", V(content.first_target)}, {"target", V(content.target)},
        {"wheel_cell", V(V::Array{V(content.wheel_cell[0]), V(content.wheel_cell[1])})},
        {"source_at_target", V(progress.source_at_target)}, {"machines_running", V(progress.machines_running)},
        {"belt_forward", V(progress.belt_forward)},
        {"placed_gears", V(progress.placed_gears)}, {"placed_shafts", V(progress.placed_shafts)},
        {"ready", V(progress.phase == Phase::ready)},
        {"title", V(std::string(content.title))}, {"brief", V(std::string(content.brief))},
        {"relocate_hint", V(std::string(content.relocate_hint))}, {"gear_hint", V(std::string(content.gear_hint))},
    });
}

values::Value projection(const godot_world::Host& host, const std::string& actor) {
    return format_progress(inspect(host, actor), actor);
}
}  // namespace factory::opening_engineering
