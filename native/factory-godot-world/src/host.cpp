#include "factory/godot_world.hpp"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <optional>
#include <stdexcept>
#include <utility>

namespace factory::godot_world {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using Role = stationary::Role;

// Current opening geometry, explicitly checked by the thin scene adapter.
constexpr double pitch = 1.65;
constexpr double anchor_height = 0.5;
constexpr double reach = 4.0;
constexpr double capsule_radius = 0.3;
constexpr double capsule_height = 1.8;
constexpr double machine_width = 1.45;
constexpr double machine_height = 1.65;
constexpr double machine_center_height = 0.8;

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

Value result(bool accepted, const std::string& reason) {
    return Value(Object{{"accepted", Value(accepted)}, {"reason", Value(reason)}});
}

bool keys(const Object& object, std::initializer_list<const char*> extras) {
    if (object.size() != 4 + extras.size()) return false;
    for (const auto* key : {"context", "client", "request", "action"}) if (!object.contains(key)) return false;
    for (const auto* key : extras) if (!object.contains(key)) return false;
    return true;
}

std::optional<mechanics::Axis> axis_value(const std::string& name) {
    if (name == "x") return mechanics::Axis::x;
    if (name == "y") return mechanics::Axis::y;
    if (name == "z") return mechanics::Axis::z;
    return std::nullopt;
}

authority::Point gear_half_extents(mechanics::Axis axis, Integer teeth) {
    const auto radius = static_cast<double>(teeth) * pitch / 4;
    authority::Point half{radius, radius, radius};
    half[static_cast<std::size_t>(axis)] = 0.04; // Fixture disc half-thickness, not tooth physics.
    return half;
}

std::optional<mechanics::Point> gear_center(const Array& input) {
    if (input.size() != 3) return std::nullopt;
    mechanics::Point output;
    for (std::size_t index = 0; index < 3; ++index) {
        const auto* value = std::get_if<Integer>(&input[index].storage());
        if (!value || *value < (index == 1 ? 0 : -8) || *value > 16) return std::nullopt;
        output[index] = *value;
    }
    return output;
}

std::optional<authority::Point> point(const Array& values) {
    if (values.size() != 3) return std::nullopt;
    authority::Point output;
    for (std::size_t index = 0; index < 3; ++index) {
        if (const auto* value = std::get_if<double>(&values[index].storage())) output[index] = *value;
        else if (const auto* value = std::get_if<Integer>(&values[index].storage())) {
            // Reject a lossy observation conversion rather than moving a body.
            constexpr Integer exact_limit = 9007199254740992;
            if (*value < -exact_limit || *value > exact_limit) return std::nullopt;
            output[index] = static_cast<double>(*value);
        } else return std::nullopt;
        if (!std::isfinite(output[index])) return std::nullopt;
    }
    return output;
}

Value point_value(const authority::Point& point) {
    return Value(Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

// Check only the retained translation. Current parts, poses and generations
// cannot be used to reinterpret a historical request after removal or restore.
bool historical_wire(const authority::Record& record) {
    const auto& intent = record.intent;
    const auto* wire = field<Object>(intent, "wire");
    const auto* action = field<std::string>(intent, "action");
    const auto* accepted = field<bool>(record.result, "accepted");
    if (!wire || !action || !accepted) return false;
    if (*action == "adapter_refusal") return !*accepted;
    const auto* original_action = field<std::string>(*wire, "action");
    if (!original_action) return false;
    const auto same = [&](const char* original, const char* normalized) {
        const auto left = wire->find(original);
        const auto right = intent.find(normalized);
        return left != wire->end() && right != intent.end() &&
            !values::typed_difference(left->second, right->second);
    };
    if (*action == "place") {
        if (*original_action == "place_gear") {
            const auto* center = field<Array>(*wire, "center");
            const auto* axis = field<std::string>(*wire, "axis");
            const auto* teeth = field<Integer>(*wire, "teeth");
            return keys(*wire, {"center", "axis", "teeth"}) && center && gear_center(*center) &&
                axis && axis_value(*axis) && teeth && *teeth > 0 && *teeth <= mechanics::maximum_dimension &&
                same("center", "center") && same("axis", "axis") && same("teeth", "teeth") &&
                field<std::string>(intent, "role") && *field<std::string>(intent, "role") == "gear" &&
                field<Integer>(intent, "half_span") && *field<Integer>(intent, "half_span") == 0;
        }
        const auto* name = field<std::string>(*wire, "kind");
        const auto* cell = field<Array>(*wire, "cell");
        const auto* axis = field<std::string>(*wire, "axis");
        if (*original_action != "place" || !(wire->contains("axis") ? keys(*wire, {"kind", "cell", "axis"}) : keys(*wire, {"kind", "cell"})) ||
            (wire->contains("axis") && (!axis || !axis_value(*axis))) || !name || !cell || cell->size() != 2)
            return false;
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        if (!x || !z || *x < -2 || *x > 4 || *z < -2 || *z > 4 ||
            (*name != "collector" && *name != "belt" && *name != "processor" && *name != "wheel" && *name != "gear"))
            return false;
        const Object expected{{"role", Value(*name == "wheel" ? "waterwheel" : *name)},
            {"center", Value(Array{Value(4 * *x), Value(Integer{0}), Value(4 * *z)})},
            {"axis", Value(axis ? *axis : "x")}, {"teeth", Value(Integer{*name == "gear" ? 2 : 0})},
            {"half_span", Value(Integer{0})}};
        for (const auto& [key, value] : expected) {
            const auto found = intent.find(key);
            if (found == intent.end() || values::typed_difference(value, found->second)) return false;
        }
        return true;
    }
    if (*action == "link" || *action == "unlink" || *action == "shaft_between" || *action == "remove_shaft_between") {
        const auto mapped = *action == "link" ? "connect" : *action == "unlink" ? "disconnect" :
            *action == "shaft_between" ? "connect_drive" : "disconnect_drive";
        return *original_action == mapped && keys(*wire, {"from", "to"}) &&
            same("from", "target") && same("to", "to");
    }
    if (*action == "set_drive")
        return *original_action == "set_power" && keys(*wire, {"active"}) && same("active", "enabled");
    if (*action == "remove" || *action == "recover")
        return *original_action == *action && keys(*wire, {"entity"}) && same("entity", "target");
    if (*action == "collect" || *action == "insert_raw")
        return *original_action == (*action == "collect" ? "retrieve" : "insert_raw") &&
            keys(*wire, {"entity", "amount"}) && same("entity", "target") && same("amount", "amount");
    if (*action == "insert_work")
        return *original_action == "insert_work" && keys(*wire, {"entity", "work_id"}) &&
            same("entity", "target") && same("work_id", "work_id");
    return false;
}

const stationary::PlacedPart* find(const world::State& state, const std::string& id) {
    const auto found = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [&](const auto& part) { return part.geometry.id == id; });
    return found == state.topology.parts.end() ? nullptr : &*found;
}

const char* kind(Role role) {
    switch (role) {
        case Role::collector: return "collector";
        case Role::belt: return "belt";
        case Role::processor: return "processor";
        case Role::waterwheel: return "wheel";
        case Role::gear: return "gear";
        case Role::shaft: return "shaft";
    }
    return "invalid";
}

Value cargo_value(const materials::Cargo& cargo) {
    Array lots;
    for (const auto& lot : cargo.work_lots) lots.emplace_back(Object{
        {"id", Value(lot.id)}, {"recipe_input", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining", Value(lot.remaining_ticks)}});
    return Value(Object{{"raw", Value(cargo.raw_units)}, {"products", Value(cargo.products)},
                         {"work_lots", Value(std::move(lots))}});
}

Value kit_value(const stationary::Kit& kit) {
    Object counts{{"collector", Value(Integer{0})}, {"belt", Value(Integer{0})},
        {"processor", Value(Integer{0})}, {"wheel", Value(Integer{0})},
        {"shaft", Value(Integer{0})}, {"gear", Value(Integer{0})}};
    for (const auto& [specification, count] : kit) {
        const auto name = kind(specification.role);
        const auto previous = std::get<Integer>(counts.at(name).storage());
        if (count > std::numeric_limits<Integer>::max() - previous) throw std::overflow_error("Part projection overflow.");
        counts.at(name) = Value(previous + count);
    }
    return Value(std::move(counts));
}

Object outward(const world::Delivery& delivery, const world::Snapshot& snapshot) {
    Object output;
    if (delivery.result) output = *delivery.result;
    else output = Object{{"accepted", Value(false)},
        {"reason", Value(delivery.history_error == authority::Error::none ? "native_preparation_failed" :
                          authority::error_name(delivery.history_error))},
        {"entity", Value("")}, {"context", Value(snapshot.history.context)},
        {"revision", Value(snapshot.revision)}, {"order", Value(snapshot.history.order)}, {"duplicate", Value(false)}};
    // The current view consumes a nested receipt; the stored native result is
    // untouched. This is a detached presentation value, not another cache.
    const auto* actor = field<std::string>(output, "actor");
    const auto* position = field<Array>(output, "actor_position");
    const auto* targets = field<Array>(output, "targets");
    const auto* distances = field<Array>(output, "distances_squared");
    const auto* epoch = field<Integer>(output, "native_epoch");
    const auto* radius = field<double>(output, "build_reach");
    if (actor && position && targets && distances && epoch && radius)
        output.emplace("reach", Value(Object{{"actor", Value(*actor)}, {"position", Value(*position)},
            {"native_epoch", Value(*epoch)}, {"targets", Value(*targets)},
            {"distances_squared", Value(*distances)}, {"build_reach", Value(*radius)},
            {"reachable", Value(field<std::string>(output, "reason") && *field<std::string>(output, "reason") != "out_of_reach")}}));
    return output;
}
}  // namespace

Value Host::initialize(const std::string& context, const std::vector<std::string>& actors) {
    if (owned_) return result(false, "already_initialized");
    if (actors.empty() || actors.size() > 2 || actors.front() != "P") return result(false, "invalid_roster");
    world::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 16;
    profile.meters_per_grid_unit = pitch / 4.0;
    profile.anchor_offset = {0, anchor_height, 0};
    profile.build_reach = reach;
    profile.finite_parts = {{{Role::collector, 0, 0}, 1}, {{Role::belt, 0, 0}, 1},
        {{Role::processor, 0, 0}, 1}, {{Role::waterwheel, 0, 0}, 1}, {{Role::shaft, 0, 2}, 3},
        {{Role::gear, 2, 0}, 2}};
    world::State seed;
    seed.material.initial_units = 16;
    seed.material.stock.source = 16;
    auto candidate = std::make_unique<Owned>();
    for (const auto& actor : actors) {
        if ((actor != "P" && actor != "Q") || !profile.actors.insert(actor).second)
            return result(false, "invalid_roster");
        seed.material.cargo.emplace(actor, materials::Cargo{});
        seed.kits.emplace(actor, actor == "P" ? profile.finite_parts : stationary::Kit{});
        candidate->actors.emplace(actor, Actor{{-pitch, 1.0, (actor == "P" ? 2.0 : 3.0) * pitch}, 0, false});
    }
    candidate->world = world::World::create(context, profile, seed);
    if (!candidate->world) return result(false, "invalid_initial_world");
    profile_ = std::move(profile);
    owned_ = std::move(candidate);
    return result(true, "initialized");
}

world::ObserveActor Host::observe() const {
    return [this](const std::string& actor) -> std::optional<authority::ActorCut> {
        const auto found = owned_->actors.find(actor);
        if (found == owned_->actors.end()) return std::nullopt;
        return authority::ActorCut{actor, found->second.position, found->second.epoch,
                                   found->second.ready, profile_.build_reach};
    };
}

bool Host::placement_blocked(const authority::Point& target, const authority::Point& half_extents) const {
    for (const auto& [actor, state] : owned_->actors) {
        (void)actor;
        if (!state.ready) continue;
        const auto dx = std::max(std::abs(state.position[0] - target[0]) - half_extents[0], 0.0);
        const auto dz = std::max(std::abs(state.position[2] - target[2]) - half_extents[2], 0.0);
        const auto segment_half = capsule_height / 2 - capsule_radius;
        const auto below = target[1] - half_extents[1] - (state.position[1] + segment_half);
        const auto above = state.position[1] - segment_half - (target[1] + half_extents[1]);
        const auto dy = std::max({below, above, 0.0});
        if (dx * dx + dy * dy + dz * dz < capsule_radius * capsule_radius) return true;
    }
    return false;
}

Value Host::command(const std::string& bound_actor, const Object& wire) {
    if (!owned_) return result(false, "not_initialized");
    const auto* client = field<std::string>(wire, "client");
    if (!profile_.actors.contains(bound_actor) || !client || *client != bound_actor)
        return result(false, "wrong_actor");
    const auto snapshot = owned_->world->snapshot();
    const auto* request = field<std::string>(wire, "request");
    // Original wire comparison precedes generation lookup or translation. The
    // only cache is World's existing history; no adapter request map is created.
    if (request) for (const auto& record : snapshot.history.records) {
        if (field<std::string>(record.intent, "client") && *field<std::string>(record.intent, "client") == *client &&
            field<std::string>(record.intent, "request") && *field<std::string>(record.intent, "request") == *request) {
            auto replay = record.intent;
            replay.insert_or_assign("wire", Value(wire));
            return Value(outward(owned_->world->command({bound_actor, *client}, replay, observe()), snapshot));
        }
    }
    Object normalized{{"context", wire.contains("context") ? wire.at("context") : Value()},
        {"client", Value(*client)}, {"request", request ? Value(*request) : Value()},
        {"actor", Value(bound_actor)}, {"action", Value("adapter_refusal")}, {"wire", Value(wire)}};
    const auto refuse = [&](const char* reason) {
        return Value(outward(owned_->world->refuse({bound_actor, *client}, normalized, reason), owned_->world->snapshot()));
    };
    const auto* action = field<std::string>(wire, "action");
    if (!action) return refuse("invalid_action");
    const auto target = [&](const char* input, const char* output, const char* generation) {
        const auto* id = field<std::string>(wire, input);
        if (!id) return false;
        const auto* selected = find(snapshot.state, *id);
        normalized.emplace(output, Value(*id));
        normalized.emplace(generation, Value(selected ? selected->generation : 0));
        return true;
    };
    if (*action == "place") {
        if (!(wire.contains("axis") ? keys(wire, {"kind", "cell", "axis"}) : keys(wire, {"kind", "cell"})))
            return refuse("invalid_command");
        const auto* axis = field<std::string>(wire, "axis");
        if (wire.contains("axis") && (!axis || !axis_value(*axis))) return refuse("invalid_axis");
        const auto* kind_name = field<std::string>(wire, "kind");
        const auto* cell = field<Array>(wire, "cell");
        if (!kind_name || !cell || cell->size() != 2) return refuse("invalid_cell");
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        if (!x || !z || *x < -2 || *x > 4 || *z < -2 || *z > 4) return refuse("invalid_cell");
        if (*kind_name != "collector" && *kind_name != "belt" && *kind_name != "processor" &&
            *kind_name != "wheel" && *kind_name != "gear") return refuse("unknown_kind");
        if (*kind_name == "collector" && *x != 0) return refuse("not_at_seam");
        if (*kind_name == "wheel" && *x != -1) return refuse("not_at_stream");
        const mechanics::Point center{4 * *x, 0, 4 * *z};
        for (const auto& part : snapshot.state.topology.parts)
            if (part.geometry.center == center) return refuse("occupied");
        const auto selected_axis = axis ? *axis_value(*axis) : mechanics::Axis::x;
        const auto is_gear = *kind_name == "gear";
        const authority::Point at{*x * pitch, is_gear ? anchor_height : machine_center_height, *z * pitch};
        const auto half = is_gear ? gear_half_extents(selected_axis, 2) :
            authority::Point{machine_width / 2, machine_height / 2, machine_width / 2};
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        normalized.at("action") = Value("place");
        normalized.emplace("role", Value(*kind_name == "wheel" ? "waterwheel" : *kind_name));
        normalized.emplace("center", Value(Array{Value(center[0]), Value(center[1]), Value(center[2])}));
        normalized.emplace("axis", Value(axis ? *axis : "x"));
        normalized.emplace("teeth", Value(Integer{*kind_name == "gear" ? 2 : 0}));
        normalized.emplace("half_span", Value(Integer{0}));
    } else if (*action == "place_gear") {
        if (!keys(wire, {"center", "axis", "teeth"})) return refuse("invalid_command");
        const auto* input = field<Array>(wire, "center");
        const auto center = input ? gear_center(*input) : std::nullopt;
        const auto* axis = field<std::string>(wire, "axis");
        const auto selected_axis = axis ? axis_value(*axis) : std::nullopt;
        const auto* teeth = field<Integer>(wire, "teeth");
        if (!center) return refuse("invalid_center");
        if (!selected_axis) return refuse("invalid_axis");
        if (!teeth || *teeth < 1 || *teeth > mechanics::maximum_dimension) return refuse("invalid_gear");
        const authority::Point at{(*center)[0] * pitch / 4, anchor_height + (*center)[1] * pitch / 4, (*center)[2] * pitch / 4};
        if (placement_blocked(at, gear_half_extents(*selected_axis, *teeth))) return refuse("actor_occupied");
        normalized.at("action") = Value("place");
        normalized.emplace("role", Value("gear"));
        normalized.emplace("center", wire.at("center"));
        normalized.emplace("axis", wire.at("axis"));
        normalized.emplace("teeth", wire.at("teeth"));
        normalized.emplace("half_span", Value(Integer{0}));
    } else if (*action == "connect" || *action == "disconnect" || *action == "connect_drive" || *action == "disconnect_drive") {
        if (!keys(wire, {"from", "to"}) || !target("from", "target", "generation") ||
            !target("to", "to", "to_generation")) return refuse("invalid_command");
        normalized.at("action") = Value(*action == "connect" ? "link" : *action == "disconnect" ? "unlink" :
                                        *action == "connect_drive" ? "shaft_between" : "remove_shaft_between");
        if (*action == "connect") {
            const auto* from = find(snapshot.state, *field<std::string>(wire, "from"));
            const auto* to = find(snapshot.state, *field<std::string>(wire, "to"));
            if (from && to && (to->geometry.center[0] != from->geometry.center[0] + 4 ||
                to->geometry.center[1] != from->geometry.center[1] || to->geometry.center[2] != from->geometry.center[2]))
                return refuse("ports_not_adjacent");
        }
    } else if (*action == "set_power") {
        if (!keys(wire, {"active"}) || !field<bool>(wire, "active")) return refuse("invalid_command");
        const auto wheel = std::find_if(snapshot.state.topology.parts.begin(), snapshot.state.topology.parts.end(),
            [](const auto& part) { return part.role == Role::waterwheel; });
        if (wheel == snapshot.state.topology.parts.end()) return refuse("missing_entity");
        normalized.at("action") = Value("set_drive");
        normalized.emplace("target", Value(wheel->geometry.id));
        normalized.emplace("generation", Value(wheel->generation));
        normalized.emplace("enabled", wire.at("active"));
    } else if (*action == "remove" || *action == "recover" || *action == "retrieve" ||
               *action == "insert_raw" || *action == "insert_work") {
        const bool amount = *action == "retrieve" || *action == "insert_raw";
        const bool work = *action == "insert_work";
        if (!(amount ? keys(wire, {"entity", "amount"}) : work ? keys(wire, {"entity", "work_id"}) : keys(wire, {"entity"})) ||
            !target("entity", "target", "generation")) return refuse("invalid_command");
        normalized.at("action") = Value(*action == "retrieve" ? "collect" : *action);
        if (amount) normalized.emplace("amount", wire.at("amount"));
        if (work) normalized.emplace("work_id", wire.at("work_id"));
    } else return refuse("unsupported_action");
    const auto delivered = owned_->world->command({bound_actor, *client}, normalized, observe());
    return Value(outward(delivered, owned_->world->snapshot()));
}

Value Host::publish_actor(const std::string& actor, const Array& position, Integer epoch) {
    if (!owned_ || !owned_->actors.contains(actor)) return result(false, "unknown_actor");
    auto& current = owned_->actors.at(actor);
    const auto at = point(position);
    if (!at || epoch < 1) {
        current.ready = false;
        return result(false, "invalid_actor_sample");
    }
    if (epoch <= current.epoch) return result(false, "stale_actor_sample");
    current = {*at, epoch, true};
    owned_->native_started = true;
    return result(true, "actor_published");
}

Value Host::invalidate_actor(const std::string& actor) {
    if (!owned_ || !owned_->actors.contains(actor)) return result(false, "unknown_actor");
    // Retain the last ordinal so invalidation cannot permit a stale sample.
    owned_->actors.at(actor).ready = false;
    return result(true, "actor_invalidated");
}

Value Host::advance() {
    if (!owned_) return result(false, "not_initialized");
    const auto tick = owned_->world->tick();
    if (tick.error != world::TransactionError::none) return result(false, "native_step_failed");
    return projection();
}

Value Host::projection() const {
    if (!owned_) return result(false, "not_initialized");
    const auto snapshot = owned_->world->snapshot();
    const auto& state = snapshot.state;
    Object entities, transmissions, inventories, cargo, kits, specifications, actors;
    Array links, drive_links, engagements;
    for (const auto& part : state.topology.parts) {
        Object projected{{"kind", Value(kind(part.role))}, {"generation", Value(part.generation)},
            {"center", Value(Array{Value(part.geometry.center[0]), Value(part.geometry.center[1]), Value(part.geometry.center[2])})},
            {"axis", Value(static_cast<Integer>(part.geometry.axis))},
            {"teeth", Value(part.geometry.teeth)}, {"half_span", Value(part.geometry.half_span)}};
        if (part.role == Role::shaft || part.role == Role::gear) transmissions.emplace(part.geometry.id, Value(projected));
        else {
            projected.emplace("cell", Value(Array{Value(part.geometry.center[0] / 4), Value(part.geometry.center[2] / 4)}));
            entities.emplace(part.geometry.id, Value(std::move(projected)));
        }
    }
    for (const auto& link : state.topology.material_links) links.emplace_back(Array{Value(link.from.id), Value(link.to.id)});
    const auto power = stationary::power_view(state.topology);
    Object motions;
    for (const auto& [id, motion] : power.mechanical.motion) motions.emplace(id, Value(Object{
        {"state", Value(mechanics::motion_state_name(motion.state))},
        {"numerator", Value(motion.rate.numerator)}, {"denominator", Value(motion.rate.denominator)}}));
    for (const auto& edge : power.mechanical.engagements) engagements.emplace_back(Object{
        {"a", Value(edge.a)}, {"b", Value(edge.b)}, {"kind", Value(static_cast<Integer>(edge.kind))}});
    for (const auto& shaft : state.topology.parts) {
        if (shaft.role != Role::shaft) continue;
        Array ends;
        const auto axis = static_cast<std::size_t>(shaft.geometry.axis);
        for (const auto& part : state.topology.parts) {
            if (part.role == Role::shaft || part.role == Role::gear || part.geometry.axis != shaft.geometry.axis) continue;
            bool aligned = true;
            for (std::size_t index = 0; index < 3; ++index)
                if (index != axis && part.geometry.center[index] != shaft.geometry.center[index]) aligned = false;
            if (aligned && std::abs(part.geometry.center[axis] - shaft.geometry.center[axis]) == shaft.geometry.half_span)
                ends.emplace_back(part.geometry.id);
        }
        if (ends.size() == 2) drive_links.emplace_back(std::move(ends));
    }
    Integer player = 0;
    for (const auto& [actor, contents] : state.material.cargo) {
        inventories.emplace(actor, Value(contents.products)); player += contents.products;
        cargo.emplace(actor, cargo_value(contents));
    }
    for (const auto& [actor, kit] : state.kits) {
        kits.emplace(actor, kit_value(kit));
        Array entries;
        for (const auto& [specification, initial] : profile_.finite_parts) {
            (void)initial;
            const auto found = kit.find(specification);
            entries.emplace_back(Object{{"kind", Value(kind(specification.role))},
                {"teeth", Value(specification.teeth)}, {"half_span", Value(specification.half_span)},
                {"count", Value(found == kit.end() ? 0 : found->second)}});
        }
        specifications.emplace(actor, Value(std::move(entries)));
    }
    for (const auto& [actor, sample] : owned_->actors) actors.emplace(actor, Value(Object{
        {"position", point_value(sample.position)}, {"capabilities", Value(Object{{"build_reach", Value(reach)}})},
        {"ready", Value(sample.ready)}, {"native_epoch", Value(sample.epoch)}}));
    const auto& stock = state.material.stock;
    const auto local = world::machine_power(state.topology);
    return Value(Object{{"context", Value(snapshot.history.context)}, {"revision", Value(snapshot.revision)},
        {"order", Value(snapshot.history.order)}, {"initial_feed", Value(profile_.initial_units)},
        {"recipe_input", Value(profile_.material.input_units_per_product)}, {"entities", Value(std::move(entities))},
        {"transmission_parts", Value(std::move(transmissions))}, {"links", Value(std::move(links))},
        {"drive_links", Value(std::move(drive_links))}, {"engagements", Value(std::move(engagements))},
        {"motion", Value(std::move(motions))}, {"inventories", Value(std::move(inventories))},
        {"cargo", Value(std::move(cargo))}, {"part_kits", Value(std::move(kits))},
        {"part_specifications", Value(std::move(specifications))},
        {"parts", kit_value(state.kits.at("P"))}, {"actors", Value(std::move(actors))},
        {"stock", Value(Object{{"source", Value(stock.source)}, {"collector", Value(stock.collector)},
            {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
            {"held", Value(state.material.processing ? state.material.processing->recipe.input_units_per_product : 0)},
            {"output", Value(stock.output)}, {"player", Value(player)}})},
        {"remaining", Value(state.material.processing ? state.material.processing->remaining_ticks : 0)},
        {"powered", Value(local.collector || local.belt || local.processor)},
        {"power_enabled", Value(state.topology.drive_enabled)},
        {"options", Value(Object{{"opening", Value(true)}, {"physical", Value(true)}, {"native", Value(true)}})},
        {"adapter_profile", Value(Object{{"pitch", Value(pitch)}, {"anchor_height", Value(anchor_height)},
            {"capsule_radius", Value(capsule_radius)}, {"capsule_height", Value(capsule_height)}})}});
}

Value Host::checkpoint() const {
    if (!owned_) return result(false, "not_initialized");
    const auto encoded = world::encode_checkpoint(profile_, owned_->world->snapshot());
    if (!std::holds_alternative<Value>(encoded)) return result(false, "native_checkpoint_refused");
    Object actors;
    for (const auto& [actor, sample] : owned_->actors) actors.emplace(actor, point_value(sample.position));
    return Value(Object{{"schema", Value(Integer{3})}, {"format", Value("factory-native-physical")},
        {"world", std::get<Value>(encoded)}, {"actors", Value(std::move(actors))}});
}

Host::Decoded Host::decode(const Value& input) const {
    if (!owned_) return {nullptr, "not_initialized"};
    const auto* root = std::get_if<Object>(&input.storage());
    if (!root || root->size() != 4 || !field<Integer>(*root, "schema") || *field<Integer>(*root, "schema") != 3 ||
        !field<std::string>(*root, "format") || *field<std::string>(*root, "format") != "factory-native-physical" ||
        !root->contains("world") || !field<Object>(*root, "actors")) return {nullptr, "invalid_checkpoint"};
    const auto* native = std::get_if<Object>(&root->at("world").storage());
    const auto* history = native ? field<Object>(*native, "history") : nullptr;
    const auto* context = history ? field<std::string>(*history, "context") : nullptr;
    if (!context) return {nullptr, "invalid_context"};
    auto decoded = world::decode_checkpoint(profile_, *context, root->at("world"));
    if (!std::holds_alternative<world::Snapshot>(decoded)) return {nullptr, "native_checkpoint_refused"};
    const auto& snapshot = std::get<world::Snapshot>(decoded);
    for (const auto& record : snapshot.history.records) {
        if (!field<Object>(record.intent, "wire")) return {nullptr, "missing_wire_history"};
        if (!historical_wire(record)) return {nullptr, "inconsistent_wire_history"};
        const auto* actor = field<std::string>(record.intent, "actor");
        const auto* client = field<std::string>(record.intent, "client");
        if (!actor || !client || *actor != *client) return {nullptr, "invalid_actor_binding"};
    }
    for (const auto& part : snapshot.state.topology.parts) {
        const auto& center = part.geometry.center;
        if (center[0] < -8 || center[0] > 16 || center[1] < 0 || center[1] > 16 ||
            center[2] < -8 || center[2] > 16) return {nullptr, "incompatible_geometry"};
        if (part.role == Role::shaft) {
            if (part.geometry.half_span != 2)
                return {nullptr, "incompatible_geometry"};
        } else if (part.role == Role::gear) {
            if (part.geometry.teeth != 2) return {nullptr, "incompatible_geometry"};
        } else if (center[1] != 0 || center[0] % 4 != 0 || center[2] % 4 != 0 ||
            (part.role == Role::collector && center[0] != 0) ||
            (part.role == Role::waterwheel && center[0] != -4)) return {nullptr, "incompatible_geometry"};
    }
    for (const auto& link : snapshot.state.topology.material_links) {
        const auto* from = find(snapshot.state, link.from.id);
        const auto* to = find(snapshot.state, link.to.id);
        if (!from || !to || to->geometry.center[0] != from->geometry.center[0] + 4 ||
            to->geometry.center[2] != from->geometry.center[2]) return {nullptr, "incompatible_geometry"};
    }
    const auto& actors = *field<Object>(*root, "actors");
    if (actors.size() != profile_.actors.size()) return {nullptr, "actor_roster_mismatch"};
    auto candidate = std::make_unique<Owned>();
    for (const auto& actor : profile_.actors) {
        const auto found = actors.find(actor);
        const auto* position = found == actors.end() ? nullptr : std::get_if<Array>(&found->second.storage());
        const auto at = position ? point(*position) : std::nullopt;
        if (!at || !std::all_of(position->begin(), position->end(), [](const auto& coordinate) {
                return coordinate.type() == values::Type::floating;
            })) return {nullptr, "invalid_actor_seed"};
        candidate->actors.emplace(actor, Actor{*at, 0, false});
    }
    candidate->world = world::World::restore(*context, profile_, snapshot);
    if (!candidate->world) return {nullptr, "native_checkpoint_refused"};
    return {std::move(candidate), ""};
}

Value Host::validate_checkpoint(const Value& input) const {
    const auto decoded = decode(input);
    return result(decoded.candidate != nullptr, decoded.candidate ? "valid" : decoded.refusal);
}

Value Host::restore_checkpoint(const Value& input) {
    if (!owned_) return result(false, "not_initialized");
    const auto current = owned_->world->snapshot();
    if (owned_->native_started || current.history.order != 0 || current.revision != 0)
        return result(false, "restore_requires_fresh_host");
    auto decoded = decode(input);
    if (!decoded.candidate) return result(false, decoded.refusal);
    owned_.swap(decoded.candidate);
    return result(true, "restored");
}

}  // namespace factory::godot_world
