#include "factory/opening_engineering.hpp"

namespace factory::opening_engineering {
namespace {
using V = values::Value;
using O = V::Object;
constexpr Definition content{
    "Upstream drive",
    "Move the waterwheel to the upper stream connection. Use the parts you already carry to bring back four more plates.",
    "Move the stocked line upstream: recover and rebuild its three machines, reuse straight shafts and keep both cogs spare.",
    "Keep the stocked line here: spend the two cogs to transfer rotation between rows and preserve the three machine placements.",
    {-1, 0}, 4, 8,
};

template<class T> const T* field(const O& object, const char* key) {
    const auto found = object.find(key);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}
}  // namespace

const Definition& definition() noexcept { return content; }

const char* phase_name(Phase phase) noexcept {
    switch (phase) {
        case Phase::unavailable: return "unavailable";
        case Phase::first_shift: return "first_shift";
        case Phase::move_source: return "move_source";
        case Phase::restore_drive: return "restore_drive";
        case Phase::deliver_more: return "deliver_more";
        case Phase::ready: return "ready";
    }
    return "unknown";
}

Progress inspect(const godot_world::Host& host, const std::string& actor) {
    const auto projection = host.projection();
    const auto* root = std::get_if<O>(&projection.storage());
    if (!root) return {};
    const auto* inventories = field<O>(*root, "inventories");
    const auto* entities = field<O>(*root, "entities");
    const auto* motion = field<O>(*root, "motion");
    const auto* transmission = field<O>(*root, "transmission_parts");
    if (!inventories || !entities || !motion || !transmission) return {};
    const auto inventory = inventories->find(actor);
    if (inventory == inventories->end()) return {};
    const auto* products = std::get_if<Count>(&inventory->second.storage());
    if (!products || *products < 0) return {};
    Progress progress;
    progress.products = *products;
    unsigned machines{}, running{};
    for (const auto& [id, value] : *entities) {
        const auto* part = std::get_if<O>(&value.storage());
        if (!part) return {};
        const auto* kind = field<std::string>(*part, "kind");
        if (!kind) return {};
        if (*kind == "wheel") {
            const auto* cell = field<V::Array>(*part, "cell");
            if (!cell || cell->size() != 2) return {};
            const auto* x = std::get_if<Count>(&cell->at(0).storage());
            const auto* z = std::get_if<Count>(&cell->at(1).storage());
            if (!x || !z) return {};
            progress.source_at_target = *x == content.wheel_cell[0] && *z == content.wheel_cell[1];
        } else if (*kind == "collector" || *kind == "belt" || *kind == "processor") {
            ++machines;
            const auto found = motion->find(id);
            if (found == motion->end()) return {};
            const auto* entry = std::get_if<O>(&found->second.storage());
            const auto* state = entry ? field<std::string>(*entry, "state") : nullptr;
            if (!state) return {};
            running += *state == "rotating";
        }
    }
    for (const auto& [id, value] : *transmission) {
        (void)id;
        const auto* part = std::get_if<O>(&value.storage());
        const auto* kind = part ? field<std::string>(*part, "kind") : nullptr;
        if (!kind) return {};
        if (*kind == "gear") ++progress.placed_gears;
        else if (*kind == "shaft") ++progress.placed_shafts;
    }
    progress.machines_running = machines == 3 && running == 3;
    if (*products < content.first_target) progress.phase = Phase::first_shift;
    else if (!progress.source_at_target) progress.phase = Phase::move_source;
    else if (!progress.machines_running) progress.phase = Phase::restore_drive;
    else if (*products < content.target) progress.phase = Phase::deliver_more;
    else progress.phase = Phase::ready;
    return progress;
}
}  // namespace factory::opening_engineering
