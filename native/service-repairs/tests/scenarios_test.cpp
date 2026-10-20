#include "factory/service_scenarios.hpp"
#include "factory/repair_workbench.hpp"

#include <array>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace r = factory::service_scenarios;
namespace w = factory::world;
namespace a = factory::authority;
namespace s = factory::stationary;
namespace m = factory::materials;
using V = factory::values::Value;
using I = a::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

struct Fixture {
    std::string context;
    w::Profile profile;
    const r::Goal* goal;
    std::unique_ptr<w::World> simulation;
    I serial{};
};

a::Object send(Fixture& fixture, const char* action, a::Object arguments, a::Point position) {
    arguments.emplace("action", V(action));
    arguments.emplace("context", V(fixture.context));
    arguments.emplace("client", V("service-fixture"));
    arguments.emplace("actor", V("P"));
    arguments.emplace("request", V("action-" + std::to_string(++fixture.serial)));
    // Supplied native fixture cut, not actual body/Session movement evidence.
    const auto delivery = fixture.simulation->command({"P", "service-fixture"}, arguments,
        [position](const std::string& actor) -> std::optional<a::ActorCut> {
            return a::ActorCut{actor, position, 1, true, 4};
        });
    check(delivery.completed() && w::validate(fixture.profile, fixture.simulation->snapshot()),
          "Every original command result leaves the complete World valid and finite.");
    return *delivery.result;
}

bool accepted(const a::Object& outcome) { return std::get<bool>(outcome.at("accepted").storage()); }
std::string reason(const a::Object& outcome) { return std::get<std::string>(outcome.at("reason").storage()); }
a::Object target(const std::string& id, I generation = 1) { return {{"target", V(id)}, {"generation", V(generation)}}; }

const char* role(s::Role value) {
    return value == s::Role::collector ? "collector" : value == s::Role::belt ? "belt" : "processor";
}

void link(Fixture& fixture, const std::string& from, I from_generation, const std::string& to, I to_generation, a::Point position) {
    auto fields = target(from, from_generation);
    fields.emplace("to", V(to)); fields.emplace("to_generation", V(to_generation));
    check(accepted(send(fixture, "link", fields, position)), "Current canonical generations reconnect the real material handoff.");
}

a::Object place(Fixture& fixture, const factory::mechanics::Point& point, a::Point position) {
    return send(fixture, "place", {{"role", V(role(fixture.goal->role))},
        {"center", V(V::Array{V(point[0]), V(point[1]), V(point[2])})},
        {"axis", V("z")}, {"teeth", V(I{0})}, {"half_span", V(I{0})}}, position);
}

void ticks(Fixture& fixture) {
    check(fixture.simulation->tick().error == w::TransactionError::none &&
          w::validate(fixture.profile, fixture.simulation->snapshot()), "Each native tick preserves original material and finite parts.");
}

void native(const factory::repair_scenarios::Definition& definition, std::size_t site_index) {
    const auto content = r::make(definition.id);
    const auto* goal = r::goal(definition.id);
    check(content && content->definition == &definition && goal && goal->sites.size() == 2,
          "Each content entry supplies its explicit trusted two-site service goal.");
    const std::string context = std::string(definition.id) + '-' + std::to_string(site_index);
    Fixture fixture{context, content->profile, goal, w::World::create(context, content->profile, content->seed)};
    check(fixture.simulation && w::validate(fixture.profile, fixture.simulation->snapshot()), "Every service seed passes the actual World initializer.");
    check(!r::relocated(*goal, content->seed) && !r::ready(*goal, content->seed), "Original machinery cannot satisfy a replacement goal.");
    const I x = goal->role == s::Role::collector ? 0 : goal->role == s::Role::belt ? 3 : 6;
    const a::Point position{static_cast<double>(x), 0, 4};
    const std::string original(goal->original);
    const auto initial = fixture.simulation->snapshot().state.material;
    const auto occupied = send(fixture, "remove", target(original), position);
    check(!accepted(occupied) && reason(occupied) == "occupied_target" && fixture.simulation->snapshot().state.material == initial,
          "Occupied removal refuses without deleting a raw blank, product or ready whole lot.");
    const auto far = send(fixture, "recover", target(original), {100, 0, 100});
    check(!accepted(far) && reason(far) == "out_of_reach", "Remote recovery cannot bypass current physical reach admission.");
    check(accepted(send(fixture, "recover", target(original), position)), "Nearby recovery evacuates exactly the machine's actual contents.");
    const auto recovered = fixture.simulation->snapshot().state.material;
    check(recovered.stock.source == initial.stock.source && recovered.cargo.at("P").raw_units == 1,
          "Recovery preserves the remote finite source and carries the original raw blank.");
    if (goal->role == s::Role::processor)
        check(recovered.cargo.at("P").products == 1 && recovered.cargo.at("P").work_lots == std::vector<m::WorkLot>{{7, {1, 2}, 0}} &&
              !recovered.processing && recovered.next_work_id == 8,
              "The original ready billet, recipe, progress and serial survive whole-machine evacuation.");
    check(accepted(send(fixture, "remove", target(original), position)), "An evacuated machine can be removed while the drive remains enabled.");
    const s::PartSpec specification{goal->role, 0, 0};
    const auto removed = fixture.simulation->snapshot().state;
    check(removed.kits.at("P").at(specification) == 1 && removed.issued_entities.contains(original) &&
          removed.material == recovered && removed.topology.drive_enabled && !r::relocated(*goal, removed),
          "Removal refunds one original machine, preserves issued identity/custody and cannot itself count as relocation.");

    if (goal->role == s::Role::processor && site_index == 0) {
        const auto wrong = place(fixture, {6, 0, 4}, position);
        check(accepted(wrong) && !r::relocated(*goal, fixture.simulation->snapshot().state),
              "A fresh identity rebuilt at the old site does not satisfy the service layout.");
        check(accepted(send(fixture, "remove", target("native-part-1"), position)), "The empty wrong-site rebuild can be refunded for correction.");
    }
    const auto placed = place(fixture, goal->sites[site_index], position);
    check(accepted(placed), "The exact refunded starter machine can be placed at either service site.");
    const auto replacement = std::get<std::string>(placed.at("entity").storage());
    const auto generation = std::get<I>(placed.at("generation").storage());
    const auto rebuilt = fixture.simulation->snapshot().state;
    check(replacement != original && rebuilt.issued_entities.contains(original) && rebuilt.kits.at("P").at(specification) == 0 &&
          rebuilt.material == recovered && r::relocated(*goal, rebuilt) && !r::ready(*goal, rebuilt),
          "Canonical placement spends one refunded part and relocates it, but missing handoffs still prevent readiness.");
    auto stale_fields = target(original);
    stale_fields.emplace("amount", V(I{1}));
    const auto stale = send(fixture, "insert_raw", stale_fields, position);
    check(!accepted(stale) && reason(stale) == "unknown_target" && fixture.simulation->snapshot().state.material == recovered,
          "An old machine identity cannot insert into its replacement or consume the actor's blank.");

    if (goal->role == s::Role::collector) link(fixture, replacement, generation, "belt", 1, position);
    else if (goal->role == s::Role::belt) {
        link(fixture, "collector", 1, replacement, generation, position);
        link(fixture, replacement, generation, "processor", 1, position);
    } else link(fixture, "belt", 1, replacement, generation, position);
    if (goal->role == s::Role::processor) {
        auto work = target(replacement, generation); work.emplace("work_id", V(I{7}));
        check(accepted(send(fixture, "insert_work", work, position)), "The same ready lot can enter the current rebuilt press.");
        check(fixture.simulation->snapshot().state.material.processing == m::WorkLot{7, {1, 2}, 0},
              "Reinsertion preserves the original lot exactly instead of restarting processing.");
    }
    auto raw = target(replacement, generation); raw.emplace("amount", V(I{1}));
    check(accepted(send(fixture, "insert_raw", raw, position)) && r::ready(*goal, fixture.simulation->snapshot().state),
          "Returned raw material and real current handoffs restore the relocated powered line.");
    const std::string processor = goal->role == s::Role::processor ? replacement : "processor";
    const I processor_generation = goal->role == s::Role::processor ? generation : 1;
    for (int tick = 0; tick < 64 && fixture.simulation->snapshot().state.material.cargo.at("P").products < 4; ++tick) {
        if (fixture.simulation->snapshot().state.material.stock.output > 0) {
            auto collect = target(processor, processor_generation); collect.emplace("amount", V(I{1}));
            check(accepted(send(fixture, "collect", collect, {6, 0, 4})), "Actual current output can be collected through native admission.");
        }
        ticks(fixture);
    }
    const auto saved = fixture.simulation->snapshot();
    check(saved.state.material.cargo.at("P").products == 4 && saved.state.material.cargo.at("Q").products == 0 &&
          saved.state.material.initial_units == 16 && saved.state.material.stock.source < initial.stock.source && r::ready(*goal, saved.state),
          "Each service layout returns to real finite production, rather than winning by replacing stock or counting a rebuild alone.");
    auto resumed = w::World::restore(context, fixture.profile, saved);
    check(resumed && resumed->snapshot().state == saved.state && r::ready(*goal, resumed->snapshot().state),
          "The existing native snapshot boundary preserves service state; the goal is rederived rather than cached separately.");
}

struct Result { int code; std::string out, errors; };
Result run(std::string_view id, const std::string& commands) {
    const std::array<std::string_view, 2> arguments{"play", id};
    std::istringstream input(commands);
    std::ostringstream out, errors;
    const auto code = factory::repair_scenarios::workbench(arguments, input, out, errors);
    return {code, out.str(), errors.str()};
}

std::string plates(const std::string& processor, int count) {
    std::string result;
    for (int plate = 0; plate < count; ++plate) result += "wait 8\ncollect " + processor + '\n';
    return result;
}

void terminal() {
    const auto collector = run("service-collector", "walk north 4\nremove collector\nrecover collector\nremove collector\n"
        "place machine collector 0 0 3 z\nlink native-part-1 belt\ninsert_raw native-part-1 1\ninspect\nwalk east 4\n" + plates("processor", 4));
    check(collector.code == 0 && collector.errors.empty() && collector.out.find("Held: occupied_target") != std::string::npos,
          "The collector puzzle is playable through occupied refusal, custody, complete-machine construction and finite production.");
    const auto belt = run("service-belt", "walk north 4\nwalk east 3\nrecover belt\nremove belt\nplace machine belt 3 0 2 z\n"
        "link collector native-part-1\nlink native-part-1 processor\ninsert_raw belt 1\ninsert_raw native-part-1 1\n" + plates("processor", 4));
    check(belt.code == 0 && belt.errors.empty() && belt.out.find("No current part named belt.") != std::string::npos,
          "The belt puzzle requires the fresh current name and supports the alternate service site.");
    const auto press = run("service-press", "walk east 6\nwalk north 4\nrecover processor\nremove processor\n"
        "place machine processor 6 0 3 z\nlink belt native-part-1\ninsert_work native-part-1 7\ninsert_raw native-part-1 1\ninspect\n" + plates("native-part-1", 3));
    check(press.code == 0 && press.errors.empty() && press.out.find("Carried work=7 remaining=0 recipe_units=1 cycle=2") != std::string::npos &&
          press.out.find("Press work=7 remaining=0 recipe_units=1 cycle=2") != std::string::npos,
          "The terminal carries the same ready billet through an actual native rebuild and back to output.");
    for (const auto* result : {&collector, &belt, &press})
        check(result->out.find("Service drive and route: ready") != std::string::npos &&
              result->out.find("Complete: service relocation and four plates retrieved") != std::string::npos,
              "Completion requires the relocated powered route plus actual retrieved products.");

    const auto unreplaced = run("service-press", "walk east 6\nwalk north 4\ncollect processor\n" + plates("processor", 3));
    check(unreplaced.code == 1 && unreplaced.out.find("products=4/4") != std::string::npos &&
          unreplaced.out.find("Complete:") == std::string::npos,
          "Producing the plate count without the required service operation cannot complete the puzzle.");
    const auto unlinked = run("service-press", "walk east 6\nwalk north 4\ncollect processor\n" + plates("processor", 3) +
        "recover processor\nremove processor\nplace machine processor 6 0 3 z\n");
    check(unlinked.code == 1 && unlinked.out.find("Service relocation: complete") != std::string::npos &&
          unlinked.out.find("Complete:") == std::string::npos,
          "A stock-count success followed by an unconnected rebuild still cannot complete the service goal.");
    const auto incomplete = run("service-collector", "walk north 4\nrecover collector\nremove collector\n"
        "place machine collector 0 0 3 z\nlink native-part-1 belt\ninsert_raw native-part-1 1\n");
    check(incomplete.code == 1 && incomplete.out.find("Service drive and route: ready") != std::string::npos,
          "A correctly rebuilt route still needs its product objective.");
    const auto invalid = run("service-press", "place machine processor 6 0 3 q\nplace machine waterwheel 6 0 3 z\n"
        "place machine processor 6 0 9223372036854775808 z\ninspect\nquit\n");
    check(invalid.code == 1 && invalid.errors.empty() && invalid.out.find("Press work=7 remaining=0") != std::string::npos,
          "Malformed machine placement preserves original ready work and the ongoing puzzle.");
    const auto legacy_gear = run("gear-idler", "place gear 4 0 0 z 2\nwalk east 6\nwalk north 4\n" + plates("processor", 4));
    check(legacy_gear.code == 0 && legacy_gear.errors.empty(), "The unchanged gear-placement branch still solves its finite production puzzle.");
    std::istringstream input;
    std::ostringstream output, errors;
    const std::array<std::string_view, 1> list{"list"};
    check(factory::repair_scenarios::workbench(list, input, output, errors) == 0 &&
          output.str().find("service-press:") != std::string::npos && output.str().find("gear-riser:") != std::string::npos &&
          output.str().find("coupling:") != std::string::npos, "All three startup catalogues share the existing caller.");
}
}  // namespace

int main() {
    try {
        check(r::catalogue().size() == 3 && !r::goal("missing") && !r::make("missing") && !r::make("outlet"),
              "Service content has three explicit names and no silent default or reset path.");
        for (const auto& definition : r::catalogue()) for (std::size_t site = 0; site < 2; ++site) native(definition, site);
        terminal();
        std::cout << checks << " native service-repair checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
