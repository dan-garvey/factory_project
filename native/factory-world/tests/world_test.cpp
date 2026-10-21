#include "factory/world.hpp"

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
using I = a::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& get(const a::Object& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

s::PlacedPart hub(const char* id, s::Role role, I x, I z) {
    return {{id, g::Kind::hub, {x, 0, z}, g::Axis::z, 0, 0}, 1, role};
}

s::PlacedPart shaft(const char* id, I x) {
    return {{id, g::Kind::shaft, {x, 0, 4}, g::Axis::z, 0, 2}, 1, s::Role::shaft};
}

struct Fixture { w::Profile profile; w::State state; };

Fixture fixture() {
    Fixture f;
    f.profile.material = {1, 1, 2};
    f.profile.waterwheel_rate = {-1, 1};
    f.profile.initial_units = 16;
    f.profile.actors = {"P", "Q"};
    f.profile.meters_per_grid_unit = 0.1;
    f.profile.build_reach = 4;
    f.profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, 3},
        {{s::Role::shaft, 0, 2}, 3}, {{s::Role::collector, 0, 0}, 1},
        {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1},
        {{s::Role::gear, 8, 0}, 1}};
    f.state.material.initial_units = 16;
    f.state.material.stock.source = 16;
    f.state.material.cargo = {{"P", {}}, {"Q", {}}};
    f.state.kits = {{"P", {{{s::Role::gear, 8, 0}, 1}}}, {"Q", {}}};
    f.state.topology.parts = {hub("wheel-A", s::Role::waterwheel, 0, 0), shaft("shaft-A", 0),
        hub("collector", s::Role::collector, 0, 8), hub("wheel-B", s::Role::waterwheel, 4, 0),
        shaft("shaft-B", 4), hub("belt", s::Role::belt, 4, 8),
        hub("wheel-C", s::Role::waterwheel, 8, 0), shaft("shaft-C", 8),
        hub("processor", s::Role::processor, 8, 8)};
    f.state.topology.material_links = {{{"collector", 1}, {"belt", 1}}, {{"belt", 1}, {"processor", 1}}};
    f.state.topology.sources = {{"wheel-A", {-1, 1}}, {"wheel-B", {-1, 1}}, {"wheel-C", {-1, 1}}};
    f.state.topology.drive_enabled = true;
    for (const auto& part : f.state.topology.parts) f.state.issued_entities.emplace(part.geometry.id, part.generation);
    return f;
}

std::unique_ptr<w::World> world(const Fixture& f) {
    auto result = w::World::create("fixture-world", f.profile, f.state);
    check(result != nullptr, "The complete canonical finite seed must initialize.");
    return result;
}

a::Object intent(const char* action, const char* request, const char* actor = "P") {
    return {{"context", V("fixture-world")}, {"client", V(std::string(actor) + "-session")},
        {"request", V(request)}, {"actor", V(actor)}, {"action", V(action)}};
}

a::Object target(const char* action, const char* request, const char* id, const char* actor = "P", I generation = 1) {
    auto result = intent(action, request, actor);
    result.emplace("target", V(id));
    result.emplace("generation", V(generation));
    return result;
}

a::Object place(const char* request, const char* role, I x, I z, I span = 0) {
    auto result = intent("place", request);
    result.emplace("role", V(role));
    result.emplace("center", V(V::Array{V(x), V(I{0}), V(z)}));
    result.emplace("axis", V("z"));
    result.emplace("teeth", V(I{0}));
    result.emplace("half_span", V(span));
    return result;
}

struct Observer {
    a::Point position{};
    bool ready{true};
    int calls{};
    w::ObserveActor callback() {
        return [this](const std::string& actor) -> std::optional<a::ActorCut> {
            ++calls;
            return a::ActorCut{actor, position, 1, ready, 1000000};
        };
    }
};

w::Delivery send(w::World& world, const a::Object& request, Observer& observer) {
    const auto actor = get<std::string>(request, "actor");
    return world.command({actor, actor + "-session"}, request, observer.callback());
}

void outcome(const w::Delivery& delivery, bool accepted, const char* reason) {
    check(delivery.completed(), "A fresh well-formed request must retain an original outcome.");
    if (get<bool>(*delivery.result, "accepted") != accepted)
        throw std::runtime_error(std::string("Expected ") + reason + ", got " + get<std::string>(*delivery.result, "reason") +
                                 " after " + std::to_string(checks) + " checks.");
    check(get<bool>(*delivery.result, "accepted") == accepted, "The accepted flag must match the literal expectation.");
    check(get<std::string>(*delivery.result, "reason") == reason, "The original reason must match.");
}

bool same_history(const w::Snapshot& left, const w::Snapshot& right) {
    const auto l = a::encode_history(left.history, left.revision);
    const auto r = a::encode_history(right.history, right.revision);
    return l.value && r.value && !factory::values::typed_difference(*l.value, *r.value);
}

void startup_and_complete_validation() {
    auto f = fixture();
    auto owner = world(f);
    f.state.material.stock.source = 0;
    check(owner->snapshot().state.material.stock.source == 16, "Startup owns a copy of canonical material.");
    auto exported = owner->snapshot();
    exported.state.kits.at("P").clear();
    check(owner->snapshot().state.kits.at("P").size() == 1, "Exported part inventories are detached.");
    const auto bad = [](const Fixture& invalid) {
        return !w::World::create("fixture-world", invalid.profile, invalid.state);
    };
    f = fixture(); f.state.material.cargo.erase("Q"); check(bad(f), "A missing actor Cargo refuses startup.");
    f = fixture(); f.state.kits.emplace("stranger", s::Kit{}); check(bad(f), "An extra kit actor refuses startup.");
    f = fixture(); ++f.state.kits.at("P").begin()->second; check(bad(f), "An extra physical gear violates finite part custody.");
    f = fixture(); ++f.state.material.stock.source; check(bad(f), "A material refill violates finite conservation.");
    f = fixture(); f.state.issued_entities.at("shaft-A") = 2; check(bad(f), "Live generations must match issued history.");
    f = fixture(); f.state.topology.material_links.front().to.generation = 2;
    check(bad(f), "Stale material links refuse startup before stepping.");
    f = fixture();
    for (auto& item : f.state.topology.parts)
        if (item.geometry.id == "belt") item.geometry.center[2] += 4;
    check(bad(f), "A seed cannot link nonadjacent material ports.");
    auto altered = world(fixture())->snapshot();
    for (auto& item : altered.state.topology.parts)
        if (item.geometry.id == "belt") item.geometry.center[2] += 4;
    check(!w::World::restore("fixture-world", fixture().profile, altered),
          "A restored checkpoint cannot preserve a link across a material-port gap.");
    f = fixture(); f.state.topology.sources.front().rate = {2, 1}; check(bad(f), "Client-selected source speed is not profile authority.");
    f = fixture(); f.state.topology.parts.front().wheel_tiles = 2;
    check(bad(f), "An undersized saved wheel is not a valid World state.");
    f = fixture(); f.state.issued_entities.emplace("native-part-1", 1);
    check(bad(f), "The issued identity counter cannot be reset behind history.");
    f = fixture(); f.profile.meters_per_grid_unit = std::numeric_limits<double>::infinity();
    check(bad(f), "Nonfinite geometry scaling refuses startup.");
}

void authentication_reach_and_replay() {
    auto f = fixture();
    f.state.material.stock.source = 15;
    f.state.material.stock.output = 1;
    auto owner = world(f);
    Observer observer;
    auto request = target("collect", "far", "processor");
    request.emplace("amount", V(I{1}));
    observer.position = {0, 20, 0};
    outcome(send(*owner, request, observer), false, "out_of_reach");
    const auto first = owner->snapshot();
    observer.position = {0, 0, 0};
    observer.calls = 0;
    const auto duplicate = send(*owner, request, observer);
    outcome(duplicate, false, "out_of_reach");
    check(get<bool>(*duplicate.result, "duplicate") && observer.calls == 0,
          "A retry returns the old refusal without sampling the new pose.");
    check(same_history(first, owner->snapshot()), "Delivery-only duplicate flags never change retained history.");

    request.at("request") = V("near");
    outcome(send(*owner, request, observer), true, "ok");
    check(owner->snapshot().state.material.cargo.at("P").products == 1 &&
          owner->snapshot().state.material.cargo.at("Q").products == 0,
          "Collection credits only the bound actor's product custody.");
    request.at("amount") = V(1.0);
    const auto reused = send(*owner, request, observer);
    check(!reused.completed() && reused.history_error == a::Error::request_reuse,
          "A float cannot reuse the identity of an integer command.");
    auto spoof = target("remove", "spoof", "shaft-A", "Q");
    check(owner->command({"P", "P-session"}, spoof, observer.callback()).history_error == a::Error::wrong_actor,
          "Session actor and namespace binding precede any receipt access.");
    check(owner->command({"Q", "P-session"}, spoof, observer.callback()).history_error == a::Error::wrong_actor,
          "A caller cannot substitute another request namespace.");
    auto extra = target("remove", "pose", "shaft-A");
    extra.emplace("pose", V(V::Array{}));
    observer.calls = 0;
    outcome(send(*owner, extra, observer), false, "invalid_command");
    check(observer.calls == 0, "A client pose field does not reach native admission.");
    auto malformed = target("remove", "float-generation", "shaft-A");
    malformed.at("generation") = V(1.0);
    outcome(send(*owner, malformed, observer), false, "invalid_target");
    auto amount = target("collect", "boolean-amount", "processor");
    amount.emplace("amount", V(true));
    outcome(send(*owner, amount, observer), false, "invalid_command");
}

void running_removal_rebuild_and_tick() {
    auto f = fixture();
    f.state.material.stock = {14, 0, 1, 0, 1};
    auto owner = world(f);
    Observer observer;
    const auto remove = target("remove", "remove-A", "shaft-A");
    outcome(send(*owner, remove, observer), true, "ok");
    auto before_tick = owner->snapshot();
    const auto power = w::machine_power(before_tick.state.topology);
    check(!power.collector && power.belt && power.processor, "Removing a real shaft stops only its connected branch.");
    check(before_tick.state.topology.drive_enabled && before_tick.state.kits.at("P").at({s::Role::shaft, 0, 2}) == 1,
          "Running removal preserves global drive and refunds the exact physical shaft.");
    const auto tick = owner->tick();
    const auto after_tick = owner->snapshot();
    check(tick.error == w::TransactionError::none && tick.changed && tick.current_revision == before_tick.revision + 1,
          "Trusted material stepping commits one revision.");
    check(after_tick.state.material.stock == m::Stock{14, 0, 0, 1, 1},
          "The independent belt keeps feeding while the disconnected collector extracts nothing.");
    check(same_history(before_tick, after_tick), "Trusted stepping does not fabricate a material request or rewrite its history.");
    observer.calls = 0;
    const auto duplicate = send(*owner, remove, observer);
    outcome(duplicate, true, "ok");
    check(observer.calls == 0 && duplicate.current_revision == after_tick.revision &&
          get<I>(*duplicate.result, "revision") == before_tick.revision,
          "Retry retains its original receipt revision after a newer step and target removal.");
    outcome(send(*owner, target("remove", "remove-again", "shaft-A"), observer), false, "unknown_target");
    const auto rebuilt = send(*owner, place("rebuild-A", "shaft", 0, 4, 2), observer);
    outcome(rebuilt, true, "ok");
    const auto rebuilt_state = owner->snapshot().state;
    check(get<std::string>(*rebuilt.result, "entity") == "native-part-1" &&
          rebuilt_state.issued_entities.contains("shaft-A") && rebuilt_state.issued_entities.contains("native-part-1"),
          "Rebuilding allocates a new identity while retaining the old entity history.");
    check(rebuilt_state.kits.at("P").at({s::Role::shaft, 0, 2}) == 0 && w::machine_power(rebuilt_state.topology).collector,
          "The returned exact part is consumed once and restores geometric transmission.");
    const auto serial = rebuilt_state.next_entity_serial;
    outcome(send(*owner, place("no-second-shaft", "shaft", 32, 0, 2), observer), false, "unavailable_part");
    check(owner->snapshot().state.next_entity_serial == serial, "A refused build consumes no identity or physical part.");
}

void preserve_work_through_recovery_and_rebuild() {
    auto f = fixture();
    f.state.material.stock = {14, 0, 0, 1, 0};
    f.state.material.processing = m::WorkLot{1, {1, 2}, 1, m::work_subticks_per_tick / 2};
    f.state.material.next_work_id = 2;
    auto owner = world(f);
    Observer observer;
    outcome(send(*owner, target("remove", "occupied", "processor"), observer), false, "occupied_target");
    const auto recovery_request = target("recover", "recover-work", "processor");
    const auto recovery = send(*owner, recovery_request, observer);
    outcome(recovery, true, "ok");
    const auto recovered = owner->snapshot();
    check(recovered.state.material.cargo.at("P") == m::Cargo{1, 0, {{1, {1, 2}, 1, m::work_subticks_per_tick / 2}}} &&
          recovered.state.material.stock == m::Stock{14, 0, 0, 0, 0} && !recovered.state.material.processing,
          "Recovery moves raw and the original partial whole lot into one actor's canonical Cargo.");
    outcome(send(*owner, target("remove", "empty-processor", "processor"), observer), true, "ok");
    const auto build = send(*owner, place("new-processor", "processor", 8, 8), observer);
    outcome(build, true, "ok");
    auto insert = target("insert_work", "resume-work", "native-part-1");
    insert.emplace("work_id", V(I{1}));
    outcome(send(*owner, insert, observer), true, "ok");
    check(owner->snapshot().state.material.processing == m::WorkLot{1, {1, 2}, 1, m::work_subticks_per_tick / 2},
          "Insertion preserves work identity, recipe and remaining progress exactly.");
    const auto before_tick = owner->snapshot();
    const auto tick = owner->tick();
    check(tick.error == w::TransactionError::none && tick.changed,
          "The geometrically powered rebuilt processor advances real canonical work.");
    const auto completed = owner->snapshot();
    check(!completed.state.material.processing && completed.state.material.stock.output == 1 &&
          completed.state.material.cargo.at("P").raw_units == 1 && completed.state.material.next_work_id == 2,
          "The recovered partial lot completes once without restart, raw loss or another serial.");
    check(same_history(before_tick, completed), "Completion preserves all original material receipts.");
    observer.calls = 0;
    const auto replay = send(*owner, recovery_request, observer);
    outcome(replay, true, "ok");
    check(observer.calls == 0 && !factory::values::typed_difference(
          recovery.result->at("moved_work"), replay.result->at("moved_work")),
          "Historical work facts do not retarget the completed or rebuilt work.");
    auto collect = target("collect", "Q-product", "native-part-1", "Q");
    collect.emplace("amount", V(I{1}));
    outcome(send(*owner, collect, observer), true, "ok");
    check(owner->snapshot().state.material.cargo.at("Q").products == 1 &&
          owner->snapshot().state.material.cargo.at("P").products == 0,
          "A fresh bound actor collects its own product after the original actor's recovery.");
    check(w::validate(f.profile, owner->snapshot()), "Every accepted edit and step retains full World invariants.");
}

void ready_work_and_two_endpoint_reach() {
    auto f = fixture();
    f.state.material.stock = {14, 0, 0, 0, 1};
    f.state.material.processing = m::WorkLot{1, {1, 2}, 0};
    f.state.material.next_work_id = 2;
    auto owner = world(f);
    Observer observer;
    outcome(send(*owner, target("remove", "ready-is-occupied", "processor"), observer), false, "occupied_target");
    outcome(send(*owner, target("recover", "recover-ready", "processor"), observer), true, "ok");
    check(owner->snapshot().state.material.cargo.at("P") == m::Cargo{0, 1, {{1, {1, 2}, 0}}},
          "A blocked ready lot and an output product remain distinct custody.");
    const auto tick = owner->tick();
    check(tick.error == w::TransactionError::none &&
          owner->snapshot().state.material.cargo.at("P").work_lots.front().remaining_ticks == 0,
          "Trusted machine ticks do not advance or complete carried work.");

    f = fixture();
    f.state.topology.material_links.clear();
    for (auto& item : f.state.topology.parts)
        if (item.geometry.id == "belt") item.geometry.center[0] = 12;
    owner = world(f);
    auto gap = target("link", "gap-within-reach", "collector");
    gap.emplace("to", V("belt"));
    gap.emplace("to_generation", V(I{1}));
    observer.position = {0.6, 0, 0.8};
    const auto before_gap = owner->snapshot().state;
    outcome(send(*owner, gap, observer), false, "ports_not_adjacent");
    check(owner->snapshot().state == before_gap, "A reachable gap cannot become a material link.");
    auto duplicate = send(*owner, gap, observer);
    check(duplicate.result && get<bool>(*duplicate.result, "duplicate") &&
          get<std::string>(*duplicate.result, "reason") == "ports_not_adjacent" &&
          owner->snapshot().state == before_gap, "A gap refusal is retry-safe and preserves material custody.");

    for (auto& item : f.state.topology.parts)
        if (item.geometry.id == "collector") item.geometry.center[0] = 8;
        else if (item.geometry.id == "processor") item.geometry.center[0] = 16;
    f.profile.build_reach = 0.21;
    owner = world(f);
    auto link = target("link", "far-endpoint", "collector");
    link.emplace("to", V("belt"));
    link.emplace("to_generation", V(I{1}));
    observer.position = {0.8, 0, 0.8};
    outcome(send(*owner, link, observer), false, "out_of_reach");
    check(owner->snapshot().state.topology.material_links.empty(), "A near first endpoint cannot authorize a far second endpoint.");
    observer.position = {1.0, 0, 0.8};
    link.at("request") = V("both-endpoints");
    outcome(send(*owner, link, observer), true, "ok");
    check(owner->snapshot().state.topology.material_links.size() == 1,
          "Both endpoints within the scalar reach boundary may connect.");
    f.profile.build_reach = 4;
    owner = world(f);
    auto arbitrary = target("link", "arbitrary-drive-edge", "wheel-A");
    arbitrary.emplace("to", V("collector")); arbitrary.emplace("to_generation", V(I{1}));
    observer.position = {0, 0, 0.4};
    outcome(send(*owner, arbitrary, observer), false, "incompatible_link");
}

void atomic_step_and_callback_failures() {
    auto f = fixture();
    f.state.material.stock = {15, 0, 0, 1, 0};
    f.state.material.next_work_id = std::numeric_limits<I>::max();
    auto owner = world(f);
    const auto before = owner->snapshot();
    const auto failed = owner->tick();
    check(failed.error == w::TransactionError::preparation_failed && !failed.changed &&
          owner->snapshot().state == before.state && owner->snapshot().revision == before.revision,
          "A failed work allocation publishes no partial material step or revision.");
    check(same_history(before, owner->snapshot()), "A failed step leaves cached requests untouched.");

    f = fixture(); f.state.topology.drive_enabled = false; owner = world(f);
    const auto stopped = owner->tick();
    check(stopped.error == w::TransactionError::none && !stopped.changed && stopped.current_revision == 0,
          "An unchanged stopped tick consumes no revision or request identity.");
    Observer observer;
    const auto nested = owner->command({"P", "P-session"}, target("remove", "nested-step", "shaft-A"),
        [&](const std::string& actor) -> std::optional<a::ActorCut> {
            check(owner->tick().error == w::TransactionError::reentrant,
                  "A callback cannot advance the World inside another pending transaction.");
            return a::ActorCut{actor, {}, 1, true, 4};
        });
    outcome(nested, true, "ok");
    const auto stable = owner->snapshot();
    const auto exception = owner->command({"P", "P-session"}, target("remove", "observation-error", "shaft-B"),
        [](const std::string&) -> std::optional<a::ActorCut> { throw std::runtime_error("invented observer error"); });
    check(exception.error == w::TransactionError::preparation_failed && owner->snapshot().state == stable.state &&
          same_history(stable, owner->snapshot()), "Observation exceptions commit neither candidate nor cached outcome.");
}

void trusted_flow_drives_world() {
    auto f = fixture();
    for (const I x : {0, 4, 8}) f.profile.water[{x, 0}] = {0, -500, 200, 0};
    for (auto& source : f.state.topology.sources) source.rate = {1, 3};
    auto owner = world(f);
    auto view = s::power_view(owner->snapshot().state.topology).mechanical;
    check(view.motion.at("collector").rate == g::Rate{1, 3},
          "The connected shaft receives the local water speed.");
    auto reversed = f;
    reversed.profile.water.at({0, 0}).velocity_x = -200;
    check(!w::World::create("fixture-world", reversed.profile, reversed.state),
          "A saved source cannot retain its old rate under reversed trusted flow.");
    reversed.state.topology.sources.front().rate = {-1, 3};
    owner = world(reversed);
    view = s::power_view(owner->snapshot().state.topology).mechanical;
    check(view.motion.at("collector").rate == g::Rate{-1, 3},
          "Reversed trusted flow reverses the connected shaft.");
    auto dry = f;
    dry.profile.water.erase({0, 0});
    dry.state.topology.sources.front().rate = {0, 1};
    owner = world(dry);
    view = s::power_view(owner->snapshot().state.topology).mechanical;
    check(view.motion.at("collector").state == g::MotionState::stopped,
          "A wheel outside sampled water cannot drive its connected shaft.");
}
}  // namespace

int main() {
    try {
        startup_and_complete_validation();
        authentication_reach_and_replay();
        running_removal_rebuild_and_tick();
        preserve_work_through_recovery_and_rebuild();
        ready_work_and_two_endpoint_reach();
        atomic_step_and_callback_failures();
        trusted_flow_drives_world();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_native_world\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "world_test: " << error.what() << '\n';
        return 1;
    }
}
