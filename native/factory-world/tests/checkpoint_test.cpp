#include "factory/checkpoint.hpp"

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
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 1}, {{s::Role::shaft, 0, 2}, 2},
                            {{s::Role::belt, 0, 0}, 1}};
    w::State state;
    state.material.initial_units = 1; state.material.stock.source = 1;
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
    auto spans = std::get<V::Array>(at(std::get<V>(encoded), {"state", "topology", "belt_spans"}).storage());
    spans[0] = edited(spans[0], {"last_shaft"}, V("missing"));
    refusal(profile, edited(std::get<V>(encoded), {"state", "topology", "belt_spans"}, V(spans)),
            w::CheckpointReason::invalid_world);
    refusal(profile, edited(std::get<V>(encoded), {"schema"}, V(I{2})), w::CheckpointReason::unsupported_schema);
    auto malformed = state; malformed.topology.belt_spans[0].geometry.last_shaft = "missing";
    check(!w::World::create("saved-world", profile, malformed), "A dangling saved belt endpoint is refused.");
    malformed = state; malformed.kits.at("P")[{s::Role::belt, 0, 0}] = 1;
    check(!w::World::create("saved-world", profile, malformed), "A belt cannot be both placed and carried.");
}
}  // namespace

int main() {
    try {
        round_trip_restore_and_continue();
        schema_and_authority_mutations();
        bounds_and_large_integers();
        belt_span_checkpoint();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_native_checkpoint\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "checkpoint_test: " << error.what() << '\n';
        return 1;
    }
}
