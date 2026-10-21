#include "factory/godot_world.hpp"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <optional>
#include <stdexcept>
#include <tuple>
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
constexpr Integer height_denominator = 4;
constexpr double height_step = pitch / height_denominator;
constexpr double foundation_depth = 2 * height_step;
constexpr double anchor_height = 0.5;
constexpr double reach = 4.0;
constexpr double capsule_radius = 0.3;
constexpr double capsule_height = 1.8;
constexpr double machine_width = 1.45;
constexpr double machine_height = 1.65;
constexpr double machine_center_height = 0.8;

struct Bounds { authority::Point center, half; };

Bounds part_bounds(const world::Profile& profile, const stationary::PlacedPart& part) {
    const auto& c = part.geometry.center;
    const auto x = c[0] * height_step, z = c[2] * height_step, floor = c[1] * height_step;
    if (part.role == Role::waterwheel) {
        const auto radius = profile.wheel_radius * part.wheel_tiles * height_step / 100.0;
        return {{x, floor + anchor_height, z},
            {part.geometry.axis == mechanics::Axis::x ? 0.3 : radius, radius,
             part.geometry.axis == mechanics::Axis::z ? 0.3 : radius}};
    }
    return {{x, floor + machine_center_height, z}, {machine_width / 2, machine_height / 2, machine_width / 2}};
}

Bounds foundation_bounds(const world::Foundation& foundation) {
    return {{foundation.center[0] * height_step, foundation.center[1] * height_step - foundation_depth / 2,
             foundation.center[2] * height_step}, {pitch / 2, foundation_depth / 2, pitch / 2}};
}

bool overlap(const Bounds& a, const Bounds& b) {
    for (std::size_t axis = 0; axis < 3; ++axis)
        if (std::abs(a.center[axis] - b.center[axis]) >= a.half[axis] + b.half[axis]) return false;
    return true;
}

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

bool place_keys(const Object& object) {
    if (object.contains("tiles")) {
        auto without_tiles = object;
        without_tiles.erase("tiles");
        const auto* kind = field<std::string>(object, "kind");
        return kind && *kind == "wheel" && place_keys(without_tiles);
    }
    if (object.contains("level")) return object.contains("axis") ?
        keys(object, {"kind", "cell", "axis", "level"}) : keys(object, {"kind", "cell", "level"});
    return object.contains("axis") ? keys(object, {"kind", "cell", "axis"}) : keys(object, {"kind", "cell"});
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
        if (!value || *value < -mechanics::maximum_coordinate || *value > mechanics::maximum_coordinate) return std::nullopt;
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
    if (*action == "place_foundations") {
        const auto* cell = field<Array>(*wire, "cell");
        const auto* end = field<Array>(*wire, "end_cell");
        const auto* level = field<Integer>(*wire, "level");
        if (*original_action != "place_foundations" || !keys(*wire, {"cell", "end_cell", "level"}) ||
            !cell || !end || cell->size() != 2 || end->size() != 2 || !level ||
            *level < -1000000 || *level > 1000000) return false;
        const auto matches = [&](const Array& point, const char* name) {
            const auto* x = std::get_if<Integer>(&point[0].storage());
            const auto* z = std::get_if<Integer>(&point[1].storage());
            return x && z && *x >= -250000 && *x <= 250000 && *z >= -250000 && *z <= 250000 &&
                intent.contains(name) && !values::typed_difference(intent.at(name),
                    Value(Array{Value(4 * *x), Value(*level), Value(4 * *z)}));
        };
        return matches(*cell, "center") && matches(*end, "end");
    }
    if (*action == "place_foundation") {
        const auto* cell = field<Array>(*wire, "cell");
        const auto* level = field<Integer>(*wire, "level");
        const auto* center = field<Array>(intent, "center");
        if (*original_action != "place_foundation" || !keys(*wire, {"cell", "level"}) ||
            !cell || cell->size() != 2 || !level || !center || center->size() != 3) return false;
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        return x && z && *x >= -250000 && *x <= 250000 && *z >= -250000 && *z <= 250000 &&
            *level >= -1000000 && *level <= 1000000 &&
            !values::typed_difference(Value(*center), Value(Array{Value(4 * *x), Value(*level), Value(4 * *z)}));
    }
    if (*action == "place" || *action == "place_connected") {
        if (*original_action == "place_gear") {
            const auto* center = field<Array>(*wire, "center");
            const auto* axis = field<std::string>(*wire, "axis");
            const auto* teeth = field<Integer>(*wire, "teeth");
            return *action == "place" && keys(*wire, {"center", "axis", "teeth"}) && center && gear_center(*center) &&
                axis && axis_value(*axis) && teeth && *teeth > 0 && *teeth <= mechanics::maximum_dimension &&
                same("center", "center") && same("axis", "axis") && same("teeth", "teeth") &&
                field<std::string>(intent, "role") && *field<std::string>(intent, "role") == "gear" &&
                field<Integer>(intent, "half_span") && *field<Integer>(intent, "half_span") == 0;
        }
        const auto* name = field<std::string>(*wire, "kind");
        const auto* cell = field<Array>(*wire, "cell");
        const auto* axis = field<std::string>(*wire, "axis");
        if (*original_action != "place" || !place_keys(*wire) ||
            (wire->contains("axis") && (!axis || !axis_value(*axis))) || !name || !cell || cell->size() != 2)
            return false;
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        const auto* level = field<Integer>(*wire, "level");
        const auto* tiles = field<Integer>(*wire, "tiles");
        if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000 ||
            (wire->contains("level") && (!level || *level < -1000000 || *level > 1000000)) ||
            (*name != "collector" && *name != "belt" && *name != "processor" && *name != "wheel" && *name != "gear"))
            return false;
        if (wire->contains("tiles") != intent.contains("wheel_tiles")) return false;
        if (wire->contains("tiles") && (!tiles || *tiles < 1 || *tiles > mechanics::maximum_dimension ||
            !field<Integer>(intent, "wheel_tiles") || *field<Integer>(intent, "wheel_tiles") != *tiles)) return false;
        if (*action == "place_connected" && *name != "collector" && *name != "belt" && *name != "processor")
            return false;
        const Object expected{{"role", Value(*name == "wheel" ? "waterwheel" : *name)},
            {"center", Value(Array{Value(4 * *x), Value(level ? *level : Integer{0}), Value(4 * *z)})},
            {"axis", Value(axis ? *axis : (*name == "belt" ? "z" : "x"))}, {"teeth", Value(Integer{*name == "gear" ? 2 : 0})},
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
    if (*action == "remove_foundation")
        return *original_action == "remove" && keys(*wire, {"entity"}) && same("entity", "target");
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
    profile.foundation_parts = 24;
    profile.finite_parts = {{{Role::collector, 0, 0}, 1}, {{Role::belt, 0, 0}, 1},
        {{Role::processor, 0, 0}, 1}, {{Role::waterwheel, 0, 0}, 1}, {{Role::shaft, 0, 2}, 4},
        {{Role::shaft, 0, 4}, 4}, {{Role::gear, 2, 0}, 5}, {{Role::gear, 4, 0}, 2}};
    world::State seed;
    seed.material.initial_units = 16;
    seed.material.stock.source = 16;
    auto candidate = std::make_unique<Owned>();
    for (const auto& actor : actors) {
        if ((actor != "P" && actor != "Q") || !profile.actors.insert(actor).second)
            return result(false, "invalid_roster");
        seed.material.cargo.emplace(actor, materials::Cargo{});
        seed.kits.emplace(actor, actor == "P" ? profile.finite_parts : stationary::Kit{});
        seed.foundation_kits.emplace(actor, actor == "P" ? profile.foundation_parts : 0);
        candidate->actors.emplace(actor, Actor{{-pitch, 1.0, (actor == "P" ? 2.0 : 3.0) * pitch}, 0, false});
    }
    candidate->world = world::World::create(context, profile, seed);
    if (!candidate->world) return result(false, "invalid_initial_world");
    profile_ = std::move(profile);
    owned_ = std::move(candidate);
    return result(true, "initialized");
}

Value Host::configure_terrain(const Object& input) {
    if (!owned_ || owned_->native_started || !terrain_axis_.empty()) return result(false, "terrain_already_bound");
    const auto* axis = field<Array>(input, "axis");
    const auto* heights = field<Array>(input, "heights");
    const auto* obstacles = field<Array>(input, "obstacles");
    const auto* water = field<Array>(input, "water");
    if (input.size() != (water ? 4u : 3u) || !axis || !heights || !obstacles || obstacles->size() > 1024 || axis->size() < 2 || axis->size() > 200 ||
        heights->size() != axis->size() * axis->size()) return result(false, "invalid_terrain");
    std::vector<double> coordinates, elevations;
    std::vector<std::pair<authority::Point, authority::Point>> solids;
    for (const auto& value : *axis) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000 ||
            (!coordinates.empty() && coordinates.back() >= *number)) return result(false, "invalid_terrain");
        coordinates.push_back(*number);
    }
    for (const auto& value : *heights) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000) return result(false, "invalid_terrain");
        elevations.push_back(*number);
    }
    for (const auto& value : *obstacles) {
        const auto* ends = std::get_if<Array>(&value.storage());
        if (!ends || ends->size() != 2) return result(false, "invalid_terrain");
        const auto* low_array = std::get_if<Array>(&ends->at(0).storage());
        const auto* high_array = std::get_if<Array>(&ends->at(1).storage());
        const auto low = low_array ? point(*low_array) : std::nullopt;
        const auto high = high_array ? point(*high_array) : std::nullopt;
        if (!low || !high) return result(false, "invalid_terrain");
        for (std::size_t axis = 0; axis < 3; ++axis)
            if ((*low)[axis] >= (*high)[axis]) return result(false, "invalid_terrain");
        solids.emplace_back(*low, *high);
    }
    auto next_profile = profile_;
    if (water) {
        if (water->empty() || water->size() > 65536) return result(false, "invalid_water");
        for (const auto& value : *water) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 6) return result(false, "invalid_water");
            std::array<Integer, 6> fields{};
            for (std::size_t i = 0; i < fields.size(); ++i) {
                const auto* number = std::get_if<Integer>(&row->at(i).storage());
                if (!number) return result(false, "invalid_water");
                fields[i] = *number;
            }
            if (!next_profile.water.emplace(std::array<Integer, 2>{fields[0], fields[1]},
                    waterwheel::Sample{fields[2], fields[3], fields[4], fields[5]}).second)
                return result(false, "invalid_water");
        }
        const auto snapshot = owned_->world->snapshot();
        if (snapshot.revision != 0 || snapshot.history.order != 0) return result(false, "terrain_already_bound");
        auto replacement = world::World::create(snapshot.history.context, next_profile, snapshot.state);
        if (!replacement) return result(false, "invalid_water");
        owned_->world = std::move(replacement);
        profile_ = std::move(next_profile);
    }
    terrain_axis_ = std::move(coordinates);
    terrain_heights_ = std::move(elevations);
    terrain_obstacles_ = std::move(solids);
    return result(true, "terrain_bound");
}

bool Host::site_blocked(const authority::Point& low, const authority::Point& high) const {
    return std::any_of(terrain_obstacles_.begin(), terrain_obstacles_.end(), [&](const auto& obstacle) {
        for (std::size_t axis = 0; axis < 3; ++axis)
            if (high[axis] <= obstacle.first[axis] || low[axis] >= obstacle.second[axis]) return false;
        return true;
    });
}

const char* Host::wheel_site_refusal(const mechanics::Point& center, mechanics::Axis axis, Integer tiles) const {
    const auto sample = profile_.water.find({center[0], center[2]});
    if (sample == profile_.water.end()) return "not_at_stream";
    const auto contact = waterwheel::immersed(center[1] * 100 + profile_.wheel_axle_offset,
                                              profile_.wheel_radius * tiles, axis, sample->second);
    if (!contact || !*contact) return "not_at_stream";
    const double x = center[0] * height_step, y = center[1] * height_step + anchor_height;
    const double z = center[2] * height_step;
    const double radius = profile_.wheel_radius * tiles * height_step / 100.0;
    const double half_x = axis == mechanics::Axis::x ? 0.3 : radius;
    const double half_z = axis == mechanics::Axis::z ? 0.3 : radius;
    if (site_blocked({x - half_x, y - radius, z - half_z}, {x + half_x, y + radius, z + half_z}))
        return "site_occupied";
    // Bound the entire rotating rim against the same emitted terrain triangles.
    // Each strip uses its highest ground and the lowest point of the arc in
    // that strip, so an unchecked peak cannot pass between point samples.
    const auto strips = static_cast<Integer>(std::ceil(2 * radius / height_step));
    for (Integer index = 0; index < strips; ++index) {
        const double a = -radius + 2 * radius * index / strips;
        const double b = -radius + 2 * radius * (index + 1) / strips;
        const double middle = (a + b) / 2, span = (b - a) / 2;
        const auto terrain = axis == mechanics::Axis::x ? terrain_range(x, z + middle, 0.3, span) :
                                                        terrain_range(x + middle, z, span, 0.3);
        if (!terrain) return "terrain_unavailable";
        const double nearest = a > 0 ? a : b < 0 ? -b : 0;
        const double low_arc = y - std::sqrt(std::max(0.0, radius * radius - nearest * nearest));
        if (terrain->second > low_arc) return "site_occupied";
    }
    return nullptr;
}

std::optional<std::pair<double, double>> Host::terrain_range(double x, double z, double half_x, double half_z) const {
    if (terrain_axis_.empty()) return std::nullopt;
    const double left = x - half_x, right = x + half_x;
    const double near = z - half_z, far = z + half_z;
    if (left < terrain_axis_.front() || right > terrain_axis_.back() ||
        near < terrain_axis_.front() || far > terrain_axis_.back()) return std::nullopt;
    const auto cell = [&](double at) {
        return std::min(terrain_axis_.size() - 2, static_cast<std::size_t>(
            std::upper_bound(terrain_axis_.begin(), terrain_axis_.end(), at) - terrain_axis_.begin() - 1));
    };
    const auto vertex = [&](std::size_t gx, std::size_t gz) {
        return authority::Point{terrain_axis_[gx], terrain_heights_[gz * terrain_axis_.size() + gx], terrain_axis_[gz]};
    };
    double low = std::numeric_limits<double>::infinity(), high = -low;
    for (auto gz = cell(near); gz <= cell(far); ++gz) for (auto gx = cell(left); gx <= cell(right); ++gx) {
        const auto a = vertex(gx, gz), b = vertex(gx + 1, gz), c = vertex(gx + 1, gz + 1), d = vertex(gx, gz + 1);
        for (auto polygon : {std::vector<authority::Point>{a, b, c}, std::vector<authority::Point>{a, c, d}}) {
            // Clip both actual emitted triangles to the complete tile footprint.
            // A linear triangle's extreme height is at a clipped polygon vertex.
            for (const auto& [axis, boundary, sign] : {std::tuple{0, left, 1.0}, {0, right, -1.0},
                    {2, near, 1.0}, {2, far, -1.0}}) {
                std::vector<authority::Point> clipped;
                for (std::size_t n = 0; n < polygon.size(); ++n) {
                    const auto& p = polygon[n];
                    const auto& q = polygon[(n + 1) % polygon.size()];
                    const bool inside = (p[axis] - boundary) * sign >= 0;
                    const bool next = (q[axis] - boundary) * sign >= 0;
                    if (inside) clipped.push_back(p);
                    if (inside != next) {
                        const auto t = (boundary - p[axis]) / (q[axis] - p[axis]);
                        clipped.push_back({p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]), p[2] + t * (q[2] - p[2])});
                    }
                }
                polygon = std::move(clipped);
            }
            for (const auto& p : polygon) { low = std::min(low, p[1]); high = std::max(high, p[1]); }
        }
    }
    return std::pair{low, high};
}

const char* Host::machine_site_refusal(const world::State& state, const mechanics::Point& center) const {
    const auto x = center[0] * height_step;
    const auto floor = center[1] * height_step;
    const auto z = center[2] * height_step;
    const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
        [&](const auto& entry) { return entry.second.center == center; });
    const auto terrain = terrain_range(x, z);
    // A foundation supplies support, not clearance through the real ground.
    // Foundation blocks themselves may be buried; ordinary machines may not.
    if (terrain && terrain->second > floor) return "foundation_required";
    if (!supported) {
        if (!terrain) return "terrain_unavailable";
        // This is the existing seating fit, not additional character reach.
        if (terrain->first < floor - 0.04) return "foundation_required";
    }
    if (site_blocked({x - machine_width / 2, floor, z - machine_width / 2},
                     {x + machine_width / 2, floor + machine_height, z + machine_width / 2}))
        return "site_occupied";
    return nullptr;
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
    if (*action == "place_foundation" || *action == "place_foundations") {
        const bool area = *action == "place_foundations";
        if (!(area ? keys(wire, {"cell", "end_cell", "level"}) : keys(wire, {"cell", "level"})))
            return refuse("invalid_command");
        const auto* cell = field<Array>(wire, "cell");
        const auto* level = field<Integer>(wire, "level");
        if (!cell || cell->size() != 2 || !level || *level < -1000000 || *level > 1000000) return refuse("invalid_cell");
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000) return refuse("invalid_cell");
        const auto* end = area ? field<Array>(wire, "end_cell") : cell;
        if (!end || end->size() != 2) return refuse("invalid_cell");
        const auto* end_x = std::get_if<Integer>(&end->at(0).storage());
        const auto* end_z = std::get_if<Integer>(&end->at(1).storage());
        if (!end_x || !end_z || *end_x < -250000 || *end_x > 250000 || *end_z < -250000 || *end_z > 250000)
            return refuse("invalid_cell");
        const auto width = std::abs(*end_x - *x) + 1, depth = std::abs(*end_z - *z) + 1;
        if (width > 256 || depth > 256 || width * depth > 256) return refuse("invalid_area");
        const auto top = *level * pitch / 4;
        // Foundations intentionally intersect natural ground/scenery and need
        // no gravity support. Constructed parts and actual actors still block.
        for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
            for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz)
                if (placement_blocked({px * pitch, top - foundation_depth / 2, pz * pitch},
                    {pitch / 2, foundation_depth / 2, pitch / 2}))
                    return refuse("actor_occupied");
        for (const auto& part : snapshot.state.topology.parts) {
            const auto& center = part.geometry.center;
            if (part.role == Role::waterwheel) {
                for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
                    for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz)
                        if (overlap(part_bounds(profile_, part), foundation_bounds({{4 * px, *level, 4 * pz}, 1})))
                            return refuse("occupied");
                continue;
            }
            if (center[0] * pitch / 4 > std::min(*x, *end_x) * pitch - pitch &&
                center[0] * pitch / 4 < std::max(*x, *end_x) * pitch + pitch &&
                center[2] * pitch / 4 > std::min(*z, *end_z) * pitch - pitch &&
                center[2] * pitch / 4 < std::max(*z, *end_z) * pitch + pitch &&
                center[1] * pitch / 4 < top && center[1] * pitch / 4 + machine_height > top - foundation_depth)
                return refuse("occupied");
        }
        normalized.at("action") = Value(*action);
        normalized.emplace("center", Value(Array{Value(4 * *x), Value(*level), Value(4 * *z)}));
        if (area) normalized.emplace("end", Value(Array{Value(4 * *end_x), Value(*level), Value(4 * *end_z)}));
    } else if (*action == "place") {
        if (!place_keys(wire))
            return refuse("invalid_command");
        const auto* axis = field<std::string>(wire, "axis");
        if (wire.contains("axis") && (!axis || !axis_value(*axis))) return refuse("invalid_axis");
        const auto* kind_name = field<std::string>(wire, "kind");
        const auto* cell = field<Array>(wire, "cell");
        if (!kind_name || !cell || cell->size() != 2) return refuse("invalid_cell");
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        const auto* level = field<Integer>(wire, "level");
        const auto* tiles = field<Integer>(wire, "tiles");
        if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000 ||
            (wire.contains("level") && (!level || *level < -1000000 || *level > 1000000))) return refuse("invalid_cell");
        if (*kind_name != "collector" && *kind_name != "belt" && *kind_name != "processor" &&
            *kind_name != "wheel" && *kind_name != "gear") return refuse("unknown_kind");
        if (wire.contains("tiles") && (!tiles || *tiles < 1 || *tiles > mechanics::maximum_dimension)) return refuse("invalid_wheel_size");
        if (*kind_name == "belt" && axis && *axis != "z") return refuse("invalid_belt_axis");
        if (*kind_name == "collector" && *x != 0) return refuse("not_at_seam");
        if (*kind_name == "collector" && level && *level != 0) return refuse("not_at_seam");
        const mechanics::Point center{4 * *x, level ? *level : 0, 4 * *z};
        const auto selected_axis = axis ? *axis_value(*axis) : (*kind_name == "belt" ? mechanics::Axis::z : mechanics::Axis::x);
        const stationary::PlacedPart proposed{{"proposed", mechanics::Kind::hub, center, selected_axis, 0, 0},
            1, *kind_name == "wheel" ? Role::waterwheel : Role::collector, tiles ? *tiles : 1};
        if (*kind_name == "wheel")
            if (const auto* refusal = wheel_site_refusal(center, selected_axis, tiles ? *tiles : 1)) return refuse(refusal);
        for (const auto& [id, foundation] : snapshot.state.foundations) {
            (void)id;
            if (*kind_name == "wheel" &&
                overlap(part_bounds(profile_, proposed), foundation_bounds(foundation))) return refuse("occupied");
            if (foundation.center[0] == center[0] && foundation.center[2] == center[2] &&
                foundation.center[1] > center[1] && foundation.center[1] - 2 < center[1] + 4)
                return refuse("occupied");
        }
        if (*kind_name != "gear" && !(*kind_name == "wheel")) {
            if (const auto* refusal = machine_site_refusal(snapshot.state, center)) return refuse(refusal);
        }
        for (const auto& part : snapshot.state.topology.parts) {
            if (part.geometry.center == center) return refuse("occupied");
            if (*kind_name != "gear" && part.role != Role::gear && part.role != Role::shaft &&
                (*kind_name == "wheel" || part.role == Role::waterwheel) &&
                overlap(part_bounds(profile_, proposed), part_bounds(profile_, part))) return refuse("occupied");
        }
        const auto is_gear = *kind_name == "gear";
        const bool water_wheel = *kind_name == "wheel";
        const auto radius = profile_.wheel_radius * (tiles ? *tiles : 1) * height_step / 100.0;
        const authority::Point at{*x * pitch, center[1] * pitch / 4 +
            (is_gear || water_wheel ? anchor_height : machine_center_height), *z * pitch};
        const auto half = is_gear ? gear_half_extents(selected_axis, 2) : water_wheel ?
            authority::Point{selected_axis == mechanics::Axis::x ? 0.3 : radius, radius,
                selected_axis == mechanics::Axis::z ? 0.3 : radius} :
            authority::Point{machine_width / 2, machine_height / 2, machine_width / 2};
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        normalized.at("action") = Value(*kind_name == "collector" || *kind_name == "belt" || *kind_name == "processor" ?
                                        "place_connected" : "place");
        normalized.emplace("role", Value(*kind_name == "wheel" ? "waterwheel" : *kind_name));
        normalized.emplace("center", Value(Array{Value(center[0]), Value(center[1]), Value(center[2])}));
        normalized.emplace("axis", Value(axis ? *axis : (*kind_name == "belt" ? "z" : "x")));
        normalized.emplace("teeth", Value(Integer{*kind_name == "gear" ? 2 : 0}));
        normalized.emplace("half_span", Value(Integer{0}));
        if (tiles) normalized.emplace("wheel_tiles", Value(*tiles));
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
        const auto* id = field<std::string>(wire, "entity");
        const auto foundation = id ? snapshot.state.foundations.find(*id) : snapshot.state.foundations.end();
        if (*action == "remove" && foundation != snapshot.state.foundations.end()) {
            normalized.at("action") = Value("remove_foundation");
            normalized.at("generation") = Value(foundation->second.generation);
        } else normalized.at("action") = Value(*action == "retrieve" ? "collect" : *action);
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
    Object entities, transmissions, inventories, cargo, kits, specifications, actors, foundations;
    Array links, drive_links, engagements;
    for (const auto& part : state.topology.parts) {
        Object projected{{"kind", Value(kind(part.role))}, {"generation", Value(part.generation)},
            {"center", Value(Array{Value(part.geometry.center[0]), Value(part.geometry.center[1]), Value(part.geometry.center[2])})},
            {"axis", Value(static_cast<Integer>(part.geometry.axis))},
            {"teeth", Value(part.geometry.teeth)}, {"half_span", Value(part.geometry.half_span)}};
        if (part.role == Role::waterwheel) projected.emplace("tiles", Value(part.wheel_tiles));
        if (part.role == Role::shaft || part.role == Role::gear) transmissions.emplace(part.geometry.id, Value(projected));
        else {
            projected.emplace("cell", Value(Array{Value(part.geometry.center[0] / 4), Value(part.geometry.center[2] / 4)}));
            if (part.geometry.center[1] != 0) projected.emplace("level", Value(part.geometry.center[1]));
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
        auto projected_kit = std::get<Object>(kit_value(kit).storage());
        projected_kit.emplace("foundation", Value(state.foundation_kits.at(actor)));
        kits.emplace(actor, Value(std::move(projected_kit)));
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
    for (const auto& [id, foundation] : state.foundations)
        foundations.emplace(id, Value(Object{{"cell", Value(Array{Value(foundation.center[0] / 4), Value(foundation.center[2] / 4)})},
            {"level", Value(foundation.center[1])}, {"generation", Value(foundation.generation)}}));
    auto player_parts = std::get<Object>(kit_value(state.kits.at("P")).storage());
    player_parts.emplace("foundation", Value(state.foundation_kits.at("P")));
    return Value(Object{{"context", Value(snapshot.history.context)}, {"revision", Value(snapshot.revision)},
        {"order", Value(snapshot.history.order)}, {"initial_feed", Value(profile_.initial_units)},
        {"recipe_input", Value(profile_.material.input_units_per_product)}, {"entities", Value(std::move(entities))},
        {"transmission_parts", Value(std::move(transmissions))}, {"links", Value(std::move(links))},
        {"drive_links", Value(std::move(drive_links))}, {"engagements", Value(std::move(engagements))},
        {"motion", Value(std::move(motions))}, {"inventories", Value(std::move(inventories))},
        {"cargo", Value(std::move(cargo))}, {"part_kits", Value(std::move(kits))},
        {"part_specifications", Value(std::move(specifications))},
        {"parts", Value(std::move(player_parts))}, {"actors", Value(std::move(actors))},
        {"foundations", Value(std::move(foundations))},
        {"stock", Value(Object{{"source", Value(stock.source)}, {"collector", Value(stock.collector)},
            {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
            {"held", Value(state.material.processing ? state.material.processing->recipe.input_units_per_product : 0)},
            {"output", Value(stock.output)}, {"player", Value(player)}})},
        {"remaining", Value(state.material.processing ? state.material.processing->remaining_ticks : 0)},
        {"powered", Value(local.collector || local.belt || local.processor)},
        {"power_enabled", Value(state.topology.drive_enabled)},
        {"options", Value(Object{{"opening", Value(true)}, {"physical", Value(true)}, {"native", Value(true)}, {"foundations", Value(true)}})},
        {"adapter_profile", Value(Object{{"pitch", Value(pitch)}, {"anchor_height", Value(anchor_height)},
            {"height_denominator", Value(height_denominator)}, {"height_step", Value(height_step)},
            {"foundation_depth", Value(foundation_depth)},
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
    auto snapshot = std::get<world::Snapshot>(decoded);
    for (const auto& record : snapshot.history.records) {
        if (!field<Object>(record.intent, "wire")) return {nullptr, "missing_wire_history"};
        if (!historical_wire(record)) return {nullptr, "inconsistent_wire_history"};
        const auto* actor = field<std::string>(record.intent, "actor");
        const auto* client = field<std::string>(record.intent, "client");
        if (!actor || !client || *actor != *client) return {nullptr, "invalid_actor_binding"};
    }
    for (const auto& part : snapshot.state.topology.parts) {
        const auto& center = part.geometry.center;
        if (std::any_of(center.begin(), center.end(), [](auto value) {
            return value < -mechanics::maximum_coordinate || value > mechanics::maximum_coordinate;
        })) return {nullptr, "incompatible_geometry"};
        if (part.role == Role::shaft) {
            if (part.geometry.half_span != 2 && part.geometry.half_span != 4)
                return {nullptr, "incompatible_geometry"};
        } else if (part.role == Role::gear) {
            if (part.geometry.teeth != 2 && part.geometry.teeth != 4) return {nullptr, "incompatible_geometry"};
        } else if ((part.role == Role::belt && part.geometry.axis != mechanics::Axis::z) ||
            center[0] % 4 != 0 || center[2] % 4 != 0 ||
            (part.role == Role::collector && (center[0] != 0 || center[1] != 0))) return {nullptr, "incompatible_geometry"};
        if (part.role == Role::waterwheel) {
            if (const auto* refusal = wheel_site_refusal(center, part.geometry.axis, part.wheel_tiles)) return {nullptr, refusal};
            for (const auto& [id, foundation] : snapshot.state.foundations) {
                (void)id;
                if (overlap(part_bounds(profile_, part), foundation_bounds(foundation))) return {nullptr, "occupied"};
            }
            for (const auto& other : snapshot.state.topology.parts)
                if (other.geometry.id != part.geometry.id && other.role != Role::gear && other.role != Role::shaft &&
                    overlap(part_bounds(profile_, part), part_bounds(profile_, other))) return {nullptr, "occupied"};
        } else if (part.role != Role::shaft && part.role != Role::gear)
            if (const auto* refusal = machine_site_refusal(snapshot.state, center)) return {nullptr, refusal};
    }
    for (const auto& link : snapshot.state.topology.material_links) {
        const auto* from = find(snapshot.state, link.from.id);
        const auto* to = find(snapshot.state, link.to.id);
        if (!from || !to || to->geometry.center[0] != from->geometry.center[0] + 4 ||
            to->geometry.center[1] != from->geometry.center[1] ||
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
