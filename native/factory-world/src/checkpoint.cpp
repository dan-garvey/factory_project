#include "factory/checkpoint.hpp"
#include "factory/material_state_codec.hpp"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <string_view>
#include <utility>

namespace factory::world {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;

[[noreturn]] void refuse(CheckpointReason reason, std::string path) {
    throw CheckpointRefusal{reason, std::move(path)};
}

struct Budget {
    std::size_t nodes{}, bytes{};
    void visit(const Value& value, std::size_t depth = 0) {
        if (depth > 32 || ++nodes > 100000) refuse(CheckpointReason::limit, "$");
        const auto text = [&](const std::string& string) {
            if (string.size() > 1048576 || bytes > 4194304 - string.size())
                refuse(CheckpointReason::limit, "$");
            bytes += string.size();
        };
        if (const auto* string = std::get_if<std::string>(&value.storage())) text(*string);
        if (const auto* array = std::get_if<Array>(&value.storage()))
            for (const auto& item : *array) visit(item, depth + 1);
        if (const auto* object = std::get_if<Object>(&value.storage()))
            for (const auto& [key, item] : *object) { text(key); visit(item, depth + 1); }
    }
};

const Object& object(const Value& value, const std::string& path) {
    const auto* output = std::get_if<Object>(&value.storage());
    if (!output) refuse(CheckpointReason::wrong_type, path);
    return *output;
}

const Object& fields(const Value& value, const std::string& path,
                     std::initializer_list<std::string_view> names) {
    const auto& output = object(value, path);
    for (const auto name : names)
        if (!output.contains(std::string(name))) refuse(CheckpointReason::missing_field, path + "." + std::string(name));
    for (const auto& [key, item] : output) {
        (void)item;
        if (std::find(names.begin(), names.end(), key) == names.end())
            refuse(CheckpointReason::unexpected_field, path + "." + key);
    }
    return output;
}

template<class T> const T& scalar(const Value& value, const std::string& path) {
    const auto* output = std::get_if<T>(&value.storage());
    if (!output) refuse(CheckpointReason::wrong_type, path);
    return *output;
}

const Array& array(const Value& value, const std::string& path, std::size_t maximum) {
    const auto& output = scalar<Array>(value, path);
    if (output.size() > maximum) refuse(CheckpointReason::limit, path);
    return output;
}

Integer integer(const Object& input, const char* key, const std::string& path) {
    return scalar<Integer>(input.at(key), path + "." + key);
}

template<class Enum> Enum enumeration(const Object& input, const char* key,
                                     Integer maximum, const std::string& path) {
    const auto value = integer(input, key, path);
    if (value < 0 || value > maximum) refuse(CheckpointReason::invalid_world, path + "." + key);
    return static_cast<Enum>(value);
}

Value kit_value(const stationary::Kit& kit) {
    Array output;
    for (const auto& [spec, count] : kit) output.emplace_back(Object{
        {"role", Value(static_cast<Integer>(spec.role))}, {"teeth", Value(spec.teeth)},
        {"half_span", Value(spec.half_span)}, {"count", Value(count)}});
    return Value(std::move(output));
}

stationary::Kit decode_kit(const Value& value, const std::string& path) {
    stationary::Kit output;
    for (const auto& item : array(value, path, stationary::maximum_specifications)) {
        const auto& entry = fields(item, path, {"role", "teeth", "half_span", "count"});
        const stationary::PartSpec spec{enumeration<stationary::Role>(entry, "role", 8, path),
            integer(entry, "teeth", path), integer(entry, "half_span", path)};
        if (!output.emplace(spec, integer(entry, "count", path)).second)
            refuse(CheckpointReason::invalid_world, path);
    }
    return output;
}

Value profile_value(const Profile& profile) {
    if (!std::isfinite(profile.meters_per_grid_unit) || !std::isfinite(profile.build_reach))
        refuse(CheckpointReason::profile_mismatch, "$.profile");
    Array actors;
    for (const auto& actor : profile.actors) actors.emplace_back(actor);
    Object output{
        {"recipe_weight", Value(profile.material.input_units_per_product)},
        {"cycle_ticks", Value(profile.material.cycle_ticks)},
        {"collector_capacity", Value(profile.material.collector_capacity)},
        {"initial_units", Value(profile.initial_units)}, {"actors", Value(std::move(actors))},
        {"finite_parts", kit_value(profile.finite_parts)},
        {"waterwheel_numerator", Value(profile.waterwheel_rate.numerator)},
        {"waterwheel_denominator", Value(profile.waterwheel_rate.denominator)},
        {"meters_per_grid_unit", Value(profile.meters_per_grid_unit)},
        {"anchor_offset", Value(Array{Value(profile.anchor_offset[0]), Value(profile.anchor_offset[1]), Value(profile.anchor_offset[2])})},
        {"build_reach", Value(profile.build_reach)}};
    if (profile.foundation_parts > 0) output.emplace("foundation_parts", Value(profile.foundation_parts));
    if (profile.landing_pod_center) {
        const auto& center = *profile.landing_pod_center;
        output.emplace("landing_pod_center", Value(Array{Value(center[0]), Value(center[1]), Value(center[2])}));
    }
    if (profile.material.manual_ore || !profile.material.timber_sites.empty()) {
        Array trees;
        for (const auto& [id, site] : profile.material.timber_sites)
            trees.emplace_back(Object{{"id", Value(id)},
                {"center", Value(Array{Value(site.center[0]), Value(site.center[1]), Value(site.center[2])})},
                {"initial", Value(site.initial)}});
        output.emplace("timber_sites", Value(std::move(trees)));
        output.emplace("hand_carry_capacity", Value(profile.material.hand_carry_capacity));
        output.emplace("component_capacity", Value(profile.material.component_capacity));
        if (profile.material.manual_ore) {
            const auto& site = *profile.material.manual_ore;
            output.emplace("manual_ore", Value(Object{{"id", Value(site.id)},
                {"center", Value(Array{Value(site.center[0]), Value(site.center[1]), Value(site.center[2])})}}));
        }
    }
    if (!profile.water.empty()) {
        Array water;
        for (const auto& [location, sample] : profile.water) water.emplace_back(Object{
            {"x", Value(location[0])}, {"z", Value(location[1])},
            {"surface", Value(sample.surface)}, {"bed", Value(sample.bed)},
            {"velocity_x", Value(sample.velocity_x)}, {"velocity_z", Value(sample.velocity_z)}});
        output.emplace("water", Value(std::move(water)));
        output.emplace("wheel_radius", Value(profile.wheel_radius));
        output.emplace("wheel_axle_offset", Value(profile.wheel_axle_offset));
    }
    return Value(std::move(output));
}

Value ref_value(const materials::EntityRef& reference) {
    return Value(Object{{"id", Value(reference.id)}, {"generation", Value(reference.generation)}});
}

materials::EntityRef decode_ref(const Value& value, const std::string& path) {
    const auto& input = fields(value, path, {"id", "generation"});
    return {scalar<std::string>(input.at("id"), path + ".id"), integer(input, "generation", path)};
}

Value topology_value(const stationary::Topology& topology) {
    Array parts, links, sources, belt_spans;
    for (const auto& part : topology.parts) {
        const auto& geometry = part.geometry;
        parts.emplace_back(Object{
            {"id", Value(geometry.id)}, {"generation", Value(part.generation)},
            {"role", Value(static_cast<Integer>(part.role))},
            {"kind", Value(static_cast<Integer>(geometry.kind))},
            {"axis", Value(static_cast<Integer>(geometry.axis))},
            {"relay_axis", Value(static_cast<Integer>(geometry.relay_axis))},
            {"center", Value(Array{Value(geometry.center[0]), Value(geometry.center[1]), Value(geometry.center[2])})},
            {"teeth", Value(geometry.teeth)}, {"half_span", Value(geometry.half_span)},
            {"wheel_tiles", Value(part.wheel_tiles)}, {"rotation", Value(part.rotation)}});
    }
    for (const auto& link : topology.material_links)
        links.emplace_back(Object{{"from", ref_value(link.from)}, {"to", ref_value(link.to)}});
    for (const auto& source : topology.sources)
        sources.emplace_back(Object{{"hub", Value(source.hub)},
            {"numerator", Value(source.rate.numerator)}, {"denominator", Value(source.rate.denominator)}});
    for (const auto& span : topology.belt_spans)
        belt_spans.emplace_back(Object{{"id", Value(span.geometry.id)}, {"generation", Value(span.generation)},
            {"first_shaft", Value(span.geometry.first_shaft)}, {"last_shaft", Value(span.geometry.last_shaft)}});
    return Value(Object{{"parts", Value(std::move(parts))}, {"links", Value(std::move(links))},
        {"sources", Value(std::move(sources))}, {"drive_enabled", Value(topology.drive_enabled)},
        {"belt_spans", Value(std::move(belt_spans))}});
}

stationary::Topology decode_topology(const Value& value) {
    const std::string path = "$.state.topology";
    const auto& input = fields(value, path, {"parts", "links", "sources", "drive_enabled", "belt_spans"});
    stationary::Topology topology;
    topology.drive_enabled = scalar<bool>(input.at("drive_enabled"), path + ".drive_enabled");
    for (const auto& value_part : array(input.at("parts"), path + ".parts", mechanics::maximum_parts)) {
        const auto& entry = fields(value_part, path + ".parts",
            {"id", "generation", "role", "kind", "axis", "relay_axis", "center", "teeth", "half_span", "wheel_tiles", "rotation"});
        const auto& center = array(entry.at("center"), path + ".parts.center", 3);
        if (center.size() != 3) refuse(CheckpointReason::invalid_world, path + ".parts.center");
        topology.parts.push_back({{
            scalar<std::string>(entry.at("id"), path + ".parts.id"),
            enumeration<mechanics::Kind>(entry, "kind", 4, path + ".parts"),
            {scalar<Integer>(center[0], path + ".parts.center"),
             scalar<Integer>(center[1], path + ".parts.center"),
             scalar<Integer>(center[2], path + ".parts.center")},
            enumeration<mechanics::Axis>(entry, "axis", 2, path + ".parts"),
            integer(entry, "teeth", path + ".parts"), integer(entry, "half_span", path + ".parts"),
            enumeration<mechanics::Axis>(entry, "relay_axis", 2, path + ".parts")},
            integer(entry, "generation", path + ".parts"),
            enumeration<stationary::Role>(entry, "role", 8, path + ".parts"),
            integer(entry, "wheel_tiles", path + ".parts"), integer(entry, "rotation", path + ".parts")});
    }
    for (const auto& value_link : array(input.at("links"), path + ".links", 2)) {
        const auto& entry = fields(value_link, path + ".links", {"from", "to"});
        topology.material_links.push_back({decode_ref(entry.at("from"), path + ".links.from"),
                                           decode_ref(entry.at("to"), path + ".links.to")});
    }
    for (const auto& value_source : array(input.at("sources"), path + ".sources", mechanics::maximum_parts)) {
        const auto& entry = fields(value_source, path + ".sources", {"hub", "numerator", "denominator"});
        topology.sources.push_back({scalar<std::string>(entry.at("hub"), path + ".sources.hub"),
            {integer(entry, "numerator", path + ".sources"), integer(entry, "denominator", path + ".sources")}});
    }
    for (const auto& value_span : array(input.at("belt_spans"), path + ".belt_spans", mechanics::maximum_parts)) {
        const auto& entry = fields(value_span, path + ".belt_spans", {"id", "generation", "first_shaft", "last_shaft"});
        topology.belt_spans.push_back({{scalar<std::string>(entry.at("id"), path + ".belt_spans.id"),
            scalar<std::string>(entry.at("first_shaft"), path + ".belt_spans.first_shaft"),
            scalar<std::string>(entry.at("last_shaft"), path + ".belt_spans.last_shaft")},
            integer(entry, "generation", path + ".belt_spans")});
    }
    return topology;
}

void material_collection_limits(const Value& value) {
    // Bound before the material codec's allocation and quadratic serial check.
    const auto& material = object(value, "$.state.material");
    const auto found = material.find("cargo");
    if (found == material.end()) refuse(CheckpointReason::missing_field, "$.state.material.cargo");
    const auto& cargo = object(found->second, "$.state.material.cargo");
    if (cargo.size() > 16) refuse(CheckpointReason::limit, "$.state.material.cargo");
    std::size_t lots = 0;
    for (const auto& [actor, contents] : cargo) {
        (void)actor;
        const auto& entry = object(contents, "$.state.material.cargo");
        const auto found_lots = entry.find("work_lots");
        if (found_lots == entry.end()) refuse(CheckpointReason::missing_field, "$.state.material.cargo.work_lots");
        lots += array(found_lots->second, "$.state.material.cargo.work_lots", 256).size();
        if (lots > 256) refuse(CheckpointReason::limit, "$.state.material.cargo.work_lots");
    }
    const auto processing = material.find("processing");
    if (processing != material.end() && processing->second.type() != values::Type::null && ++lots > 256)
        refuse(CheckpointReason::limit, "$.state.material.processing");
    const auto lanes = material.find("belt_lanes");
    if (lanes == material.end()) refuse(CheckpointReason::missing_field, "$.state.material.belt_lanes");
    const auto& entries = object(lanes->second, "$.state.material.belt_lanes");
    if (entries.size() > 256) refuse(CheckpointReason::limit, "$.state.material.belt_lanes");
    for (const auto& [id, value] : entries) {
        (void)id;
        const auto& lane = object(value, "$.state.material.belt_lanes");
        const auto found_slots = lane.find("slots");
        if (found_slots == lane.end()) refuse(CheckpointReason::missing_field, "$.state.material.belt_lanes.slots");
        for (const auto& item : array(found_slots->second, "$.state.material.belt_lanes.slots", materials::maximum_belt_slots)) {
            if (item.type() == values::Type::null) continue;
            const auto& contents = object(item, "$.state.material.belt_lanes.item");
            const auto found_work = contents.find("work_lots");
            if (found_work == contents.end()) refuse(CheckpointReason::missing_field, "$.state.material.belt_lanes.item.work_lots");
            lots += array(found_work->second, "$.state.material.belt_lanes.item.work_lots", 1).size();
            if (lots > 256) refuse(CheckpointReason::limit, "$.state.material.belt_lanes.item.work_lots");
        }
    }
}
}  // namespace

CheckpointEncoding encode_checkpoint(const Profile& profile, const Snapshot& snapshot) {
    try {
        if (!validate(profile, snapshot)) refuse(CheckpointReason::invalid_world, "$");
        auto material = materials::encode_material_state(snapshot.state.material, profile.material,
            material_path(snapshot.state.topology), {profile.actors.begin(), profile.actors.end()});
        if (!std::holds_alternative<Value>(material)) refuse(CheckpointReason::invalid_material, "$.state.material");
        auto history = authority::encode_history(snapshot.history, snapshot.revision);
        if (!history.value) refuse(CheckpointReason::invalid_history, "$.history");
        Object kits, issued;
        for (const auto& [actor, kit] : snapshot.state.kits) kits.emplace(actor, kit_value(kit));
        for (const auto& [id, generation] : snapshot.state.issued_entities) issued.emplace(id, Value(generation));
        Value output(Object{
            {"schema", Value(Integer{7})}, {"profile", profile_value(profile)},
            {"revision", Value(snapshot.revision)}, {"history", std::move(*history.value)},
            {"state", Value(Object{{"material", std::move(std::get<Value>(material))},
                {"topology", topology_value(snapshot.state.topology)}, {"kits", Value(std::move(kits))},
                {"issued_entities", Value(std::move(issued))},
                {"next_entity_serial", Value(snapshot.state.next_entity_serial)}})}});
        if (profile.foundation_parts > 0) {
            Object foundations, foundation_kits;
            for (const auto& [id, foundation] : snapshot.state.foundations)
                foundations.emplace(id, Value(Object{{"center", Value(Array{Value(foundation.center[0]),
                    Value(foundation.center[1]), Value(foundation.center[2])})},
                    {"generation", Value(foundation.generation)}}));
            for (const auto& [actor, count] : snapshot.state.foundation_kits) foundation_kits.emplace(actor, Value(count));
            auto root = std::get<Object>(output.storage());
            auto state = std::get<Object>(root.at("state").storage());
            state.emplace("foundations", Value(std::move(foundations)));
            state.emplace("foundation_kits", Value(std::move(foundation_kits)));
            root.at("state") = Value(std::move(state));
            output = Value(std::move(root));
        }
        if (snapshot.state.landing_pod) {
            const auto& pod = *snapshot.state.landing_pod;
            auto root = std::get<Object>(output.storage());
            auto state = std::get<Object>(root.at("state").storage());
            state.emplace("landing_pod", Value(Object{{"id", Value(pod.id)},
                {"center", Value(Array{Value(pod.center[0]), Value(pod.center[1]), Value(pod.center[2])})},
                {"generation", Value(pod.generation)}}));
            root.at("state") = Value(std::move(state));
            output = Value(std::move(root));
        }
        Budget{}.visit(output);
        return output;
    } catch (const CheckpointRefusal& failure) { return failure; }
}

CheckpointDecoding decode_checkpoint(const Profile& profile, const std::string& expected_context,
                                    const Value& value) {
    try {
        Budget{}.visit(value);
        const auto& root = fields(value, "$", {"schema", "profile", "revision", "history", "state"});
        if (integer(root, "schema", "$") != 7) refuse(CheckpointReason::unsupported_schema, "$.schema");
        if (const auto difference = values::typed_difference(profile_value(profile), root.at("profile")))
            refuse(CheckpointReason::profile_mismatch, "$.profile" + difference->path.substr(1));
        Snapshot candidate;
        candidate.revision = integer(root, "revision", "$");
        auto history = authority::decode_history(root.at("history"), candidate.revision);
        if (!history.history) refuse(CheckpointReason::invalid_history, "$.history");
        candidate.history = std::move(*history.history);
        if (candidate.history.context != expected_context) refuse(CheckpointReason::wrong_context, "$.history.context");
        const auto& state = profile.landing_pod_center ? fields(root.at("state"), "$.state",
            {"material", "topology", "kits", "issued_entities", "next_entity_serial", "foundations", "foundation_kits", "landing_pod"}) :
            profile.foundation_parts > 0 ? fields(root.at("state"), "$.state",
            {"material", "topology", "kits", "issued_entities", "next_entity_serial", "foundations", "foundation_kits"}) :
            fields(root.at("state"), "$.state", {"material", "topology", "kits", "issued_entities", "next_entity_serial"});
        if (profile.landing_pod_center) {
            const auto& pod = fields(state.at("landing_pod"), "$.state.landing_pod", {"id", "center", "generation"});
            const auto& center = array(pod.at("center"), "$.state.landing_pod.center", 3);
            if (center.size() != 3) refuse(CheckpointReason::invalid_world, "$.state.landing_pod.center");
            candidate.state.landing_pod = LandingPod{scalar<std::string>(pod.at("id"), "$.state.landing_pod.id"),
                {scalar<Integer>(center[0], "$.state.landing_pod.center"),
                 scalar<Integer>(center[1], "$.state.landing_pod.center"),
                 scalar<Integer>(center[2], "$.state.landing_pod.center")},
                integer(pod, "generation", "$.state.landing_pod")};
        }
        if (profile.foundation_parts > 0) {
            const auto& foundations = object(state.at("foundations"), "$.state.foundations");
            if (foundations.size() > 256) refuse(CheckpointReason::limit, "$.state.foundations");
            for (const auto& [id, value] : foundations) {
                const auto& entry = fields(value, "$.state.foundations", {"center", "generation"});
                const auto& center = array(entry.at("center"), "$.state.foundations.center", 3);
                if (center.size() != 3) refuse(CheckpointReason::invalid_world, "$.state.foundations.center");
                candidate.state.foundations.emplace(id, Foundation{{
                    scalar<Integer>(center[0], "$.state.foundations.center"),
                    scalar<Integer>(center[1], "$.state.foundations.center"),
                    scalar<Integer>(center[2], "$.state.foundations.center")}, integer(entry, "generation", "$.state.foundations")});
            }
            const auto& kits = object(state.at("foundation_kits"), "$.state.foundation_kits");
            if (kits.size() > 16) refuse(CheckpointReason::limit, "$.state.foundation_kits");
            for (const auto& [actor, count] : kits)
                candidate.state.foundation_kits.emplace(actor, scalar<Integer>(count, "$.state.foundation_kits"));
        }
        candidate.state.topology = decode_topology(state.at("topology"));
        material_collection_limits(state.at("material"));
        auto material = materials::decode_material_state(state.at("material"), profile.material,
            material_path(candidate.state.topology), {profile.actors.begin(), profile.actors.end()});
        if (!std::holds_alternative<materials::State>(material))
            refuse(CheckpointReason::invalid_material, "$.state.material");
        candidate.state.material = std::move(std::get<materials::State>(material));
        const auto& kits = object(state.at("kits"), "$.state.kits");
        if (kits.size() > 16) refuse(CheckpointReason::limit, "$.state.kits");
        for (const auto& [actor, kit] : kits) candidate.state.kits.emplace(actor, decode_kit(kit, "$.state.kits"));
        const auto& issued = object(state.at("issued_entities"), "$.state.issued_entities");
        if (issued.size() > 4096) refuse(CheckpointReason::limit, "$.state.issued_entities");
        for (const auto& [id, generation] : issued)
            candidate.state.issued_entities.emplace(id, scalar<Integer>(generation, "$.state.issued_entities"));
        candidate.state.next_entity_serial = integer(state, "next_entity_serial", "$.state");
        if (!validate(profile, candidate)) refuse(CheckpointReason::invalid_world, "$");
        return candidate;
    } catch (const CheckpointRefusal& failure) { return failure; }
}

}  // namespace factory::world
