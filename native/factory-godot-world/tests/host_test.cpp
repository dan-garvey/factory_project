#include "factory/godot_world.hpp"
#include "factory/machine_placement_contract.hpp"
#include "factory/projection_contract.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <array>
#include <functional>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string_view>
#include <tuple>
#include <utility>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};

void check(bool value, const char* message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}

template<class T> const T& field(const V& value, const char* name) {
    return std::get<T>(std::get<O>(value.storage()).at(name).storage());
}

bool accepted(const V& value) { return field<bool>(value, "accepted"); }

O request(const char* action, const char* id) {
    return {{"context", V("host-boundary")}, {"client", V("P")}, {"request", V(id)}, {"action", V(action)}};
}

O target(const char* action, const char* id, const std::string& entity) {
    auto wire = request(action, id);
    wire.emplace("entity", V(entity));
    return wire;
}

O link(const char* action, const char* id, const std::string& from, const std::string& to) {
    auto wire = request(action, id);
    wire.emplace("from", V(from)); wire.emplace("to", V(to));
    return wire;
}

V alter_wire(const V& saved, const std::string& request_id, const std::string& key, V replacement) {
    auto root = std::get<O>(saved.storage());
    auto world = field<O>(saved, "world");
    auto history = field<O>(V(world), "history");
    auto records = field<A>(V(history), "records");
    bool found = false;
    for (auto& value : records) {
        auto record = std::get<O>(value.storage());
        auto intent = field<O>(value, "intent");
        if (field<std::string>(V(intent), "request") != request_id) continue;
        auto wire = field<O>(V(intent), "wire");
        wire.insert_or_assign(key, std::move(replacement));
        intent.at("wire") = V(std::move(wire));
        record.at("intent") = V(std::move(intent));
        value = V(std::move(record));
        found = true;
        break;
    }
    check(found, "The mutation must alter an existing original request.");
    history.at("records") = V(std::move(records));
    world.at("history") = V(std::move(history));
    root.at("world") = V(std::move(world));
    return V(std::move(root));
}

V alter_saved_action(const V& saved, const std::string& request_id, const char* action) {
    auto root = std::get<O>(saved.storage());
    auto world = field<O>(saved, "world");
    auto history = field<O>(V(world), "history");
    auto records = field<A>(V(history), "records");
    bool found = false;
    for (auto& value : records) {
        auto record = std::get<O>(value.storage());
        auto intent = field<O>(value, "intent");
        if (field<std::string>(V(intent), "request") != request_id) continue;
        intent.at("action") = V(action);
        record.at("intent") = V(std::move(intent));
        value = V(std::move(record));
        found = true;
        break;
    }
    check(found, "The mutation must alter an existing normalized placement action.");
    history.at("records") = V(std::move(records));
    world.at("history") = V(std::move(history));
    root.at("world") = V(std::move(world));
    return V(std::move(root));
}

void historical_translation() {
    Host host;
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)}, heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    const O site{{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})},
        {"water", V(A{V(A{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})})})}};
    check(accepted(host.initialize("host-boundary", {"P"})), "The finite test World initializes.");
    check(accepted(host.configure_terrain(site)), "The test binds its explicit forward-driving synthetic terrain.");
    I epoch{};
    const auto at = [&](double x, double z) {
        check(accepted(host.publish_actor("P", {V(x), V(1.0), V(z)}, ++epoch)),
              "The disclosed synthetic observation reaches the next construction.");
    };
    const auto place = [&](const char* kind, I x, I z, I level, const char* axis_name, const char* id) {
        auto wire = request("place", id);
        wire.emplace("kind", V(kind)); wire.emplace("cell", V(A{V(x), V(z)})); wire.emplace("axis", V(axis_name));
        wire.emplace("level", V(level));
        if (std::string_view(kind) == "collector") wire.emplace("rotation", V(I{0}));
        if (std::string_view(kind) == "wheel") wire.emplace("tiles", V(I{3}));
        const auto reply = host.command("P", wire);
        check(accepted(reply), (std::string("The starter placement succeeds: ") + kind + ", " + field<std::string>(reply, "reason")).c_str());
        return field<std::string>(reply, "entity");
    };
    const auto foundation = [&](I x, const char* id) {
        auto base = request("place_foundation", id);
        base.emplace("cell", V(A{V(x), V(I{1})})); base.emplace("level", V(I{4}));
        check(accepted(host.command("P", base)), "The machine's raised foundation is placed.");
    };
    const auto cog = [&](I x, I z, const char* axis_name, I teeth, const char* id) {
        auto gear = request("place_gear", id);
        gear.emplace("center", V(A{V(x), V(I{4}), V(z)}));
        gear.emplace("axis", V(axis_name)); gear.emplace("teeth", V(teeth));
        const auto placed = host.command("P", gear);
        check(accepted(placed), ("The cog placement succeeds: " + field<std::string>(placed, "reason")).c_str());
        return field<std::string>(placed, "entity");
    };
    const auto shaft = [&](I x, I z, const char* id) {
        auto wire = request("place_shaft", id);
        wire.emplace("center", V(A{V(x), V(I{4}), V(z)})); wire.emplace("axis", V("z"));
        wire.emplace("half_span", V(I{2}));
        const auto placed = host.command("P", wire);
        check(accepted(placed), ("The shaft placement succeeds: " + field<std::string>(placed, "reason")).c_str());
        return field<std::string>(placed, "entity");
    };
    at(-1.65, 3.3);
    const auto wheel = place("wheel", -2, 0, 4, "x", "wheel");
    at(0, 0); foundation(0, "collector-base");
    const auto collector = place("collector", 0, 1, 4, "z", "collector");
    at(-3.3, 0); cog(-4, 0, "x", 4, "input-cog");
    at(-3.3, -1.65); cog(0, -4, "z", 4, "output-cog");
    for (I x : {I{0}, I{4}}) {
        at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
        const auto id = "front-cog-" + std::to_string(x);
        cog(x, 0, "z", 2, id.c_str());
    }
    for (I x : {I{4}, I{8}, I{12}}) {
        at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
        const auto id = "rear-cog-" + std::to_string(x);
        cog(x, -4, "z", 2, id.c_str());
    }
    at(4.95, -3.3); shaft(12, 0, "press-drive");
    at(1.65, 0); const auto first = shaft(4, 4, "first-shaft");
    at(3.3, 0); const auto last = shaft(8, 4, "last-shaft");
    at(2.475, 0);
    const auto belt_reply = host.command("P", link("place_belt_span", "span", first, last));
    check(accepted(belt_reply), "The physical belt joins both shafts.");
    const auto belt = field<std::string>(belt_reply, "entity");
    at(4.95, 0); foundation(3, "press-base");
    const auto press = place("processor", 3, 1, 4, "z", "press");
    check(field<bool>(host.projection(), "powered"), "The existing wheel supplies the test line automatically.");
    const auto before_targets = host.projection();
    const auto before_target_state = field<O>(V(field<O>(host.checkpoint(), "world")), "state");
    auto bad_remove = target("remove", "bad-target-remove", press);
    bad_remove.at("entity") = V(I{1});
    auto bad_recover = target("recover", "bad-target-recover", press);
    bad_recover.emplace("extra", V(true));
    auto bad_collect = target("retrieve", "bad-target-collect", press);
    bad_collect.emplace("amount", V(1.0));
    auto bad_insert_raw = target("insert_raw", "bad-target-raw", press);
    bad_insert_raw.emplace("amount", V(false));
    auto bad_insert_work = target("insert_work", "bad-target-work", press);
    bad_insert_work.emplace("work_id", V(1.0));
    auto bad_connect = link("connect_drive", "bad-target-connect", wheel, press);
    bad_connect.at("to") = V(I{1});
    auto bad_disconnect = link("disconnect_drive", "bad-target-disconnect", wheel, press);
    bad_disconnect.emplace("extra", V(true));
    for (const auto& malformed : {bad_remove, bad_recover, bad_collect, bad_insert_raw,
                                  bad_insert_work, bad_connect, bad_disconnect}) {
        const auto reply = host.command("P", malformed);
        check(!accepted(reply) && field<std::string>(reply, "reason") == "invalid_command",
              "Malformed target and material-port requests refuse with the original command reason.");
    }
    const auto bad_place = [&](const char* id, const char* kind) {
        auto wire = request("place", id);
        wire.emplace("kind", V(kind)); wire.emplace("cell", V(A{V(I{0}), V(I{1})}));
        wire.emplace("axis", V("z")); wire.emplace("level", V(I{4}));
        return wire;
    };
    const auto place_refuses = [&](O wire, const char* reason) {
        const auto reply = host.command("P", wire);
        check(!accepted(reply) && field<std::string>(reply, "reason") == reason,
              (std::string("Malformed machine placement must refuse as ") + reason).c_str());
    };
    auto wrong_optional = bad_place("wrong-optional", "wheel");
    wrong_optional.emplace("rotation", V(I{0}));
    place_refuses(wrong_optional, "invalid_command");
    auto wrong_axis = bad_place("wrong-axis", "collector");
    wrong_axis.at("axis") = V(I{1}); wrong_axis.emplace("rotation", V(I{4}));
    place_refuses(wrong_axis, "invalid_axis");
    auto wrong_rotation = bad_place("wrong-rotation", "collector");
    wrong_rotation.emplace("rotation", V(I{4})); wrong_rotation.at("cell") = V(false);
    place_refuses(wrong_rotation, "invalid_rotation");
    auto wrong_cell = bad_place("wrong-cell", "unknown");
    wrong_cell.at("cell") = V(A{V(I{250001}), V(I{0})});
    place_refuses(wrong_cell, "invalid_cell");
    auto unknown_kind = bad_place("unknown-kind", "unknown");
    unknown_kind.at("level") = V(I{5});
    place_refuses(unknown_kind, "unknown_kind");
    auto unaligned = bad_place("unaligned", "collector");
    unaligned.at("level") = V(I{5});
    place_refuses(unaligned, "unaligned_elevation");
    auto bad_wheel = bad_place("bad-wheel", "wheel");
    bad_wheel.emplace("tiles", V(false));
    place_refuses(bad_wheel, "invalid_wheel_size");
    check(field<I>(before_targets, "revision") == field<I>(host.projection(), "revision") &&
          !factory::values::typed_difference(V(before_target_state),
              V(field<O>(V(field<O>(host.checkpoint(), "world")), "state"))),
          "Malformed target requests preserve native revision, material custody and world state.");
    for (int index = 0; index < 150; ++index) (void)host.advance();
    at(4.95, 0);
    auto collect = target("retrieve", "collect", press); collect.emplace("amount", V(I{1}));
    check(accepted(host.command("P", collect)), "The checkpoint includes an accepted product amount.");
    const auto recovery = target("recover", "recover", press);
    check(accepted(host.command("P", recovery)), "The checkpoint includes accepted recovery of the original target.");
    check(accepted(host.command("P", target("remove", "remove", press))), "The original target can be removed.");
    auto malformed = request("place", "malformed"); malformed.emplace("cell", V(false));
    check(!accepted(host.command("P", malformed)), "An intentionally malformed adapter refusal is retained.");
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "Removed historical targets and malformed refusals remain valid.");
    {
        const auto world = field<O>(saved, "world");
        const auto history = field<O>(V(world), "history");
        const auto records = field<A>(V(history), "records");
        int placements = 0;
        for (const auto& record : records) {
            const auto intent = field<O>(record, "intent");
            const auto id = field<std::string>(V(intent), "request");
            if (id != "wheel" && id != "collector" && id != "press") continue;
            const auto wire = field<O>(V(intent), "wire");
            const auto action = field<std::string>(V(intent), "action");
            check(factory::machine_placement::historical_wire(wire, intent, action),
                  "An actual saved machine placement keeps its original Host translation.");
            auto forged = intent;
            const auto wrong = action == "place" ? "place_connected" : "place";
            forged.at("action") = V(wrong);
            check(!factory::machine_placement::historical_wire(wire, forged, wrong),
                  "A saved machine wire cannot claim the other normalized placement action.");
            ++placements;
        }
        check(placements == 3, "The saved line exercises wheel, collector and press actions.");
    }
    for (const auto& [id, wrong] : {std::pair{"wheel", "place_connected"},
                                    std::pair{"collector", "place"},
                                    std::pair{"press", "place"}}) {
        const auto reply = host.validate_checkpoint(alter_saved_action(saved, id, wrong));
        check(!accepted(reply) && !factory::values::typed_difference(saved, host.checkpoint()),
              "A forged normalized machine action refuses without changing the live Host.");
    }
    const auto reject = [&](const char* id, const char* key, V value) {
        const auto changed = alter_wire(saved, id, key, std::move(value));
        const auto reply = host.validate_checkpoint(changed);
        check(!accepted(reply) && field<std::string>(reply, "reason") == "inconsistent_wire_history",
              (std::string("Tampered ") + id + "." + key + " must reject as inconsistent wire history; got " +
               field<std::string>(reply, "reason")).c_str());
        check(!factory::values::typed_difference(saved, host.checkpoint()), "Refused validation never changes the live authority.");
    };
    reject("recover", "entity", V(belt));
    reject("collect", "amount", V(I{2}));
    reject("collect", "amount", V(1.0));
    reject("collect", "action", V("recover"));
    reject("span", "to", V(wheel));
    reject("span", "from", V(collector));
    reject("collector", "cell", V(A{V(I{0}), V(I{0})}));
    reject("collector", "kind", V("belt"));
    reject("collector", "rotation", V(I{1}));
    reject("wheel", "tiles", V(I{6}));
    reject("input-cog", "teeth", V(I{1}));
    reject("first-shaft", "half_span", V(I{3}));
    Host fresh;
    check(accepted(fresh.initialize("new-host", {"P"})), "A separate fresh Host initializes.");
    check(accepted(fresh.configure_terrain(site)), "The fresh Host binds the same synthetic terrain.");
    check(accepted(fresh.restore_checkpoint(saved)), "The unchanged complete checkpoint restores.");
    check(!factory::values::typed_difference(saved, fresh.checkpoint()), "Restore preserves the original typed history and state.");
    const auto restored_actor = fresh.actor_projection("P");
    check(accepted(restored_actor) && !field<bool>(restored_actor, "ready") &&
          field<I>(restored_actor, "native_epoch") == 0 &&
          !factory::values::typed_difference(V(field<A>(restored_actor, "position")),
                                              V(field<A>(host.actor_projection("P"), "position"))),
          "A restored Host retains the saved pose but requires a fresh physical publication.");
    const auto retry = fresh.command("P", recovery);
    check(accepted(retry) && field<bool>(retry, "duplicate") && field<std::string>(retry, "entity") == press,
          "Historical recovery replays before present target lookup or native readiness.");
}

void exact_observation_conversion() {
    Host missing;
    check(!accepted(missing.actor_projection("P")) &&
          field<std::string>(missing.actor_projection("P"), "reason") == "not_initialized",
          "The narrow actor view refuses an uninitialized Host.");
    Host host;
    check(accepted(host.initialize("host-boundary", {"P"})), "The observation test Host initializes.");
    check(!accepted(host.actor_projection("Q")) &&
          field<std::string>(host.actor_projection("Q"), "reason") == "unknown_actor",
          "The narrow actor view refuses an unknown identity.");
    const auto unready = host.actor_projection("P");
    check(accepted(unready) && !field<bool>(unready, "ready") &&
          field<I>(unready, "native_epoch") == 0,
          "The registered actor is unready before a physical publication.");
    for (const I coordinate : {I{9007199254740993}, I{-9007199254740993}}) {
        const auto reply = host.publish_actor("P", {V(coordinate), V(I{1}), V(I{0})}, 1);
        check(!accepted(reply) && field<std::string>(reply, "reason") == "invalid_actor_sample",
              "The original integer immediately beyond either exact boundary is refused before conversion.");
        check(!field<bool>(V(field<O>(V(field<O>(host.projection(), "actors")), "P")), "ready"),
              "A lossy observation cannot mark the actor ready.");
    }
    I epoch = 1;
    for (const I coordinate : {I{9007199254740992}, I{-9007199254740992}}) {
        check(accepted(host.publish_actor("P", {V(coordinate), V(I{1}), V(I{0})}, epoch++)),
              "An exact integer at either inclusive boundary remains accepted.");
        const auto actor = V(field<O>(V(field<O>(host.projection(), "actors")), "P"));
        const auto narrow = host.actor_projection("P");
        check(accepted(narrow) && field<bool>(narrow, "ready") == field<bool>(actor, "ready") &&
              field<I>(narrow, "native_epoch") == field<I>(actor, "native_epoch") &&
              !factory::values::typed_difference(V(field<A>(narrow, "position")),
                                                  V(field<A>(actor, "position"))),
              "The narrow actor view matches the accepted full projection exactly.");
        check(std::get<double>(field<A>(actor, "position").at(0).storage()) == static_cast<double>(coordinate),
              "The accepted boundary retains its exact numeric coordinate.");
    }
    check(accepted(host.invalidate_actor("P")) && !field<bool>(host.actor_projection("P"), "ready") &&
          field<I>(host.actor_projection("P"), "native_epoch") == epoch - 1,
          "Invalidation clears readiness without rewinding the published ordinal.");
}

void nonarrival_tick_schema() {
    Host host;
    check(accepted(host.initialize("plain-tick-schema", {"P"})) &&
          accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
          "The nonarrival Host starts with an ordinary finite world.");
    const auto full_before = std::get<O>(host.projection().storage());
    check(factory::godot_world::projection_contract::complete(V(full_before)),
          "The ordinary Host exports every stable typed projection field.");
    auto optional_arrival_record = full_before;
    optional_arrival_record.emplace("collector_assemblies", V(A{}));
    auto malformed_optional_arrival_record = optional_arrival_record;
    malformed_optional_arrival_record.at("collector_assemblies") = V(A{V(O{})});
    check(!full_before.contains("collector_assemblies") &&
          factory::godot_world::projection_contract::complete(V(optional_arrival_record)) &&
          !factory::godot_world::projection_contract::complete(
              V(malformed_optional_arrival_record)),
          "An ordinary world can omit arrival machines, but validates an arrival record if present.");
    auto missing_stock = full_before;
    missing_stock.erase("stock");
    auto wrong_cargo = full_before;
    wrong_cargo.at("cargo") = V(A{});
    check(!factory::godot_world::projection_contract::complete(V(missing_stock)) &&
          !factory::godot_world::projection_contract::complete(V(wrong_cargo)),
          "Missing stock or mistyped cargo cannot be admitted as a complete native view.");
    auto missing_source = full_before;
    auto stock = std::get<O>(missing_source.at("stock").storage());
    stock.erase("source");
    missing_source.at("stock") = V(std::move(stock));
    auto wrong_work_lots = full_before;
    auto cargo = std::get<O>(wrong_work_lots.at("cargo").storage());
    auto carried = std::get<O>(cargo.at("P").storage());
    carried.at("work_lots") = V(O{});
    cargo.at("P") = V(std::move(carried));
    wrong_work_lots.at("cargo") = V(std::move(cargo));
    auto missing_ready = full_before;
    auto actors = std::get<O>(missing_ready.at("actors").storage());
    auto actor = std::get<O>(actors.at("P").storage());
    actor.erase("ready");
    actors.at("P") = V(std::move(actor));
    missing_ready.at("actors") = V(std::move(actors));
    auto wrong_drop_center = full_before;
    wrong_drop_center.at("dropped_material") = V(A{V(O{
        {"center", V(A{V(I{0}), V(I{0})})}, {"raw", V(I{0})},
        {"products", V(I{1})}, {"work_lots", V(A{})}})});
    check(!factory::godot_world::projection_contract::complete(V(missing_source)) &&
          !factory::godot_world::projection_contract::complete(V(wrong_work_lots)) &&
          !factory::godot_world::projection_contract::complete(V(missing_ready)) &&
          !factory::godot_world::projection_contract::complete(V(wrong_drop_center)),
          "Nested stock, carried work, actor readiness and three-coordinate drop shapes are required.");
    const auto invalid_map_record = [&](const char* name, O fields) {
        auto malformed = full_before;
        malformed.at(name) = V(O{{"broken-record", V(std::move(fields))}});
        return !factory::godot_world::projection_contract::complete(V(malformed));
    };
    auto malformed_engagement = full_before;
    malformed_engagement.at("engagements") = V(A{V(O{{"a", V("one")}, {"b", V("two")},
        {"kind", V(true)}})});
    check(invalid_map_record("entities", O{{"kind", V("processor")}, {"generation", V(I{1})},
              {"center", V(A{V(I{0}), V(I{1})})}, {"axis", V(I{0})},
              {"relay_axis", V(I{0})}, {"teeth", V(I{0})}, {"half_span", V(I{0})},
              {"rotation", V(I{0})}, {"cell", V(A{V(I{0}), V(I{0})})}}) &&
          invalid_map_record("transmission_parts", O{{"kind", V("shaft")}}) &&
          invalid_map_record("belt_spans", O{{"generation", V(I{1})}, {"order", V(I{0})},
              {"from", V("one")}, {"to", V("two")}, {"phase", V(I{0})},
              {"slots", V(O{})}}) &&
          invalid_map_record("motion", O{{"state", V("turning")}, {"numerator", V("one")},
              {"denominator", V(I{1})}}) &&
          invalid_map_record("foundations", O{{"cell", V(A{V(I{0})})},
              {"level", V(I{0})}, {"generation", V(I{1})}}) &&
          !factory::godot_world::projection_contract::complete(V(malformed_engagement)),
          "Malformed topology coordinates, belt cargo, motion, foundations and engagement kinds refuse.");
    const auto invalid_object_field = [&](const char* record, const char* field, V bad) {
        auto malformed = full_before;
        auto fields = std::get<O>(malformed.at(record).storage());
        fields.at(field) = std::move(bad);
        malformed.at(record) = V(std::move(fields));
        return !factory::godot_world::projection_contract::complete(V(malformed));
    };
    auto malformed_links = full_before;
    malformed_links.at("links") = V(A{V(A{V("first"), V(I{2})})});
    auto malformed_drive_links = full_before;
    malformed_drive_links.at("drive_links") = V(A{V(A{V("only-one")})});
    check(!factory::godot_world::projection_contract::complete(V(malformed_links)) &&
          !factory::godot_world::projection_contract::complete(V(malformed_drive_links)) &&
          invalid_object_field("source_deposit", "cells", V(A{V(A{V(I{0}), V("wrong")})})) &&
          invalid_object_field("adapter_profile", "pitch", V(I{1})) &&
          invalid_object_field("adapter_profile", "collector_intake_size", V(A{V(0.28), V(0.20)})) &&
          invalid_object_field("options", "native", V("true")),
          "Links, deposit cells, adapter geometry and options need complete typed native fields.");
    const auto invalid_lift = [&](const char* field, std::optional<V> replacement) {
        auto malformed = full_before;
        auto profile = std::get<O>(malformed.at("adapter_profile").storage());
        auto lift = std::get<O>(profile.at("collector_lift").storage());
        if (replacement) lift.at(field) = std::move(*replacement);
        else lift.erase(field);
        profile.at("collector_lift") = V(std::move(lift));
        malformed.at("adapter_profile") = V(std::move(profile));
        return !factory::godot_world::projection_contract::complete(V(malformed));
    };
    check(invalid_lift("pickup_size", V(A{V(0.34), V(0.30)})) &&
          invalid_lift("carrier_size_xz", V(A{V(0.34), V(0.42), V(0.50)})) &&
          invalid_lift("flight_count", V(5.0)) &&
          invalid_lift("head_z_size", std::nullopt),
          "Every collector lift dimension and count follows the nested native projection schema.");
    const auto fields = std::get<O>(host.advance_tick_fields().storage());
    const auto full_after = std::get<O>(host.projection().storage());
    check(!full_before.contains("slide_phases") && !fields.contains("slide_phases") &&
          !full_after.contains("slide_phases"),
          "A nonarrival tick cannot introduce an arrival-only slide phase field.");
    check(factory::godot_world::projection_contract::complete(V(full_after)),
          "A nonarrival tick retains the complete stable projection schema.");
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 1 || (argc == 2 && std::string(argv[1]) == "--wire")) historical_translation();
        if (argc == 1 || (argc == 2 && std::string(argv[1]) == "--point")) exact_observation_conversion();
        if (argc == 1) nonarrival_tick_schema();
        if (argc > 2 || (argc == 2 && std::string(argv[1]) != "--wire" && std::string(argv[1]) != "--point"))
            throw std::runtime_error("Unknown Host regression selection.");
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_host_source_regressions\",\"checks\":" << checks
                  << ",\"engine_calls\":0,\"physical_producers\":0}" << std::endl;
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}
