#include "factory/checkpoint.hpp"

#include <algorithm>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <utility>

namespace {
namespace w = factory::world;
namespace a = factory::authority;
namespace s = factory::stationary;
namespace m = factory::materials;
namespace g = factory::mechanics;
using V = factory::values::Value;
using O = V::Object;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

const V& at(const V& value, const std::vector<std::string>& path) {
    const V* current = &value;
    for (const auto& key : path) current = &std::get<O>(current->storage()).at(key);
    return *current;
}

V edited(const V& value, const std::vector<std::string>& path,
         std::optional<V> replacement, std::size_t index = 0) {
    auto object = std::get<O>(value.storage());
    if (index + 1 == path.size()) {
        if (replacement) object.insert_or_assign(path[index], std::move(*replacement));
        else object.erase(path[index]);
    } else object.at(path[index]) = edited(object.at(path[index]), path, std::move(replacement), index + 1);
    return V(std::move(object));
}

// The deep negative control exceeds the production input budget deliberately.
bool equal(const V& left, const V& right) { return !factory::values::typed_difference(left, right, 64); }

template<class T> const T& field(const O& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

struct Fixture { w::Profile profile; std::unique_ptr<w::World> world; V checkpoint; };

O command(const char* action, const char* request, const char* target = "press", const char* actor = "P") {
    return {{"context", V("saved-world")}, {"client", V(std::string(actor) + "-old")},
        {"request", V(request)}, {"actor", V(actor)}, {"action", V(action)},
        {"target", V(target)}, {"generation", V(I{1})}};
}

w::Delivery send(w::World& world, const O& intent) {
    const auto& actor = field<std::string>(intent, "actor");
    return world.command({actor, field<std::string>(intent, "client")}, intent,
        [](const std::string& actor) -> std::optional<a::ActorCut> {
            return a::ActorCut{actor, {}, 10, true, 4};
        });
}

void accepted(const w::Delivery& result) {
    check(result.completed() && field<bool>(*result.result, "accepted"), "The literal command must succeed.");
}

Fixture fixture() {
    w::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 16;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.1;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::shaft, 0, 2}, 1},
        {{s::Role::processor, 0, 0}, 1}};
    w::State state;
    state.material.initial_units = 16;
    state.material.stock = {12, 0, 0, 1, 1};
    state.material.processing = m::WorkLot{1, {1, 2}, 1};
    state.material.next_work_id = 2;
    state.material.cargo = {{"P", {1, 0, {}}}, {"Q", {}}};
    state.kits = {{"P", {}}, {"Q", {}}};
    state.topology.parts = {
        {{"wheel", g::Kind::hub, {0, 0, 0}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
        {{"shaft", g::Kind::shaft, {0, 0, 4}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
        {{"press", g::Kind::hub, {0, 0, 8}, g::Axis::z, 0, 0}, 1, s::Role::processor}};
    state.topology.sources = {{"wheel", {1, 1}}};
    state.topology.drive_enabled = true;
    state.issued_entities = {{"wheel", 1}, {"shaft", 1}, {"press", 1}};
    for (const auto role : {s::Role::waterwheel, s::Role::processor}) {
        auto invalid = state;
        for (auto& part : invalid.topology.parts)
            if (part.role == role) part.geometry.center[1] = 1;
        check(w::World::create("saved-world", profile, invalid) == nullptr,
              "A fresh World rejects a machine or wheel between transmission tile heights.");
    }
    auto world = w::World::create("saved-world", profile, state);
    check(world != nullptr, "The literal sixteen-unit World initializes.");
    accepted(send(*world, command("recover", "recover")));
    accepted(send(*world, command("remove", "remove")));
    O place{{"context", V("saved-world")}, {"client", V("P-old")}, {"request", V("place")},
        {"actor", V("P")}, {"action", V("place")}, {"role", V("processor")},
        {"center", V(V::Array{V(I{0}), V(I{0}), V(I{8})})}, {"axis", V("z")},
        {"teeth", V(I{0})}, {"half_span", V(I{0})}};
    accepted(send(*world, place));
    auto insert = command("insert_work", "insert", "native-part-1");
    insert.emplace("work_id", V(I{1}));
    accepted(send(*world, insert));
    auto refusal = command("remove", "far-refusal", "native-part-1", "Q");
    const auto refused = world->command({"Q", "Q-old"}, refusal,
        [](const std::string& actor) -> std::optional<a::ActorCut> {
            return a::ActorCut{actor, {0, 20, 0}, 11, true, 4};
        });
    check(refused.completed() && !field<bool>(*refused.result, "accepted"), "The saved cache includes an original reach refusal.");
    const auto snapshot = world->snapshot();
    check(snapshot.revision == 4 && snapshot.history.order == 5 &&
          snapshot.state.material.stock == m::Stock{12, 0, 0, 0, 0} &&
          snapshot.state.material.cargo.at("P") == m::Cargo{2, 1, {}} &&
          snapshot.state.material.processing == m::WorkLot{1, {1, 2}, 1},
          "The checkpoint literal preserves sixteen units, partial work and five historical requests.");
    const auto encoded = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(encoded), "The validated complete snapshot encodes.");
    return {std::move(profile), std::move(world), std::get<V>(encoded)};
}

void refusal(const w::Profile& profile, const V& invalid, w::CheckpointReason expected) {
    const auto original = invalid;
    const auto decoded = w::decode_checkpoint(profile, "saved-world", invalid);
    check(std::holds_alternative<w::CheckpointRefusal>(decoded), "Malformed input must not produce a partial snapshot.");
    check(std::get<w::CheckpointRefusal>(decoded).reason == expected, "The refusal category must match the changed boundary.");
    check(equal(original, invalid), "Decoding never changes the input checkpoint.");
}

void round_trip_restore_and_continue() {
    auto f = fixture();
    const auto before = f.world->snapshot();
    const auto decoded = w::decode_checkpoint(f.profile, "saved-world", f.checkpoint);
    check(std::holds_alternative<w::Snapshot>(decoded), "The original typed checkpoint decodes.");
    const auto& saved = std::get<w::Snapshot>(decoded);
    check(saved.state == before.state && saved.revision == 4 && saved.history.order == 5,
          "Typed decode preserves canonical custody, identities, part kits and counters.");
    for (const auto role : {s::Role::waterwheel, s::Role::processor}) {
        auto invalid = saved;
        for (auto& part : invalid.state.topology.parts)
            if (part.role == role) part.geometry.center[1] = 1;
        check(w::World::restore("saved-world", f.profile, invalid) == nullptr,
              "Restoration rejects a machine or wheel between transmission tile heights.");
        check(std::holds_alternative<w::CheckpointRefusal>(w::encode_checkpoint(f.profile, invalid)),
              "An invalid off-grid machine or wheel cannot be encoded as a valid checkpoint.");
    }
    const auto reencoded = w::encode_checkpoint(f.profile, saved);
    check(std::holds_alternative<V>(reencoded) && equal(f.checkpoint, std::get<V>(reencoded)),
          "All original request intents, outcomes and typed checkpoint values survive exactly.");
    auto restored = w::World::restore("saved-world", f.profile, saved);
    check(restored != nullptr && restored->snapshot().history.order == 5, "Explicit restore retains history rather than starting a new World.");
    int observations = 0;
    const auto retry = restored->command({"P", "P-old"}, command("recover", "recover"),
        [&](const std::string&) -> std::optional<a::ActorCut> { ++observations; throw std::runtime_error("must not observe retry"); });
    check(retry.completed() && field<bool>(*retry.result, "duplicate") && observations == 0,
          "A restored retry uses its old receipt before current native admission.");
    check(field<I>(*retry.result, "revision") == 1 && retry.current_revision == 4 &&
          field<I>(*retry.result, "moved_raw") == 1 && field<I>(*retry.result, "moved_products") == 1,
          "Removed-target recovery facts retain their original revision and quantities.");
    const auto refused = restored->command({"Q", "Q-old"}, command("remove", "far-refusal", "native-part-1", "Q"), {});
    check(refused.completed() && !field<bool>(*refused.result, "accepted") && field<bool>(*refused.result, "duplicate"),
          "An original reach refusal survives restoration without being retargeted to a new pose.");
    const auto tick = restored->tick();
    check(tick.error == w::TransactionError::none && tick.changed && tick.current_revision == 5,
          "The original partial lot continues in the restored geometrically powered machine.");
    auto collect = command("collect", "new-product", "native-part-1", "Q");
    collect.at("client") = V("Q-fresh"); collect.emplace("amount", V(I{1}));
    accepted(send(*restored, collect));
    const auto final = restored->snapshot();
    check(final.revision == 6 && final.history.order == 6 && final.state.material.stock.source == 12 &&
          final.state.material.stock.output == 0 && !final.state.material.processing &&
          final.state.material.cargo.at("P") == m::Cargo{2, 1, {}} && final.state.material.cargo.at("Q").products == 1,
          "The original work completes once and a fresh namespace collects its own product with exact finite custody.");
    check(f.world->snapshot().state == before.state, "The restored owner shares no mutable state with the original owner.");
    check(equal(f.checkpoint, std::get<V>(reencoded)), "Continuing another owner preserves the original checkpoint value.");
}

void schema_and_authority_mutations() {
    auto f = fixture();
    refusal(f.profile, edited(f.checkpoint, {"schema"}, V(1.0)), w::CheckpointReason::wrong_type);
    refusal(f.profile, edited(f.checkpoint, {"schema"}, V(I{99})), w::CheckpointReason::unsupported_schema);
    refusal(f.profile, edited(f.checkpoint, {"state"}, std::nullopt), w::CheckpointReason::missing_field);
    refusal(f.profile, edited(f.checkpoint, {"unexpected"}, V(nullptr)), w::CheckpointReason::unexpected_field);
    refusal(f.profile, edited(f.checkpoint, {"revision"}, V(true)), w::CheckpointReason::wrong_type);
    refusal(f.profile, edited(f.checkpoint, {"revision"}, V(I{0})), w::CheckpointReason::invalid_history);
    refusal(f.profile, edited(f.checkpoint, {"profile", "recipe_weight"}, V(1.0)), w::CheckpointReason::profile_mismatch);
    refusal(f.profile, edited(f.checkpoint, {"profile", "build_reach"}, V(40.0)), w::CheckpointReason::profile_mismatch);
    refusal(f.profile, edited(f.checkpoint, {"history", "context"}, V("other-world")), w::CheckpointReason::invalid_history);
    check(std::get<w::CheckpointRefusal>(w::decode_checkpoint(f.profile, "other-world", f.checkpoint)).reason ==
          w::CheckpointReason::wrong_context, "A valid checkpoint cannot replace another expected context.");
    refusal(f.profile, edited(f.checkpoint, {"state", "material", "stock", "source"}, V(12.0)), w::CheckpointReason::invalid_material);
    refusal(f.profile, edited(f.checkpoint, {"state", "material", "stock", "source"}, V(I{13})), w::CheckpointReason::invalid_material);
    refusal(f.profile, edited(f.checkpoint, {"state", "material", "processing", "id"}, V(I{2})), w::CheckpointReason::invalid_material);
    refusal(f.profile, edited(f.checkpoint, {"state", "kits", "Q"}, std::nullopt), w::CheckpointReason::invalid_world);
    refusal(f.profile, edited(f.checkpoint, {"state", "issued_entities", "press"}, std::nullopt), w::CheckpointReason::invalid_world);
    refusal(f.profile, edited(f.checkpoint, {"state", "issued_entities", "native-part-1"}, V(I{2})), w::CheckpointReason::invalid_world);
    refusal(f.profile, edited(f.checkpoint, {"state", "next_entity_serial"}, V(I{1})), w::CheckpointReason::invalid_world);
    refusal(f.profile, edited(f.checkpoint, {"state", "topology", "drive_enabled"}, V(I{1})), w::CheckpointReason::wrong_type);
    refusal(f.profile, edited(f.checkpoint, {"state", "extra"}, V(I{0})), w::CheckpointReason::unexpected_field);

    auto records = std::get<V::Array>(at(f.checkpoint, {"history", "records"}).storage());
    records[0] = edited(records[0], {"result", "generation"}, V(1.0));
    refusal(f.profile, edited(f.checkpoint, {"history", "records"}, V(records)), w::CheckpointReason::invalid_world);
    records = std::get<V::Array>(at(f.checkpoint, {"history", "records"}).storage());
    records[0] = edited(records[0], {"result", "moved_raw"}, V(1.0));
    refusal(f.profile, edited(f.checkpoint, {"history", "records"}, V(records)), w::CheckpointReason::invalid_world);
    records = std::get<V::Array>(at(f.checkpoint, {"history", "records"}).storage());
    records[0] = edited(records[0], {"result", "distances_squared"}, V(V::Array{V(100.0)}));
    refusal(f.profile, edited(f.checkpoint, {"history", "records"}, V(records)), w::CheckpointReason::invalid_world);
    records = std::get<V::Array>(at(f.checkpoint, {"history", "records"}).storage());
    records[2] = edited(records[2], {"intent", "role"}, V(true));
    refusal(f.profile, edited(f.checkpoint, {"history", "records"}, V(records)), w::CheckpointReason::invalid_world);
    auto kits = std::get<V::Array>(at(f.checkpoint, {"state", "kits", "P"}).storage());
    kits.push_back(kits.front());
    refusal(f.profile, edited(f.checkpoint, {"state", "kits", "P"}, V(kits)), w::CheckpointReason::invalid_world);

    auto invalid = f.world->snapshot();
    ++invalid.state.material.stock.source;
    check(!w::World::restore("saved-world", f.profile, invalid), "Invalid state cannot fall back to a fresh owner.");
    check(!w::World::restore("wrong-world", f.profile, f.world->snapshot()), "Native restore also checks the expected context.");
    check(std::holds_alternative<w::CheckpointRefusal>(w::encode_checkpoint(f.profile, invalid)),
          "Export refuses a nonconserving snapshot.");
}

void bounds_and_large_integers() {
    auto f = fixture();
    auto large = f.world->snapshot();
    large.revision = 9007199254740993LL;
    large.state.material.next_work_id = std::numeric_limits<I>::max();
    auto encoded = w::encode_checkpoint(f.profile, large);
    check(std::holds_alternative<V>(encoded), "Large native integer ordinals encode without a float boundary.");
    const auto decoded = w::decode_checkpoint(f.profile, "saved-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).revision == large.revision &&
          std::get<w::Snapshot>(decoded).state.material.next_work_id == std::numeric_limits<I>::max(),
          "Exact integers above two-to-the-fifty-third and at the signed limit survive.");
    auto profile = f.profile; profile.meters_per_grid_unit = 0.2;
    refusal(profile, f.checkpoint, w::CheckpointReason::profile_mismatch);
    profile = f.profile; profile.build_reach = std::numeric_limits<double>::infinity();
    refusal(profile, f.checkpoint, w::CheckpointReason::profile_mismatch);
    V deep(nullptr);
    for (int index = 0; index < 34; ++index) deep = V(O{{"nested", std::move(deep)}});
    refusal(f.profile, edited(f.checkpoint, {"extra"}, std::move(deep)), w::CheckpointReason::limit);
    V::Array lots(257, V(nullptr));
    refusal(f.profile, edited(f.checkpoint, {"state", "material", "cargo", "P", "work_lots"}, V(lots)),
            w::CheckpointReason::limit);
    O issued;
    for (int index = 0; index < 4097; ++index) issued.emplace("old-" + std::to_string(index), V(I{1}));
    refusal(f.profile, edited(f.checkpoint, {"state", "issued_entities"}, V(issued)), w::CheckpointReason::limit);
}

void belt_span_checkpoint() {
    w::Profile profile;
    profile.material = {1, 1, 2}; profile.initial_units = 1; profile.actors = {"P"};
    profile.meters_per_grid_unit = 0.1;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::shaft, 0, 2}, 2},
                            {{s::Role::belt, 0, 0}, 1}};
    w::State state;
    state.material.initial_units = 1; state.material.stock.source = 0;
    state.material.belt_lanes.emplace("belt", m::BeltLane{{std::nullopt, std::nullopt, m::Cargo{1, 0, {}}}, -123});
    state.material.cargo = {{"P", {}}}; state.kits = {{"P", {}}};
    state.topology.parts = {{{"wheel", g::Kind::hub, {0, 0, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
        {{"left", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
        {{"right", g::Kind::shaft, {8, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft}};
    state.topology.sources = {{"wheel", {1, 1}}}; state.topology.drive_enabled = true;
    state.topology.belt_spans = {{{"belt", "left", "right"}, 1}};
    state.issued_entities = {{"wheel", 1}, {"left", 1}, {"right", 1}, {"belt", 1}};
    auto world = w::World::create("saved-world", profile, state);
    check(world != nullptr, "A seeded world accepts a finite, identified belt span.");
    const auto encoded = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(encoded), "The world exports the span in the typed checkpoint.");
    const auto decoded = w::decode_checkpoint(profile, "saved-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded) && std::get<w::Snapshot>(decoded).state == state,
          "Belt identity, endpoints and finite custody survive exact decoding.");
    auto restored = w::World::restore("saved-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && s::power_view(restored->snapshot().state.topology).mechanical.motion.at("right").rate == g::Rate{1, 1},
          "A fresh World derives the same driven shaft from the restored belt.");
    auto removal = command("remove_belt_span", "occupied-belt", "belt");
    const auto occupied = send(*restored, removal);
    check(occupied.completed() && !field<bool>(*occupied.result, "accepted") &&
          field<std::string>(*occupied.result, "reason") == "occupied_target" &&
          restored->snapshot().state.material.belt_lanes.at("belt") == state.material.belt_lanes.at("belt"),
          "An occupied restored span cannot be removed or lose its item.");
    for (const bool work : {false, true}) {
        auto carried_state = state;
        carried_state.material.belt_lanes.at("belt").slots[2] = work ? m::Cargo{0, 0, {{1, {1, 2}, 1, 123}}} : m::Cargo{0, 1, {}};
        carried_state.material.next_work_id = work ? 2 : 1;
        auto carried_world = w::World::create("saved-world", profile, carried_state);
        check(carried_world != nullptr, "A belt slot can own a product or whole partial workpiece.");
        auto recover = command("recover_belt_slot", work ? "recover-work" : "recover-product", "belt");
        recover.emplace("slot", V(I{2}));
        V::Array lots;
        if (work) lots.emplace_back(O{{"id", V(I{1})}, {"recipe_input", V(I{1})}, {"cycle_ticks", V(I{2})},
                                      {"remaining", V(I{1})}, {"completed_subticks", V(I{123})}});
        recover.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{work ? 0 : 1})}, {"work_lots", V(lots)}}));
        accepted(send(*carried_world, recover));
        check(carried_world->snapshot().state.material.cargo.at("P") == *carried_state.material.belt_lanes.at("belt").slots[2],
              "Recovery retains the exact product or partial workpiece in actor custody.");
        accepted(send(*carried_world, command("remove_belt_span", work ? "remove-work" : "remove-product", "belt")));
        const auto saved = w::encode_checkpoint(profile, carried_world->snapshot());
        check(std::holds_alternative<V>(saved) && std::holds_alternative<w::Snapshot>(w::decode_checkpoint(profile, "saved-world", std::get<V>(saved))),
              "Recovered product and partial-work histories survive span removal and checkpoint validation.");
    }
    const auto moving = restored->tick();
    check(moving.error == w::TransactionError::none && moving.changed &&
          restored->snapshot().state.material.belt_lanes.at("belt").slots[1] == m::Cargo{1, 0, {}} &&
          restored->snapshot().state.material.belt_lanes.at("belt").phase == -123,
          "Restored shaft power moves the original item toward the correct end with retained fractional phase.");
    auto spans = std::get<V::Array>(at(std::get<V>(encoded), {"state", "topology", "belt_spans"}).storage());
    spans[0] = edited(spans[0], {"last_shaft"}, V("missing"));
    refusal(profile, edited(std::get<V>(encoded), {"state", "topology", "belt_spans"}, V(spans)),
            w::CheckpointReason::invalid_world);
    refusal(profile, edited(std::get<V>(encoded), {"schema"}, V(I{3})), w::CheckpointReason::unsupported_schema);
    auto malformed = state; malformed.topology.belt_spans[0].geometry.last_shaft = "missing";
    check(!w::World::create("saved-world", profile, malformed), "A dangling saved belt endpoint is refused.");
    malformed = state; malformed.kits.at("P")[{s::Role::belt, 0, 0}] = 1;
    check(!w::World::create("saved-world", profile, malformed), "A belt cannot be both placed and carried.");
    malformed = state; malformed.material.belt_lanes.at("belt").slots.pop_back();
    check(!w::World::create("saved-world", profile, malformed), "Lane length must match its span geometry.");
    malformed = state; malformed.material.belt_lanes.emplace("orphan", m::BeltLane{{std::nullopt, std::nullopt}, 0});
    check(!w::World::create("saved-world", profile, malformed), "An orphan lane cannot own material.");
    malformed = state; malformed.topology.parts[1].geometry.center[0] = std::numeric_limits<I>::min();
    check(!w::World::create("saved-world", profile, malformed), "Out-of-bounds span endpoints refuse before distance arithmetic.");
    auto paused_state = state;
    paused_state.topology.drive_enabled = false;
    auto paused_world = w::World::create("paused-world", profile, paused_state);
    check(paused_world != nullptr, "An unpowered span with retained cargo is valid.");
    const auto paused = paused_world->tick();
    check(paused.error == w::TransactionError::none && !paused.changed && paused_world->snapshot().state == paused_state,
          "A stopped shaft cannot move cargo or its phase.");
    auto reverse_profile = profile;
    reverse_profile.waterwheel_rate = {-1, 1};
    auto reverse_state = state;
    reverse_state.topology.sources[0].rate = {-1, 1};
    reverse_state.material.belt_lanes.at("belt") = {{std::nullopt, m::Cargo{1, 0, {}}, std::nullopt}, 0};
    auto reverse_world = w::World::create("reverse-world", reverse_profile, reverse_state);
    check(reverse_world != nullptr, "The reversed source admits the same conserved span.");
    const auto reversing = reverse_world->tick();
    check(reversing.error == w::TransactionError::none && reversing.changed &&
          reverse_world->snapshot().state.material.belt_lanes.at("belt").slots[2] == m::Cargo{1, 0, {}},
          "Reversing the shaft reverses lane travel.");
}

void adjacent_belt_handoff() {
    for (const bool reversed : {false, true}) for (const bool reverse_order : {false, true})
    for (const bool toward_negative : {false, true}) {
        for (int kind = 0; kind < 3; ++kind) {
            w::Profile profile;
            profile.material = {1, 1, 2}; profile.initial_units = 1; profile.actors = {"P"};
            profile.meters_per_grid_unit = 0.1; profile.waterwheel_rate = {toward_negative ? 1 : -1, 1};
            profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 2},
                {{s::Role::shaft, 0, 2}, 4}, {{s::Role::belt, 0, 0}, 2}};
            w::State state;
            state.material.initial_units = 1; state.material.cargo = {{"P", {}}}; state.kits = {{"P", {}}};
            const m::Cargo cargo = kind == 0 ? m::Cargo{1, 0, {}} : kind == 1 ? m::Cargo{0, 1, {}} :
                m::Cargo{0, 0, {{1, {1, 2}, 1, 123}}};
            if (kind == 2) state.material.next_work_id = 2;
            state.topology.parts = {
                {{"wheel-a", g::Kind::hub, {0, 0, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
                {{"a0", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
                {{"a1", g::Kind::shaft, {4, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
                {{"wheel-b", g::Kind::hub, {8, 0, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
                {{"b0", g::Kind::shaft, {8, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
                {{"b1", g::Kind::shaft, {12, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft}};
            if (toward_negative) for (auto& part : state.topology.parts) part.geometry.center[0] *= -1;
            state.topology.sources = {{"wheel-a", profile.waterwheel_rate}, {"wheel-b", profile.waterwheel_rate}};
            state.topology.drive_enabled = true;
            state.topology.belt_spans = {{{"span-a", reversed ? "a1" : "a0", reversed ? "a0" : "a1"}, 1},
                                         {{"span-b", reversed ? "b1" : "b0", reversed ? "b0" : "b1"}, 1}};
            if (reverse_order) std::reverse(state.topology.belt_spans.begin(), state.topology.belt_spans.end());
            state.material.belt_lanes.emplace("span-a", m::BeltLane{{std::nullopt, std::nullopt}, 0});
            state.material.belt_lanes.emplace("span-b", m::BeltLane{{std::nullopt, std::nullopt}, 0});
            state.material.belt_lanes.at("span-a").slots[reversed ? 0 : 1] = cargo;
            for (const auto& part : state.topology.parts) state.issued_entities.emplace(part.geometry.id, 1);
            state.issued_entities.emplace("span-a", 1); state.issued_entities.emplace("span-b", 1);
            const m::DropPoint handoff{toward_negative ? -8 : 8, 0, 0};
            const m::DropPoint exit{toward_negative ? -16 : 16, 0, 0};
            auto world = w::World::create("handoff", profile, state);
            check(world != nullptr, "Adjacent powered belts admit conserved typed cargo.");
            check(world->tick().error == w::TransactionError::none &&
                  world->snapshot().state.material.dropped_material.at(handoff) == cargo,
                  "The first belt deposits its exact cargo on the next belt tile.");
            if (kind == 0 && !reversed && !reverse_order && !toward_negative) {
                auto stopped_state = world->snapshot().state;
                stopped_state.topology.drive_enabled = false;
                auto stopped = w::World::create("stopped-handoff", profile, stopped_state);
                check(stopped && stopped->tick().error == w::TransactionError::none &&
                          stopped->snapshot().state.material == stopped_state.material,
                      "A stopped receiving belt does not collect loose cargo.");
                auto blocked_profile = profile; blocked_profile.initial_units = 2;
                auto blocked_state = world->snapshot().state;
                blocked_state.material.initial_units = 2;
                blocked_state.material.belt_lanes.at("span-b").slots[0] = m::Cargo{1, 0, {}};
                auto blocked = w::World::create("blocked-handoff", blocked_profile, blocked_state);
                check(blocked && blocked->tick().error == w::TransactionError::none &&
                          blocked->snapshot().state.material.dropped_material.at(handoff) == cargo,
                      "An occupied receiving tile leaves the loose item in place.");
                check(blocked->tick().error == w::TransactionError::none &&
                          !blocked->snapshot().state.material.dropped_material.contains(handoff),
                      "The loose item is collected once the receiving tile becomes free.");
            }
            const auto encoded = w::encode_checkpoint(profile, world->snapshot());
            check(std::holds_alternative<V>(encoded), "The in-flight handoff encodes.");
            const auto decoded = w::decode_checkpoint(profile, "handoff", std::get<V>(encoded));
            check(std::holds_alternative<w::Snapshot>(decoded), "The in-flight handoff decodes.");
            auto loaded = w::World::restore("handoff", profile, std::get<w::Snapshot>(decoded));
            check(loaded && loaded->tick().error == w::TransactionError::none && world->tick().error == w::TransactionError::none &&
                  loaded->snapshot().state.material == world->snapshot().state.material &&
                  !world->snapshot().state.material.dropped_material.contains(handoff) &&
                  world->snapshot().state.material.belt_lanes.at("span-b").slots[reversed ? 0 : 1] == cargo,
                  "Both original and restored worlds capture and carry the exact item on the second belt.");
            check(world->tick().error == w::TransactionError::none &&
                  world->snapshot().state.material.dropped_material.at(exit) == cargo,
                  "The downstream open end retains the same raw, product or partial-work item.");
        }
    }
}

void inclined_material_route() {
    for (const bool reverse_endpoints : {false, true}) {
        w::Profile profile;
        profile.material = {1, 1, 2}; profile.initial_units = 3; profile.actors = {"P"};
        profile.meters_per_grid_unit = 0.1;
        profile.waterwheel_rate = {-1, 1};
        profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 2}, {{s::Role::collector, 0, 0}, 1},
            {{s::Role::processor, 0, 0}, 1}, {{s::Role::shaft, 0, 2}, 2}, {{s::Role::belt, 0, 0}, 1}};
        w::State state;
        state.material.initial_units = 3; state.material.stock.source = 3;
        state.material.cargo = {{"P", {}}}; state.kits = {{"P", {}}};
        state.topology.parts = {
            {{"collector-wheel", g::Kind::hub, {-4, 0, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
            {{"collector", g::Kind::hub, {-4, 0, 0}, g::Axis::z, 0, 0}, 1, s::Role::collector},
            {{"belt-wheel", g::Kind::hub, {0, 4, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
            {{"low", g::Kind::shaft, {0, 4, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
            {{"high", g::Kind::shaft, {8, 12, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
            {{"processor", g::Kind::hub, {12, 16, 0}, g::Axis::z, 0, 0}, 1, s::Role::processor}};
        state.topology.sources = {{"collector-wheel", {-1, 1}}, {"belt-wheel", {-1, 1}}};
        state.topology.drive_enabled = true;
        state.topology.belt_spans = {{{"span", reverse_endpoints ? "high" : "low", reverse_endpoints ? "low" : "high"}, 1}};
        state.material.belt_lanes.emplace("span", m::BeltLane{{std::nullopt, std::nullopt, std::nullopt}, 0});
        for (const auto& part : state.topology.parts) state.issued_entities.emplace(part.geometry.id, 1);
        state.issued_entities.emplace("span", 1);
        auto open_state = state;
        std::erase_if(open_state.topology.parts, [](const auto& part) { return part.role == s::Role::processor; });
        open_state.kits.at("P")[{s::Role::processor, 0, 0}] = 1;
        auto open_world = w::World::create("inclined-open", profile, open_state);
        check(open_world != nullptr, "An open inclined route conserves its unplaced processor.");
        for (int i = 0; i < 8; ++i)
            check(open_world->tick().error == w::TransactionError::none, "The open inclined route advances.");
        const auto open_snapshot = open_world->snapshot();
        const m::DropPoint exit{12, 16, 0};
        check(open_snapshot.state.material.dropped_material.contains(exit), "An inclined belt ejects a blank at its elevated open end.");
        const auto open_encoded = w::encode_checkpoint(profile, open_snapshot);
        check(std::holds_alternative<V>(open_encoded), "The ejected inclined blank encodes.");
        const auto open_decoded = w::decode_checkpoint(profile, "inclined-open", std::get<V>(open_encoded));
        check(std::holds_alternative<w::Snapshot>(open_decoded), "The ejected inclined blank decodes.");
        auto open_restored = w::World::restore("inclined-open", profile, std::get<w::Snapshot>(open_decoded));
        check(open_restored && open_restored->snapshot().state.material.dropped_material == open_snapshot.state.material.dropped_material,
              "A fresh World retains the ejected inclined blank.");
        for (const bool workpiece : {false, true}) {
            auto typed_state = open_state;
            typed_state.material.stock.source = 2;
            const m::Cargo item = workpiece ? m::Cargo{0, 0, {{1, {1, 2}, 1, 0}}} : m::Cargo{0, 1, {}};
            if (workpiece) typed_state.material.next_work_id = 2;
            auto& slots = typed_state.material.belt_lanes.at("span").slots;
            (reverse_endpoints ? slots.front() : slots.back()) = item;
            auto typed = w::World::create("typed-incline", profile, typed_state);
            check(typed && typed->tick().error == w::TransactionError::none, "A typed item starts along the powered inclined belt.");
            const auto partial = typed->snapshot();
            const auto expected_phase = reverse_endpoints ? -2896 : 2896;
            check(partial.state.material.belt_lanes.at("span").phase == expected_phase &&
                      !partial.state.material.dropped_material.contains(exit),
                  "One tick advances the same physical surface distance as a horizontal belt without premature delivery.");
            check(typed->tick().error == w::TransactionError::none, "A second tick carries the item off the inclined belt.");
            const auto after = typed->snapshot();
            check(after.state.material.dropped_material.at(exit) == item, "The open end retains the exact typed item and work identity.");
            const auto encoded = w::encode_checkpoint(profile, after);
            check(std::holds_alternative<V>(encoded), "Loose typed cargo encodes.");
            const auto decoded = w::decode_checkpoint(profile, "typed-incline", std::get<V>(encoded));
            check(std::holds_alternative<w::Snapshot>(decoded), "Loose typed cargo decodes.");
            auto loaded = w::World::restore("typed-incline", profile, std::get<w::Snapshot>(decoded));
            check(loaded != nullptr, "Loose typed cargo restores in a fresh World.");
            O pickup{{"context", V("typed-incline")}, {"client", V("P-old")}, {"request", V("pickup-typed")},
                {"actor", V("P")}, {"action", V("pickup_material")},
                {"center", V(V::Array{V(I{12}), V(I{16}), V(I{0})})}};
            V::Array expected_lots;
            if (workpiece) expected_lots.emplace_back(O{{"id", V(I{1})}, {"recipe_input", V(I{1})},
                {"cycle_ticks", V(I{2})}, {"remaining", V(I{1})}, {"completed_subticks", V(I{0})}});
            pickup.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(workpiece ? I{0} : I{1})},
                                          {"work_lots", V(std::move(expected_lots))}}));
            accepted(send(*loaded, pickup));
            check(loaded->snapshot().state.material.cargo.at("P") == item &&
                      !loaded->snapshot().state.material.dropped_material.contains(exit),
                  "Pickup preserves the exact plate or workpiece in actor custody.");
            auto reverse_profile = profile;
            reverse_profile.waterwheel_rate = {1, 1};
            auto reverse_state = typed_state;
            reverse_state.topology.sources = {{"collector-wheel", {1, 1}}, {"belt-wheel", {1, 1}}};
            auto& reverse_slots = reverse_state.material.belt_lanes.at("span").slots;
            for (auto& slot : reverse_slots) slot.reset();
            (reverse_endpoints ? reverse_slots.back() : reverse_slots.front()) = item;
            auto reverse = w::World::create("typed-reverse", reverse_profile, reverse_state);
            check(reverse && reverse->tick().error == w::TransactionError::none &&
                      reverse->snapshot().state.material.belt_lanes.at("span").phase == -expected_phase &&
                      reverse->tick().error == w::TransactionError::none &&
                      reverse->snapshot().state.material.dropped_material.at({-4, 0, 0}) == item,
                  "Reversing power ejects the same typed item at the lower end.");
        }
        if (!reverse_endpoints) {
            auto capacity_profile = profile;
            capacity_profile.initial_units = static_cast<I>(m::maximum_drop_points) + 1;
            auto capacity_state = open_state;
            capacity_state.material.initial_units = capacity_profile.initial_units;
            capacity_state.material.stock.source = 0;
            capacity_state.material.belt_lanes.at("span").slots.back() = m::Cargo{1, 0, {}};
            for (std::size_t i = 0; i < m::maximum_drop_points; ++i)
                capacity_state.material.dropped_material.emplace(m::DropPoint{100 + static_cast<I>(i) * 4, 0, 100}, m::Cargo{1, 0, {}});
            auto capacity_world = w::World::create("inclined-capacity", capacity_profile, capacity_state);
            check(capacity_world != nullptr && capacity_world->tick().error == w::TransactionError::none &&
                      capacity_world->snapshot().state.material.belt_lanes.at("span").slots.back().has_value(),
                  "A full loose-material store keeps the blank on the belt without losing custody.");
        }
        auto world = w::World::create("inclined-route", profile, state);
        check(world != nullptr && w::machine_power(world->snapshot().state.topology).collector,
              "A powered collector and independently driven inclined belt form a conserved route.");
        for (int i = 0; i < 2; ++i)
            check(world->tick().error == w::TransactionError::none, "The inclined collector route advances.");
        const auto in_flight = world->snapshot();
        const auto& lane = in_flight.state.material.belt_lanes.at("span");
        check(std::any_of(lane.slots.begin(), lane.slots.end(), [](const auto& item) { return item.has_value(); }),
              "A real collector deposits a blank into the inclined lane.");
        const auto checkpoint = w::encode_checkpoint(profile, world->snapshot());
        check(std::holds_alternative<V>(checkpoint), "The in-flight inclined route encodes.");
        const auto decoded = w::decode_checkpoint(profile, "inclined-route", std::get<V>(checkpoint));
        check(std::holds_alternative<w::Snapshot>(decoded), "The in-flight inclined route decodes.");
        auto restored = w::World::restore("inclined-route", profile, std::get<w::Snapshot>(decoded));
        check(restored != nullptr, "A fresh World restores the in-flight route.");
        for (int i = 0; i < 8; ++i) {
            check(world->tick().error == w::TransactionError::none && restored->tick().error == w::TransactionError::none &&
                      world->snapshot().state == restored->snapshot().state,
                  "Original and restored inclined routes retain identical custody.");
        }
        check(restored->snapshot().state.material.stock.input == 1,
              "The elevated processor receives a collector blank from either endpoint order.");
        const auto full = restored->snapshot().state.material;
        check(full.dropped_material.empty() && std::any_of(full.belt_lanes.at("span").slots.begin(),
                  full.belt_lanes.at("span").slots.end(), [](const auto& item) { return item.has_value(); }),
              "A full processor blocks the belt instead of ejecting its queued cargo.");
    }
}

void belt_span_material_route() {
    for (const bool rotated : {false, true}) for (const bool reverse : {false, true}) {
        for (const bool reverse_parts : {false, true}) {
            for (const bool gap : {false, true}) {
                w::Profile profile;
                profile.material = {1, 1, 2}; profile.initial_units = 3; profile.actors = {"P"};
                profile.meters_per_grid_unit = 0.1;
                const I rate = reverse ? -1 : 1;
                profile.waterwheel_rate = {rotated ? -rate : rate, 1};
                profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::collector, 0, 0}, 1},
                    {{s::Role::processor, 0, 0}, 1}, {{s::Role::shaft, 0, 2}, 2},
                    {{s::Role::gear, 2, 0}, 2}, {{s::Role::belt, 0, 0}, 1}};
                w::State state;
                state.material.initial_units = 3; state.material.stock.source = 3;
                state.material.cargo = {{"P", {}}}; state.kits = {{"P", {}}};
                state.topology.parts = {
                    {{"wheel", g::Kind::hub, {-4, 0, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
                    {{"collector", g::Kind::hub, {-4, 0, 0}, g::Axis::z, 0, 0}, 1, s::Role::collector},
                    {{"first-cog", g::Kind::gear, {-4, 0, 4}, g::Axis::z, 2, 0}, 1, s::Role::gear},
                    {{"second-cog", g::Kind::gear, {0, 0, 4}, g::Axis::z, 2, 0}, 1, s::Role::gear},
                    {{"left", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
                    {{"right", g::Kind::shaft, {8, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
                    {{"processor", g::Kind::hub, {gap ? 16 : 12, 0, 0}, g::Axis::z, 0, 0}, 1, s::Role::processor}};
                if (rotated) {
                    for (auto& part : state.topology.parts) {
                        std::swap(part.geometry.center[0], part.geometry.center[2]);
                        part.geometry.axis = g::Axis::x;
                    }
                }
                if (reverse_parts) std::reverse(state.topology.parts.begin(), state.topology.parts.end());
                state.topology.sources = {{"wheel", profile.waterwheel_rate}};
                state.topology.drive_enabled = true;
                state.topology.belt_spans = {{{"span", "left", "right"}, 1}};
                state.material.belt_lanes.emplace("span", m::BeltLane{{std::nullopt, std::nullopt, std::nullopt}, 0});
                for (const auto& part : state.topology.parts) state.issued_entities.emplace(part.geometry.id, 1);
                state.issued_entities.emplace("span", 1);
                if (reverse_parts) {
                    std::erase_if(state.topology.parts, [](const auto& part) {
                        return part.role == s::Role::collector || part.role == s::Role::processor;
                    });
                    state.kits.at("P")[{s::Role::collector, 0, 0}] = 1;
                    state.kits.at("P")[{s::Role::processor, 0, 0}] = 1;
                } else {
                    state.topology.belt_spans.clear();
                    state.material.belt_lanes.clear();
                    state.issued_entities.erase("span");
                    state.kits.at("P")[{s::Role::belt, 0, 0}] = 1;
                }
                auto world = w::World::create("route-world", profile, state);
                check(world != nullptr, "Either construction order starts with conserved finite parts.");
                if (reverse_parts) {
                    for (const auto& [role, x] : std::vector<std::pair<std::string, I>>{{"collector", -4}, {"processor", gap ? 16 : 12}}) {
                        O place{{"context", V("route-world")}, {"client", V("P-old")}, {"request", V("place-" + role)},
                            {"actor", V("P")}, {"action", V("place")}, {"role", V(role)},
                            {"center", V(V::Array{V(rotated ? I{0} : x), V(I{0}), V(rotated ? x : I{0})})},
                            {"axis", V(rotated ? "x" : "z")},
                            {"teeth", V(I{0})}, {"half_span", V(I{0})}};
                        accepted(send(*world, place));
                    }
                } else {
                    auto place = command("place_belt_span", "place-span", "left");
                    place.at("context") = V("route-world");
                    place.emplace("to", V("right")); place.emplace("to_generation", V(I{1}));
                    accepted(send(*world, place));
                }
                check(w::machine_power(world->snapshot().state.topology).collector,
                      "The finite route powers its collector through actual shaft and cog contacts.");
                for (int i = 0; i < 3; ++i) {
                    const auto tick = world->tick();
                    check(tick.error == w::TransactionError::none, "A span route advances without losing custody.");
                }
                if (!reverse && !gap) {
                    auto mixed = world->snapshot().state;
                    auto& lane = mixed.material.belt_lanes.begin()->second;
                    check(lane.slots.back().has_value(), "The collector reaches the outgoing end before its next delivery tick.");
                    lane.slots.back() = m::Cargo{0, 1, {}};
                    auto blocked = w::World::create("blocked-output", profile, mixed);
                    check(blocked != nullptr, "A finished product remains a valid distinct span item.");
                    const auto tick = blocked->tick();
                    check(tick.error == w::TransactionError::none && blocked->snapshot().state.material.stock.input == 0 &&
                          blocked->snapshot().state.material.belt_lanes.begin()->second.slots.back() == m::Cargo{0, 1, {}},
                          "A raw-only processor leaves a finished product on the belt.");
                }
                const auto encoded = w::encode_checkpoint(profile, world->snapshot());
                check(std::holds_alternative<V>(encoded), "An in-flight span route checkpoints.");
                const auto decoded = w::decode_checkpoint(profile, "route-world", std::get<V>(encoded));
                check(std::holds_alternative<w::Snapshot>(decoded), "An in-flight span route decodes.");
                auto restored = w::World::restore("route-world", profile, std::get<w::Snapshot>(decoded));
                check(restored != nullptr, "A fresh World resumes the in-flight route.");
                for (int i = 0; i < 8; ++i) {
                    const auto original_tick = world->tick();
                    const auto restored_tick = restored->tick();
                    check(original_tick.error == w::TransactionError::none && restored_tick.error == w::TransactionError::none &&
                          world->snapshot().state == restored->snapshot().state,
                          "Original and restored lanes continue with identical material custody.");
                }
                const auto& material = restored->snapshot().state.material;
                check(material.stock.input == (reverse || gap ? 0 : 1),
                      "Only an adjacent processor in the direction of travel accepts raw material.");
                if (reverse || gap) {
                    const I travel = reverse ? -4 : 12;
                    const m::DropPoint exit{rotated ? 0 : travel, 0, rotated ? travel : 0};
                    check(material.dropped_material.contains(exit) && material.dropped_material.at(exit).raw_units > 0,
                          "An unconnected outgoing end ejects conserved raw cargo at its actual endpoint.");
                }
                check(m::validate(material, profile.material, w::material_path(restored->snapshot().state.topology)) == m::Error::none,
                      "A full processor and reversed flow preserve every finite source unit.");
                if (reverse || gap) {
                    const I travel = reverse ? -4 : 12;
                    const m::DropPoint exit{rotated ? 0 : travel, 0, rotated ? travel : 0};
                    O pickup{{"context", V("route-world")}, {"client", V("P-old")}, {"request", V("pickup-ejected")},
                        {"actor", V("P")}, {"action", V("pickup_material")},
                        {"center", V(V::Array{V(exit[0]), V(exit[1]), V(exit[2])})}};
                    const auto before_pickup = restored->snapshot().state.material.dropped_material.at(exit).raw_units;
                    pickup.emplace("expected", V(O{{"raw", V(before_pickup)}, {"products", V(I{0})}, {"work_lots", V(V::Array{})}}));
                    accepted(send(*restored, pickup));
                    check(restored->snapshot().state.material.cargo.at("P").raw_units == before_pickup &&
                              !restored->snapshot().state.material.dropped_material.contains(exit),
                          "Ejected blanks move into the actor's canonical custody on pickup.");
                }
            }
        }
    }
}

void belt_span_commands() {
    w::Profile profile;
    profile.material = {1, 1, 2}; profile.initial_units = 1; profile.actors = {"P"};
    profile.meters_per_grid_unit = 0.1;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::shaft, 0, 2}, 2},
                            {{s::Role::belt, 0, 0}, 1}};
    w::State state;
    state.material.initial_units = 1; state.material.stock.source = 1; state.material.cargo = {{"P", {}}};
    state.kits = {{"P", {{{s::Role::belt, 0, 0}, 1}}}};
    state.topology.parts = {{{"wheel", g::Kind::hub, {0, 0, -4}, g::Axis::z, 0, 0}, 1, s::Role::waterwheel},
        {{"left", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft},
        {{"right", g::Kind::shaft, {8, 0, 0}, g::Axis::z, 0, 2}, 1, s::Role::shaft}};
    state.topology.sources = {{"wheel", {1, 1}}}; state.topology.drive_enabled = true;
    state.issued_entities = {{"wheel", 1}, {"left", 1}, {"right", 1}};
    auto inclined = state;
    inclined.topology.parts.back().geometry.center[1] = 8;
    auto inclined_world = w::World::create("saved-world", profile, inclined);
    check(inclined_world != nullptr, "The World accepts the separate inclined shaft endpoints.");
    auto inclined_command = command("place_belt_span", "inclined-placement", "left");
    inclined_command.emplace("to", V("right")); inclined_command.emplace("to_generation", V(I{1}));
    const auto inclined_built = send(*inclined_world, inclined_command);
    check(inclined_built.completed() && field<bool>(*inclined_built.result, "accepted"),
          "The native World places an inclined belt between confirmed shafts.");
    const auto inclined_id = field<std::string>(*inclined_built.result, "entity");
    check(inclined_world->snapshot().state.material.belt_lanes.at(inclined_id).slots.size() == 3 &&
              s::power_view(inclined_world->snapshot().state.topology).mechanical.motion.at("right").rate == g::Rate{1, 1},
          "The inclined lane has one slot per tile and transmits power.");
    auto moving = inclined_world->snapshot().state;
    moving.material.stock.source = 0;
    moving.material.belt_lanes.at(inclined_id).slots[2] = m::Cargo{1, 0, {}};
    auto cargo_world = w::World::create("saved-world", profile, moving);
    check(cargo_world != nullptr, "A conserved inclined-lane cargo fixture creates a World.");
    check(cargo_world->tick().error == w::TransactionError::none &&
              cargo_world->snapshot().state.material.belt_lanes.at(inclined_id).phase == -2896 &&
              cargo_world->tick().error == w::TransactionError::none &&
              cargo_world->snapshot().state.material.belt_lanes.at(inclined_id).slots[1].has_value(),
          "The driven inclined lane moves cargo in shaft-signed direction.");
    const auto incline_save = w::encode_checkpoint(profile, cargo_world->snapshot());
    check(std::holds_alternative<V>(incline_save) && std::holds_alternative<w::Snapshot>(
              w::decode_checkpoint(profile, "saved-world", std::get<V>(incline_save))),
          "An occupied inclined lane round-trips through the native checkpoint.");
    auto recover_world = w::World::restore("saved-world", profile,
        std::get<w::Snapshot>(w::decode_checkpoint(profile, "saved-world", std::get<V>(incline_save))));
    auto recover = command("recover_belt_slot", "incline-recover", inclined_id.c_str());
    recover.at("generation") = V(field<I>(*inclined_built.result, "generation"));
    recover.emplace("slot", V(I{1}));
    recover.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(V::Array{})}}));
    const auto recovered = send(*recover_world, recover);
    check(recovered.completed() && field<bool>(*recovered.result, "accepted") &&
              !factory::values::typed_difference(V(field<V::Array>(*recovered.result, "slot_center")),
                  V(V::Array{V(I{4}), V(I{4}), V(I{0})})),
          "Inclined cargo recovery targets the actual elevated tile.");
    auto resumed_incline = w::World::restore("saved-world", profile,
        std::get<w::Snapshot>(w::decode_checkpoint(profile, "saved-world", std::get<V>(incline_save))));
    check(resumed_incline && resumed_incline->tick().error == w::TransactionError::none &&
              cargo_world->tick().error == w::TransactionError::none &&
              resumed_incline->snapshot().state.material == cargo_world->snapshot().state.material,
          "Original and restored inclined lanes continue identically.");
    auto sideways = state;
    sideways.topology.parts.erase(sideways.topology.parts.begin());
    sideways.topology.sources.clear();
    sideways.kits.at("P").emplace(s::PartSpec{s::Role::waterwheel, 0, 0}, 1);
    for (auto& item : sideways.topology.parts) item.geometry.axis = g::Axis::y;
    auto sideways_world = w::World::create("saved-world", profile, sideways);
    check(sideways_world != nullptr, "The World accepts separate vertical shafts for a sideways belt.");
    auto sideways_command = command("place_belt_span", "sideways-placement", "left");
    sideways_command.emplace("to", V("right")); sideways_command.emplace("to_generation", V(I{1}));
    const auto sideways_built = send(*sideways_world, sideways_command);
    check(sideways_built.completed() && field<bool>(*sideways_built.result, "accepted"),
          "The native World places a sideways power-only belt.");
    const auto sideways_id = field<std::string>(*sideways_built.result, "entity");
    auto sideways_cargo = sideways_world->snapshot().state;
    sideways_cargo.material.stock.source = 0;
    sideways_cargo.material.belt_lanes.at(sideways_id).slots[1] = m::Cargo{1, 0, {}};
    check(w::World::create("saved-world", profile, sideways_cargo) == nullptr,
          "A sideways power-only belt cannot retain cargo.");
    auto vertical = state;
    vertical.topology.parts.back().geometry.center = {0, 8, 0};
    auto vertical_world = w::World::create("saved-world", profile, vertical);
    check(vertical_world != nullptr, "The World accepts separate vertical shaft endpoints.");
    auto vertical_command = command("place_belt_span", "vertical-placement", "left");
    vertical_command.emplace("to", V("right")); vertical_command.emplace("to_generation", V(I{1}));
    const auto vertical_built = send(*vertical_world, vertical_command);
    check(vertical_built.completed() && field<bool>(*vertical_built.result, "accepted"),
          "The native World places a vertical belt for power transmission.");
    const auto vertical_id = field<std::string>(*vertical_built.result, "entity");
    auto illegal_cargo = vertical_world->snapshot().state;
    illegal_cargo.material.stock.source = 0;
    illegal_cargo.material.belt_lanes.at(vertical_id).slots[1] = m::Cargo{1, 0, {}};
    check(w::World::create("saved-world", profile, illegal_cargo) == nullptr,
          "A vertical power-only belt cannot retain cargo.");
    check(vertical_world->tick().error == w::TransactionError::none &&
              s::power_view(vertical_world->snapshot().state.topology).mechanical.motion.at("right").rate == g::Rate{1, 1},
          "An empty vertical belt ticks and continues to transmit power.");
    auto world = w::World::create("saved-world", profile, state);
    check(world != nullptr, "The belt command fixture creates the single World.");
    auto place = command("place_belt_span", "belt-place", "left");
    place.emplace("to", V("right")); place.emplace("to_generation", V(I{1}));
    auto far = place; far.at("request") = V("belt-far");
    const auto distant = world->command({"P", "P-old"}, far, [](const std::string& who) -> std::optional<a::ActorCut> {
        return a::ActorCut{who, {50, 0, 0}, 1, true, 4};
    });
    check(distant.completed() && !field<bool>(*distant.result, "accepted") &&
              world->snapshot().state == state, "A far actor cannot place or consume the belt.");
    const auto built = send(*world, place);
    check(built.completed() && field<bool>(*built.result, "accepted"), "A nearby actor creates the belt span.");
    const auto id = field<std::string>(*built.result, "entity");
    const auto generation = field<I>(*built.result, "generation");
    check(world->snapshot().state.kits.at("P").at({s::Role::belt, 0, 0}) == 0 &&
              s::power_view(world->snapshot().state.topology).mechanical.motion.at("right").rate == g::Rate{1, 1},
          "The committed belt consumes its finite part and powers the remote shaft.");
    auto endpoint = command("remove", "remove-endpoint", "left");
    const auto blocked = send(*world, endpoint);
    check(blocked.completed() && !field<bool>(*blocked.result, "accepted") &&
              field<std::string>(*blocked.result, "reason") == "belt_attached",
          "An attached shaft cannot be removed before its belt.");
    const auto encoded = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(encoded), "A constructed belt and its request history encode.");
    const auto decoded = w::decode_checkpoint(profile, "saved-world", std::get<V>(encoded));
    check(std::holds_alternative<w::Snapshot>(decoded), "The exact constructed belt history decodes.");
    auto restored = w::World::restore("saved-world", profile, std::get<w::Snapshot>(decoded));
    check(restored != nullptr, "A fresh World resumes the constructed belt.");
    const auto duplicate = send(*restored, place);
    check(duplicate.completed() && field<bool>(*duplicate.result, "accepted") && field<bool>(*duplicate.result, "duplicate"),
          "An exact retried construction returns the original receipt without another belt.");
    auto remove = command("remove_belt_span", "belt-remove", id.c_str());
    remove.at("generation") = V(generation);
    accepted(send(*restored, remove));
    check(restored->snapshot().state.topology.belt_spans.empty() &&
              restored->snapshot().state.kits.at("P").at({s::Role::belt, 0, 0}) == 1 &&
              s::power_view(restored->snapshot().state.topology).mechanical.motion.at("right").state == g::MotionState::unpowered,
          "Removing the span refunds one belt and stops remote power.");
    endpoint.at("request") = V("remove-endpoint-after-belt");
    accepted(send(*restored, endpoint));
    const auto after = w::encode_checkpoint(profile, restored->snapshot());
    check(std::holds_alternative<V>(after) &&
              std::holds_alternative<w::Snapshot>(w::decode_checkpoint(profile, "saved-world", std::get<V>(after))),
          "Removed belt history remains valid after both endpoints and the span have changed.");
}
}  // namespace

int main() {
    try {
        round_trip_restore_and_continue();
        schema_and_authority_mutations();
        bounds_and_large_integers();
        belt_span_checkpoint();
        belt_span_material_route(); adjacent_belt_handoff(); inclined_material_route();
        belt_span_commands();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_native_checkpoint\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "checkpoint_test: " << error.what() << '\n';
        return 1;
    }
}
