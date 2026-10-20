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
        const stationary::PartSpec spec{enumeration<stationary::Role>(entry, "role", 5, path),
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
    return Value(Object{
        {"recipe_weight", Value(profile.material.input_units_per_product)},
        {"cycle_ticks", Value(profile.material.cycle_ticks)},
        {"collector_capacity", Value(profile.material.collector_capacity)},
        {"initial_units", Value(profile.initial_units)}, {"actors", Value(std::move(actors))},
        {"finite_parts", kit_value(profile.finite_parts)},
        {"waterwheel_numerator", Value(profile.waterwheel_rate.numerator)},
        {"waterwheel_denominator", Value(profile.waterwheel_rate.denominator)},
        {"meters_per_grid_unit", Value(profile.meters_per_grid_unit)},
        {"build_reach", Value(profile.build_reach)}});
}

Value ref_value(const materials::EntityRef& reference) {
    return Value(Object{{"id", Value(reference.id)}, {"generation", Value(reference.generation)}});
}

materials::EntityRef decode_ref(const Value& value, const std::string& path) {
    const auto& input = fields(value, path, {"id", "generation"});
    return {scalar<std::string>(input.at("id"), path + ".id"), integer(input, "generation", path)};
}

Value topology_value(const stationary::Topology& topology) {
    Array parts, links, sources;
    for (const auto& part : topology.parts) {
        const auto& geometry = part.geometry;
        parts.emplace_back(Object{
            {"id", Value(geometry.id)}, {"generation", Value(part.generation)},
            {"role", Value(static_cast<Integer>(part.role))},
            {"kind", Value(static_cast<Integer>(geometry.kind))},
            {"axis", Value(static_cast<Integer>(geometry.axis))},
            {"center", Value(Array{Value(geometry.center[0]), Value(geometry.center[1]), Value(geometry.center[2])})},
            {"teeth", Value(geometry.teeth)}, {"half_span", Value(geometry.half_span)}});
    }
    for (const auto& link : topology.material_links)
        links.emplace_back(Object{{"from", ref_value(link.from)}, {"to", ref_value(link.to)}});
    for (const auto& source : topology.sources)
        sources.emplace_back(Object{{"hub", Value(source.hub)},
            {"numerator", Value(source.rate.numerator)}, {"denominator", Value(source.rate.denominator)}});
    return Value(Object{{"parts", Value(std::move(parts))}, {"links", Value(std::move(links))},
        {"sources", Value(std::move(sources))}, {"drive_enabled", Value(topology.drive_enabled)}});
}

stationary::Topology decode_topology(const Value& value) {
    const std::string path = "$.state.topology";
    const auto& input = fields(value, path, {"parts", "links", "sources", "drive_enabled"});
    stationary::Topology topology;
    topology.drive_enabled = scalar<bool>(input.at("drive_enabled"), path + ".drive_enabled");
    for (const auto& value_part : array(input.at("parts"), path + ".parts", mechanics::maximum_parts)) {
        const auto& entry = fields(value_part, path + ".parts",
            {"id", "generation", "role", "kind", "axis", "center", "teeth", "half_span"});
        const auto& center = array(entry.at("center"), path + ".parts.center", 3);
        if (center.size() != 3) refuse(CheckpointReason::invalid_world, path + ".parts.center");
        topology.parts.push_back({{
            scalar<std::string>(entry.at("id"), path + ".parts.id"),
            enumeration<mechanics::Kind>(entry, "kind", 2, path + ".parts"),
            {scalar<Integer>(center[0], path + ".parts.center"),
             scalar<Integer>(center[1], path + ".parts.center"),
             scalar<Integer>(center[2], path + ".parts.center")},
            enumeration<mechanics::Axis>(entry, "axis", 2, path + ".parts"),
            integer(entry, "teeth", path + ".parts"), integer(entry, "half_span", path + ".parts")},
            integer(entry, "generation", path + ".parts"),
            enumeration<stationary::Role>(entry, "role", 5, path + ".parts")});
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
            {"schema", Value(Integer{1})}, {"profile", profile_value(profile)},
            {"revision", Value(snapshot.revision)}, {"history", std::move(*history.value)},
            {"state", Value(Object{{"material", std::move(std::get<Value>(material))},
                {"topology", topology_value(snapshot.state.topology)}, {"kits", Value(std::move(kits))},
                {"issued_entities", Value(std::move(issued))},
                {"next_entity_serial", Value(snapshot.state.next_entity_serial)}})}});
        Budget{}.visit(output);
        return output;
    } catch (const CheckpointRefusal& failure) { return failure; }
}

CheckpointDecoding decode_checkpoint(const Profile& profile, const std::string& expected_context,
                                    const Value& value) {
    try {
        Budget{}.visit(value);
        const auto& root = fields(value, "$", {"schema", "profile", "revision", "history", "state"});
        if (integer(root, "schema", "$") != 1) refuse(CheckpointReason::unsupported_schema, "$.schema");
        if (const auto difference = values::typed_difference(profile_value(profile), root.at("profile")))
            refuse(CheckpointReason::profile_mismatch, "$.profile" + difference->path.substr(1));
        Snapshot candidate;
        candidate.revision = integer(root, "revision", "$");
        auto history = authority::decode_history(root.at("history"), candidate.revision);
        if (!history.history) refuse(CheckpointReason::invalid_history, "$.history");
        candidate.history = std::move(*history.history);
        if (candidate.history.context != expected_context) refuse(CheckpointReason::wrong_context, "$.history.context");
        const auto& state = fields(root.at("state"), "$.state",
            {"material", "topology", "kits", "issued_entities", "next_entity_serial"});
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
