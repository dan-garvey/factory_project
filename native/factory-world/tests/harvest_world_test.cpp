#include "factory/checkpoint.hpp"
#include "factory/world.hpp"

#include <iostream>
#include <stdexcept>

namespace {
namespace w = factory::world;
namespace m = factory::materials;
namespace a = factory::authority;
using V = factory::values::Value;
using O = V::Object;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

std::pair<w::Profile, w::State> seed() {
    w::Profile profile;
    profile.material = {1, 32, 2};
    profile.material.timber_sites = {{"tree-a", {{12, 0, 12}, 8}},
                                     {"tree-b", {{12, 0, 24}, 8}}};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.hand_carry_capacity = 24;
    profile.initial_units = 16;
    profile.actors = {"P", "Q"};
    profile.meters_per_grid_unit = 0.4125;
    profile.anchor_offset = {0, 1, 0};
    profile.build_reach = 4;
    w::State state;
    state.material.initial_units = 16;
    state.material.stock.source = 16;
    state.material.timber_remaining = {{"tree-a", 8}, {"tree-b", 8}};
    state.material.cargo = {{"P", {}}, {"Q", {}}};
    state.kits = {{"P", {}}, {"Q", {}}};
    return {profile, state};
}

O command(const char* actor, const char* client, const char* request, const char* target) {
    return {{"context", V("harvest-world")}, {"client", V(client)}, {"request", V(request)},
        {"actor", V(actor)}, {"action", V("harvest_source")}, {"target", V(target)}};
}

O finish(const char* actor, const char* client, const char* request) {
    return {{"context", V("harvest-world")}, {"client", V(client)}, {"request", V(request)},
        {"actor", V(actor)}, {"action", V("finish_harvest")}};
}

O cancel(const char* actor, const char* client, const char* request) {
    return {{"context", V("harvest-world")}, {"client", V(client)}, {"request", V(request)},
        {"actor", V(actor)}, {"action", V("cancel_harvest")}};
}

void harvest_and_restore() {
    auto [profile, state] = seed();
    auto world = w::World::create("harvest-world", profile, state);
    check(world != nullptr, "A native World accepts trusted tree and ore source facts.");
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, actor == "P" ? a::Point{1.65, 1, 6.6} : a::Point{-1.2375, 1, 0},
            3, true, 4};
    };
    const auto tree = command("P", "P-client", "tree-cut", "tree-a");
    const auto first = world->command({"P", "P-client"}, tree, nearby);
    check(first.completed() && std::get<bool>(first.result->at("accepted").storage()) &&
          world->snapshot().state.material.timber_remaining.at("tree-a") == 8 &&
          world->snapshot().state.material.cargo.at("P").timber == 0,
          "A physical P cut starts without transferring timber before tool contact.");
    for (I tick = 1; tick < w::manual_cut_ticks; ++tick)
        check(world->tick(nearby).changed, "Trusted native ticks advance the active cut.");
    check(world->snapshot().state.material.timber_remaining.at("tree-a") == 8 &&
          world->snapshot().state.material.cargo.at("P").timber == 0,
          "No timber moves before the required contact tick.");
    check(world->tick(nearby).changed, "The contact tick makes the cut finishable.");
    const auto first_contact = world->command({"P", "P-client"},
        finish("P", "P-client", "tree-contact"), nearby);
    check(first_contact.completed() && std::get<bool>(first_contact.result->at("accepted").storage()) &&
          world->snapshot().state.material.timber_remaining.at("tree-a") == 7 &&
          world->snapshot().state.material.cargo.at("P").timber == 1,
          "Only the authenticated finish transfers one timber from the targeted tree.");
    const auto before_retry = world->snapshot();
    const auto retry = world->command({"P", "P-client"}, tree,
        [](const std::string&) -> std::optional<a::ActorCut> { return std::nullopt; });
    check(retry.completed() && std::get<bool>(retry.result->at("duplicate").storage()) &&
          world->snapshot().state == before_retry.state && world->snapshot().revision == before_retry.revision,
          "A cached retry is decided before observation and cannot duplicate wood.");
    const auto ore = world->command({"Q", "Q-client"}, command("Q", "Q-client", "ore-cut", "ore"), nearby);
    check(ore.completed() && std::get<bool>(ore.result->at("accepted").storage()) &&
          world->snapshot().state.material.stock.source == 16,
          "Ore remains in its shared source when Q starts cutting.");
    for (I tick = 0; tick < w::manual_cut_ticks; ++tick)
        check(world->tick(nearby).changed, "Q's accepted cut advances on trusted native ticks.");
    const auto ore_contact = world->command({"Q", "Q-client"},
        finish("Q", "Q-client", "ore-contact"), nearby);
    check(ore_contact.completed() && std::get<bool>(ore_contact.result->at("accepted").storage()) &&
          world->snapshot().state.material.stock.source == 15 &&
          world->snapshot().state.material.cargo.at("Q").raw_units == 1,
          "Q's hand cut debits the collector's one finite ore reserve.");
    const auto far = world->command({"P", "P-client"}, command("P", "P-client", "far-cut", "tree-b"), nearby);
    check(far.completed() && !std::get<bool>(far.result->at("accepted").storage()) &&
          std::get<std::string>(far.result->at("reason").storage()) == "out_of_reach" &&
          world->snapshot().state.material.timber_remaining.at("tree-b") == 8,
          "A distant tree cannot be harvested from a camera or another actor's body.");
    const auto unknown = world->command({"P", "P-client"}, command("P", "P-client", "fake-cut", "fake"), nearby);
    check(unknown.completed() && !std::get<bool>(unknown.result->at("accepted").storage()) &&
          world->snapshot().state.material.cargo.at("P").timber == 1,
          "A forged source identity does not mint timber.");
    const auto snapshot = world->snapshot();
    const auto saved = w::encode_checkpoint(profile, snapshot);
    check(std::holds_alternative<V>(saved), "The World checkpoint includes tree and ore custody.");
    const auto decoded = w::decode_checkpoint(profile, "harvest-world", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(decoded) &&
          std::get<w::Snapshot>(decoded).state == snapshot.state,
          "A late join decodes the same source balances and actor inventory.");
    auto restored = w::World::restore("harvest-world", profile, std::get<w::Snapshot>(decoded));
    check(restored && restored->snapshot().state == snapshot.state,
          "A fresh authority restores the exact material ledger.");
    auto forged = snapshot;
    ++forged.state.material.cargo.at("P").timber;
    check(!w::World::restore("harvest-world", profile, forged),
          "A restored actor cannot receive unmined timber.");
    forged = snapshot;
    --forged.state.material.cargo.at("P").timber;
    ++forged.state.material.cargo.at("Q").timber;
    check(!w::World::restore("harvest-world", profile, forged),
          "A checkpoint cannot move timber between actors without an accepted transfer.");
    auto moved_tree = profile;
    moved_tree.material.timber_sites.at("tree-a").center = {16, 0, 12};
    const auto moved = w::decode_checkpoint(moved_tree, "harvest-world", std::get<V>(saved));
    check(std::holds_alternative<w::CheckpointRefusal>(moved),
          "A site anchor cannot move under an existing save or history.");
}

void interrupted_cut_and_shared_source() {
    auto [profile, state] = seed();
    auto world = w::World::create("harvest-world", profile, state);
    check(world != nullptr, "A two-actor cut starts from finite native stock.");
    const w::ObserveActor at_tree = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, {4.95, 1, 4.95}, 3, true, 4};
    };
    const auto started = world->command({"P", "P-client"},
        command("P", "P-client", "P-start", "tree-a"), at_tree);
    check(started.completed() && std::get<bool>(started.result->at("accepted").storage()) &&
          world->snapshot().state.material.timber_remaining.at("tree-a") == 8,
          "Starting P's cut reserves only the working source, not an item.");
    const auto competing = world->command({"Q", "Q-client"},
        command("Q", "Q-client", "Q-competing", "tree-a"), at_tree);
    check(competing.completed() && !std::get<bool>(competing.result->at("accepted").storage()) &&
          std::get<std::string>(competing.result->at("reason").storage()) == "source_busy",
          "A concurrent cut at the same source receives a deterministic refusal.");
    for (I index = 0; index < 1; ++index)
        check(world->tick(at_tree).changed, "P's native cut advances while the actor remains nearby.");
    const auto pending = world->snapshot();
    check(pending.state.manual_cuts.at("P").remaining_ticks == w::manual_cut_ticks - 1,
          "The native cut owns the remaining duration.");
    auto forged_pending = pending;
    forged_pending.state.manual_cuts.at("P").remaining_ticks = 0;
    check(!w::World::restore("harvest-world", profile, forged_pending),
          "A checkpoint cannot shorten an unfinished cut without trusted tick revisions.");
    forged_pending = pending;
    forged_pending.state.manual_cuts.at("P").interrupted_revision = pending.revision;
    check(!w::World::restore("harvest-world", profile, forged_pending),
          "A checkpoint cannot invent an interruption on a prior trusted cut tick.");
    auto saved = w::encode_checkpoint(profile, pending);
    check(std::holds_alternative<V>(saved), "An unfinished cut has a typed checkpoint.");
    auto decoded = w::decode_checkpoint(profile, "harvest-world", std::get<V>(saved));
    check(std::holds_alternative<w::Snapshot>(decoded), "The unfinished cut decodes without changing its timer.");
    auto resumed = w::World::restore("harvest-world", profile, std::get<w::Snapshot>(decoded));
    check(resumed && resumed->snapshot().state == pending.state,
          "A new World resumes exact cut identity and finite stock.");
    world = std::move(resumed);
    const w::ObserveActor moved = [](const std::string& actor) -> std::optional<a::ActorCut> {
        return a::ActorCut{actor, actor == "P" ? a::Point{20, 1, 20} : a::Point{4.95, 1, 4.95},
            4, true, 4};
    };
    check(world->tick(moved).changed &&
          world->snapshot().state.manual_cuts.at("P").interrupted_revision > 0,
          "A trusted out-of-reach actor sample interrupts the cut.");
    const auto late_finish = world->command({"P", "P-client"},
        finish("P", "P-client", "P-late-finish"), at_tree);
    check(late_finish.completed() && !std::get<bool>(late_finish.result->at("accepted").storage()) &&
          std::get<std::string>(late_finish.result->at("reason").storage()) == "cut_interrupted" &&
          world->snapshot().state.material.timber_remaining.at("tree-a") == 8,
          "Returning after interruption cannot release an uncut item.");
    saved = w::encode_checkpoint(profile, world->snapshot());
    check(std::holds_alternative<V>(saved) &&
          std::holds_alternative<w::Snapshot>(
              w::decode_checkpoint(profile, "harvest-world", std::get<V>(saved))),
          "The interruption itself survives a typed checkpoint.");
    const auto cancelled = world->command({"P", "P-client"},
        cancel("P", "P-client", "P-cancel"), {});
    check(cancelled.completed() && std::get<bool>(cancelled.result->at("accepted").storage()) &&
          world->snapshot().state.manual_cuts.empty(),
          "An interrupted actor can free the source without minting cargo.");
    const auto second = world->command({"Q", "Q-client"},
        command("Q", "Q-client", "Q-start", "tree-a"), at_tree);
    check(second.completed() && std::get<bool>(second.result->at("accepted").storage()),
          "Q can start after P releases the source.");
    for (I index = 0; index < w::manual_cut_ticks; ++index)
        check(world->tick(at_tree).changed, "Q completes its own native work time.");
    const auto contact = world->command({"Q", "Q-client"},
        finish("Q", "Q-client", "Q-contact"), at_tree);
    check(contact.completed() && std::get<bool>(contact.result->at("accepted").storage()) &&
          world->snapshot().state.material.timber_remaining.at("tree-a") == 7 &&
          world->snapshot().state.material.cargo.at("P").timber == 0 &&
          world->snapshot().state.material.cargo.at("Q").timber == 1,
          "Only Q receives the timber from its completed cut.");
    const auto final = world->snapshot();
    auto restored = w::World::restore("harvest-world", profile, final);
    check(restored && restored->snapshot().state == final.state,
          "Replay validates the interrupted P cut and completed Q cut.");
}
}  // namespace

int main() {
    try {
        harvest_and_restore();
        interrupted_cut_and_shared_source();
        std::cout << "harvest_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_world_test: " << error.what() << '\n';
        return 1;
    }
}
