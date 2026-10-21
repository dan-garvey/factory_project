#include "factory/opening_engineering.hpp"
#include "factory/mechanics.hpp"

#include <algorithm>
#include <optional>
#include <vector>

namespace factory::opening_engineering {
namespace {
using V = values::Value;
using O = V::Object;
constexpr Definition content{
    "Upstream drive",
    "Move the waterwheel to the upper stream connection. Use the parts you already carry to bring back four more plates.",
    "Move the stocked line upstream, recovering its contents before rebuilding the drive.",
    "Keep the stocked line here and use cogs and shafts to transfer rotation between rows.",
    {-2, 0}, 4, 8,
};

template<class T> const T* field(const O& object, const char* key) {
    const auto found = object.find(key);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

std::optional<mechanics::Point> point(const O& object) {
    const auto* values = field<V::Array>(object, "center");
    if (!values || values->size() != 3) return std::nullopt;
    mechanics::Point result{};
    for (std::size_t i = 0; i < result.size(); ++i) {
        const auto* value = std::get_if<Count>(&values->at(i).storage());
        if (!value) return std::nullopt;
        result[i] = *value;
    }
    return result;
}

std::optional<mechanics::Part> shaft(const O& parts, const std::string& id) {
    const auto found = parts.find(id);
    const auto* part = found == parts.end() ? nullptr : std::get_if<O>(&found->second.storage());
    const auto* kind = part ? field<std::string>(*part, "kind") : nullptr;
    const auto* axis = part ? field<Count>(*part, "axis") : nullptr;
    const auto* half = part ? field<Count>(*part, "half_span") : nullptr;
    const auto center = part ? point(*part) : std::nullopt;
    if (!kind || *kind != "shaft" || !axis || *axis < 0 || *axis > 2 || !half || !center) return std::nullopt;
    return mechanics::Part{id, mechanics::Kind::shaft, *center, static_cast<mechanics::Axis>(*axis), 0, *half};
}

// Follow the same tile geometry, direction, endpoint feeding and loose-item
// handoff used by World::tick. A rotating but disconnected or backwards span
// must not satisfy the challenge.
bool forward_route(const O& spans, const O& parts, const O& motion,
                   const mechanics::Point& collector, const mechanics::Point& processor) {
    struct Lane { mechanics::BeltPath path; int direction; mechanics::Point before, after; };
    std::vector<Lane> lanes;
    for (const auto& [id, value] : spans) {
        (void)id;
        const auto* span = std::get_if<O>(&value.storage());
        const auto* from = span ? field<std::string>(*span, "from") : nullptr;
        const auto* to = span ? field<std::string>(*span, "to") : nullptr;
        if (!from || !to) return false;
        const auto first = shaft(parts, *from), last = shaft(parts, *to);
        const auto found = motion.find(*from);
        const auto* entry = found == motion.end() ? nullptr : std::get_if<O>(&found->second.storage());
        const auto* state = entry ? field<std::string>(*entry, "state") : nullptr;
        const auto* numerator = entry ? field<Count>(*entry, "numerator") : nullptr;
        const auto* denominator = entry ? field<Count>(*entry, "denominator") : nullptr;
        if (!first || !last || !state || !numerator || !denominator) return false;
        const auto path = mechanics::belt_path(*first, *last);
        if (!path) return false;
        if (*state != "rotating") continue;
        const auto direction = mechanics::belt_cargo_direction(*first, *last, {*numerator, *denominator});
        if (!direction || *direction == 0) continue;
        auto before = path->tiles.front(), after = path->tiles.back();
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const auto step = path->tiles[1][axis] - path->tiles[0][axis];
            before[axis] -= step;
            after[axis] += step;
        }
        lanes.push_back({*path, *direction, before, after});
    }
    std::vector<bool> reached(lanes.size());
    std::vector<std::size_t> pending;
    for (std::size_t i = 0; i < lanes.size(); ++i) {
        if ((lanes[i].direction > 0 && lanes[i].before == collector) ||
            (lanes[i].direction < 0 && lanes[i].after == collector)) {
            reached[i] = true;
            pending.push_back(i);
        }
    }
    for (std::size_t cursor = 0; cursor < pending.size(); ++cursor) {
        const auto& lane = lanes[pending[cursor]];
        const auto& output = lane.direction > 0 ? lane.after : lane.before;
        if (output == processor) return true;
        for (std::size_t i = 0; i < lanes.size(); ++i) {
            if (!reached[i] && std::find(lanes[i].path.tiles.begin(), lanes[i].path.tiles.end(), output) != lanes[i].path.tiles.end()) {
                reached[i] = true;
                pending.push_back(i);
            }
        }
    }
    return false;
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
    const auto* spans = field<O>(*root, "belt_spans");
    if (!inventories || !entities || !motion || !transmission || !spans) return {};
    const auto inventory = inventories->find(actor);
    if (inventory == inventories->end()) return {};
    const auto* products = std::get_if<Count>(&inventory->second.storage());
    if (!products || *products < 0) return {};
    Progress progress;
    progress.products = *products;
    unsigned machines{}, running{};
    std::optional<mechanics::Point> collector, processor;
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
        } else if (*kind == "collector" || *kind == "processor") {
            ++machines;
            if (*kind == "collector") collector = point(*part);
            else processor = point(*part);
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
    progress.machines_running = machines == 2 && running == 2;
    if (collector && processor) progress.belt_forward = forward_route(*spans, *transmission, *motion, *collector, *processor);
    if (*products < content.first_target) progress.phase = Phase::first_shift;
    else if (!progress.source_at_target) progress.phase = Phase::move_source;
    else if (!progress.machines_running || !progress.belt_forward) progress.phase = Phase::restore_drive;
    else if (*products < content.target) progress.phase = Phase::deliver_more;
    else progress.phase = Phase::ready;
    return progress;
}
}  // namespace factory::opening_engineering
