#include "factory/service_scenarios.hpp"
#include "factory/repair_workbench.hpp"

#include <array>
#include <iostream>
#include <map>
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

a::Object recover_slot(Fixture& fixture, a::Point position) {
    auto fields = target("belt");
    fields.emplace("slot", V(I{0}));
    fields.emplace("expected", V(V::Object{{"raw", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(V::Array{})}}));
    return send(fixture, "recover_belt_slot", fields, position);
}

a::Object place(Fixture& fixture, const char* role, I x, I z, bool shaft, a::Point position) {
    return send(fixture, "place", {{"role", V(role)}, {"center", V(V::Array{V(x), V(I{0}), V(z)})},
        {"axis", V("z")}, {"teeth", V(I{0})}, {"half_span", V(shaft ? I{2} : I{0})}}, position);
}

void native(const factory::repair_scenarios::Definition& definition, std::size_t site_index) {
    const auto content = r::make(definition.id);
    const auto* goal = r::goal(definition.id);
    check(content && goal && goal->sites.size() == 2, "Each service challenge has two explicit relocation sites.");
    Fixture fixture{std::string(definition.id) + '-' + std::to_string(site_index), content->profile, goal,
                    w::World::create(std::string(definition.id) + '-' + std::to_string(site_index), content->profile, content->seed)};
    check(fixture.simulation && !r::relocated(*goal, content->seed) && !r::ready(*goal, content->seed),
          "The finite original line initializes without satisfying its relocation goal.");
    const a::Point old{6, 0, 8};
    const auto initial = fixture.simulation->snapshot().state.material;
    const bool belt_goal = goal->role == s::Role::belt;
    const std::string original(goal->original);
    const auto occupied = send(fixture, belt_goal ? "remove_belt_span" : "remove", target(original), old);
    check(!accepted(occupied) && reason(occupied) == "occupied_target" && fixture.simulation->snapshot().state.material == initial,
          "Occupied removal cannot discard original material or work.");
    const auto far = belt_goal ? recover_slot(fixture, {100, 0, 100}) : send(fixture, "recover", target(original), {100, 0, 100});
    check(!accepted(far) && reason(far) == "out_of_reach", "Remote recovery is refused without changing custody.");
    check(accepted(belt_goal ? recover_slot(fixture, old) : send(fixture, "recover", target(original), old)),
          "The original occupied target is recovered through World authority.");
    if (goal->role != s::Role::collector && initial.stock.collector)
        check(accepted(send(fixture, "recover", target("collector"), old)), "Recover the collector's original raw stock.");
    if (!belt_goal && initial.belt_lanes.at("belt").slots.front())
        check(accepted(recover_slot(fixture, old)), "Recover the original belt slot without deleting its item.");
    if (goal->role != s::Role::processor && (initial.stock.input || initial.stock.output || initial.processing))
        check(accepted(send(fixture, "recover", target("processor"), old)), "Recover the original processor contents.");
    const auto held = fixture.simulation->snapshot().state.material;
    if (goal->role == s::Role::processor)
        check(held.cargo.at("P").work_lots == std::vector<m::WorkLot>{{7, {1, 2}, 0}} && held.cargo.at("P").products == 1,
              "Recovery retains the exact ready work and finished plate.");
    check(accepted(send(fixture, "remove", target("collector"), old)) &&
          accepted(send(fixture, "remove_belt_span", target("belt"), old)) &&
          accepted(send(fixture, "remove", target("processor"), old)),
          "The evacuated machines and span are refunded without discarding material.");
    const auto removed = fixture.simulation->snapshot().state;
    auto held_without_lane = held; held_without_lane.belt_lanes.clear();
    check(removed.material == held_without_lane && removed.issued_entities.contains(original) && !r::relocated(*goal, removed),
          "Old identities and full custody survive removal without claiming relocation.");
    const I row = site_index == 0 ? -4 : 4;
    const a::Point at{static_cast<double>(row + 6), 0, 12};
    const auto collector = place(fixture, "collector", row, 12, false, at);
    const auto press = place(fixture, "processor", row + 12, 12, false, at);
    const auto first = place(fixture, "shaft", row + 4, 12, true, at);
    const auto last = place(fixture, "shaft", row + 8, 12, true, at);
    check(accepted(collector) && accepted(press) && accepted(first) && accepted(last),
          "The refunded machines and carried one-tile shafts build at the selected service row.");
    const auto name = [](const a::Object& object) { return std::get<std::string>(object.at("entity").storage()); };
    const auto generation = [](const a::Object& object) { return std::get<I>(object.at("generation").storage()); };
    check(!r::ready(*goal, fixture.simulation->snapshot().state), "Machines without a belt cannot satisfy the service goal.");
    auto connect = target(name(first), generation(first));
    connect.emplace("to", V(name(last))); connect.emplace("to_generation", V(generation(last)));
    const auto span = send(fixture, "place_belt_span", connect, at);
    check(accepted(span) && r::relocated(*goal, fixture.simulation->snapshot().state) && r::ready(*goal, fixture.simulation->snapshot().state),
          "The current geometric span and powered endpoints complete the selected service relocation.");
    auto raw = target(name(collector), generation(collector)); raw.emplace("amount", V(I{1}));
    check(accepted(send(fixture, "insert_raw", raw, at)), "Return an original blank to the rebuilt collector.");
    if (goal->role == s::Role::processor) {
        auto work = target(name(press), generation(press)); work.emplace("work_id", V(I{7}));
        check(accepted(send(fixture, "insert_work", work, at)) &&
              fixture.simulation->snapshot().state.material.processing == m::WorkLot{7, {1, 2}, 0},
              "The same original ready billet enters the replacement press.");
    }
    for (int tick = 0; tick < 64 && fixture.simulation->snapshot().state.material.cargo.at("P").products < 4; ++tick) {
        if (fixture.simulation->snapshot().state.material.stock.output > 0) {
            auto collect = target(name(press), generation(press)); collect.emplace("amount", V(I{1}));
            check(accepted(send(fixture, "collect", collect, at)), "Collect actual output from the replacement press.");
        }
        check(fixture.simulation->tick().error == w::TransactionError::none, "The service World advances finite production.");
    }
    const auto saved = fixture.simulation->snapshot();
    check(saved.state.material.cargo.at("P").products == 4 && saved.state.material.initial_units == 16 &&
          saved.state.material.stock.source < initial.stock.source && r::ready(*goal, saved.state),
          "The selected service route produces four real plates from the original finite stock.");
    auto restored = w::World::restore(fixture.context, fixture.profile, saved);
    check(restored && restored->snapshot().state == saved.state && r::ready(*goal, restored->snapshot().state),
          "The service state and derived goal survive native snapshot continuation.");
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
    const std::string setup = "walk north 8\nwalk east 4\nrecover collector\nremove collector\nremove_belt belt\n"
        "remove processor\nplace machine collector -4 0 12 z\nplace machine processor 8 0 12 z\n"
        "place shaft 0 0 12 z 2\nplace shaft 4 0 12 z 2\nbelt native-part-3 native-part-4\n"
        "insert_raw native-part-1 1\ninspect\n";
    const auto collector = run("service-collector", setup + plates("native-part-2", 4));
    if (collector.code != 0) std::cerr << collector.out << collector.errors;
    check(collector.code == 0 && collector.errors.empty() && collector.out.find("Service drive and route: ready") != std::string::npos,
          "Terminal commands rebuild a physical service span and retrieve four plates.");
    const auto belt = run("service-belt", "recover_belt belt 0\n" + setup + plates("native-part-2", 4));
    if (belt.code != 0) std::cerr << belt.out << belt.errors;
    check(belt.code == 0 && belt.errors.empty() && belt.out.find("Complete: service relocation and four plates retrieved") != std::string::npos,
          "The terminal recovers the belt slot and completes the physical belt relocation.");
    const auto press = run("service-press", "walk north 8\nwalk east 4\nrecover_belt belt 0\nrecover processor\n" +
        setup.substr(std::string("walk north 8\nwalk east 4\n").size()) +
        "insert_work native-part-2 7\n" + plates("native-part-2", 3));
    if (press.code != 0) std::cerr << press.out << press.errors;
    check(press.code == 0 && press.errors.empty() && press.out.find("Press work=7 remaining=0") != std::string::npos,
          "The terminal preserves the original ready billet through a complete press relocation.");
    const auto incomplete = run("service-collector", setup);
    check(incomplete.code == 1 && incomplete.out.find("Service drive and route: ready") != std::string::npos,
          "A ready relocated route still requires its product objective.");
    const auto invalid = run("service-press", "place machine processor 6 0 3 q\ninspect\nquit\n");
    check(invalid.code == 1 && invalid.errors.empty() && invalid.out.find("Press work=7 remaining=0") != std::string::npos,
          "Malformed construction preserves the original waiting work.");
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
