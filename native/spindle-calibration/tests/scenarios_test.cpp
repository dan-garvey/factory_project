#include "factory/spindle_scenarios.hpp"
#include "factory/repair_workbench.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace c = factory::spindle_scenarios;
namespace w = factory::world;
namespace s = factory::stationary;
namespace g = factory::mechanics;
namespace a = factory::authority;
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
    std::unique_ptr<w::World> world;
    I request{};
};
void conserved(const Fixture& fixture) {
    const auto cut = fixture.world->snapshot();
    check(w::validate(fixture.profile, cut), "The sole World validates material, finite parts, identities and request history.");
    auto totals = fixture.profile.finite_parts;
    for (auto& [spec, count] : totals) { (void)spec; count = 0; }
    for (const auto& part : cut.state.topology.parts) ++totals.at({part.role, part.geometry.teeth, part.geometry.half_span});
    for (const auto& span : cut.state.topology.belt_spans) { (void)span; ++totals.at({s::Role::belt, 0, 0}); }
    for (const auto& [actor, kit] : cut.state.kits) {
        (void)actor;
        for (const auto& [spec, count] : kit) totals.at(spec) += count;
    }
    check(totals == fixture.profile.finite_parts && cut.state.material.initial_units == 16,
          "Every original part and all sixteen material units retain their canonical owner.");
}
Fixture fresh(const char* suffix, bool missing_link = false) {
    auto content = c::make("spindle");
    check(content && content->definition == &c::definition(), "Only the explicit trusted spindle startup is selected.");
    if (missing_link) {
        content->seed.topology.belt_spans.clear();
        content->seed.material.belt_lanes.clear();
        content->seed.issued_entities.erase("belt");
        content->seed.kits.at("P").emplace(s::PartSpec{s::Role::belt, 0, 0}, 1);
    }
    std::string context = std::string("spindle-") + suffix;
    Fixture fixture{context, content->profile, w::World::create(context, content->profile, content->seed)};
    check(fixture.world != nullptr, "The real World accepts the authored two-plane finite seed.");
    conserved(fixture);
    I parts{};
    for (const auto& [spec, count] : fixture.profile.finite_parts) { (void)spec; parts += count; }
    const auto state = fixture.world->snapshot().state;
    check(parts == 17 && state.topology.sources.size() == 1 && state.material.stock.source == 16 &&
          state.kits.at("P").at({s::Role::gear, 2, 0}) == 2 && state.kits.at("P").at({s::Role::shaft, 0, 2}) == 1 &&
          state.kits.at("Q").empty() && c::inspect(state).mode == c::Mode::incomplete_line,
          "Seventeen exact original parts, sixteen blanks and one source begin without a powered output train.");
    return fixture;
}
bool accepted(const a::Object& result) { return std::get<bool>(result.at("accepted").storage()); }
a::Object send(Fixture& fixture, a::Object intent, a::Point position) {
    intent.emplace("context", V(fixture.context)); intent.emplace("actor", V("P"));
    intent.emplace("client", V("spindle-fixture")); intent.emplace("request", V("action-" + std::to_string(++fixture.request)));
    const auto delivery = fixture.world->command({"P", "spindle-fixture"}, intent,
        [position](const std::string& actor) -> std::optional<a::ActorCut> {
            // Supplied native observation, not a body/Session movement witness.
            return a::ActorCut{actor, position, 1, true, 4};
        });
    check(delivery.completed(), "An actual World command returns its original accepted or refused outcome.");
    conserved(fixture);
    return *delivery.result;
}
a::Object place(Fixture& fixture, g::Point center, bool shaft, I dimension, a::Point position) {
    return send(fixture, {{"action", V("place")}, {"role", V(shaft ? "shaft" : "gear")},
        {"center", V(V::Array{V(center[0]), V(center[1]), V(center[2])})}, {"axis", V("z")},
        {"teeth", V(shaft ? I{0} : dimension)}, {"half_span", V(shaft ? dimension : I{0})}}, position);
}
a::Object remove(Fixture& fixture, const std::string& id, a::Point position) {
    const auto state = fixture.world->snapshot().state;
    const auto found = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [&](const auto& part) { return part.geometry.id == id; });
    check(found != state.topology.parts.end(), "Removal selects a current identity and generation.");
    return send(fixture, {{"action", V("remove")}, {"target", V(id)}, {"generation", V(found->generation)}}, position);
}
void ticks(Fixture& fixture, int count) {
    for (int n = 0; n < count; ++n) {
        check(fixture.world->tick().error == w::TransactionError::none, "Only the owning World advances its real finite production.");
        conserved(fixture);
    }
}
void restore(Fixture& fixture) {
    const auto cut = fixture.world->snapshot();
    auto next = w::World::restore(fixture.context, fixture.profile, cut);
    check(next != nullptr, "A fresh native World accepts the typed retained cut.");
    const auto restored = next->snapshot();
    check(restored.state == cut.state && restored.revision == cut.revision && restored.history.context == cut.history.context &&
          restored.history.order == cut.history.order && restored.history.records.size() == cut.history.records.size(),
          "Typed restore retains the full current state, revision and ordered historical context.");
    for (std::size_t n = 0; n < cut.history.records.size(); ++n)
        check(!factory::values::typed_difference(V(cut.history.records[n].intent), V(restored.history.records[n].intent)) &&
              !factory::values::typed_difference(V(cut.history.records[n].result), V(restored.history.records[n].result)),
              "Every original intent and outcome retains exact scalar types through native continuation.");
    fixture.world = std::move(next);  // Same fixture host retains its request counter.
}
void produce(Fixture& fixture) {
    for (int n = 0; n < 64 && fixture.world->snapshot().state.material.cargo.at("P").products < 4; ++n) {
        if (fixture.world->snapshot().state.material.stock.output > 0)
            check(accepted(send(fixture, {{"action", V("collect")}, {"target", V("processor")},
                {"generation", V(I{1})}, {"amount", V(I{1})}}, {16, 0, 4})), "A nearby actor collects one original-stock plate into individual cargo.");
        ticks(fixture, 1);
    }
    const auto state = fixture.world->snapshot().state;
    check(state.material.cargo.at("P").products == 4 && state.material.cargo.at("Q").products == 0 && state.material.stock.source < 16,
          "Four actual plates belong to P and consume original material, independent of the calibration goal.");
}
std::string bridge(Fixture& fixture, bool reverse = false) {
    const I first = reverse ? 0 : -8;
    const I last = reverse ? -8 : 0;
    auto result = place(fixture, {4, 4, first}, false, 2, {4, 0, static_cast<double>(first)});
    check(accepted(result), "A carried small cog is reachable at the ground-observation reach boundary.");
    const auto first_id = std::get<std::string>(result.at("entity").storage());
    check(accepted(place(fixture, {4, 4, -4}, true, 2, {4, 0, -4})), "The one-tile shaft joins both axial gear planes.");
    check(!c::inspect(fixture.world->snapshot().state).ready(), "A partial bridge cannot satisfy a powered-line specification.");
    check(accepted(place(fixture, {4, 4, last}, false, 2, {4, 0, static_cast<double>(last)})),
          "The final original cog completes the geometric bridge in either construction order.");
    const auto state = fixture.world->snapshot().state;
    const auto motion = s::power_view(state.topology).mechanical.motion;
    check(motion.at(first_id).rate == g::Rate{-2, 1} && motion.at("processor").rate == g::Rate{-2, 1},
          "Literal exact gear rates are minus two on both the bridge and output spindle.");
    return first_id;
}
void wrong_rate_correction() {
    auto fixture = fresh("shortcut");
    const auto material = fixture.world->snapshot().state.material;
    ticks(fixture, 8);
    check(fixture.world->snapshot().state.material == material, "Waiting cannot feed a disconnected initial collector.");
    const auto before = fixture.world->snapshot().state;
    const auto far = place(fixture, {4, 4, -8}, false, 2, {100, 0, 0});
    check(!accepted(far) && std::get<std::string>(far.at("reason").storage()) == "out_of_reach" && fixture.world->snapshot().state == before,
          "A remote placement refuses without spending a cog or allocating an identity.");
    const auto wrong = place(fixture, {0, 0, -4}, false, 2, {0, 0, -4});
    const auto wrong_end = place(fixture, {0, 0, 0}, false, 2, {0, 0, 0});
    check(accepted(wrong) && accepted(wrong_end), "The tempting coaxial and small-cog shortcut is legal finite construction.");
    const auto wrong_id = std::get<std::string>(wrong.at("entity").storage());
    const auto wrong_end_id = std::get<std::string>(wrong_end.at("entity").storage());
    check(c::inspect(fixture.world->snapshot().state).rate == g::Rate{1, 1}, "The shortcut has the literal positive-one rate.");
    ticks(fixture, 8);
    auto state = fixture.world->snapshot().state;
    check(c::inspect(state).mode == c::Mode::wrong_rate && !c::inspect(state).complete() &&
          std::any_of(state.material.belt_lanes.begin()->second.slots.begin(), state.material.belt_lanes.begin()->second.slots.end(),
                      [](const auto& item) { return item.has_value(); }) && state.material.stock.output == 0,
          "The wrong signed rate reverses the belt and leaves recoverable blanks, rather than producing plates.");
    const auto retained = state.material;
    restore(fixture);
    check(accepted(remove(fixture, wrong_id, {0, 0, -4})) && accepted(remove(fixture, wrong_end_id, {0, 0, 0})),
          "Both wrong-rate cogs can be refunded without erasing retained material.");
    bridge(fixture);
    state = fixture.world->snapshot().state;
    check(state.material == retained && state.issued_entities.contains(wrong_id) && c::inspect(state).ready(),
          "Same-run correction changes only geometry and preserves retained material and issued identities.");
    produce(fixture);
    state = fixture.world->snapshot().state;
    check(c::inspect(state).complete(), "The forward calibrated line produces four plates.");
    const auto completed = state.material;
    const auto cut = fixture.world->snapshot();
    check(!c::inspect(cut.state, "Q").complete() && !c::inspect(cut.state, "missing").known_actor &&
          fixture.world->snapshot().state == cut.state && fixture.world->snapshot().history.order == cut.history.order,
          "Read-only calibration cannot borrow P's credit or mutate the World/history.");
    const auto off = send(fixture, {{"action", V("set_drive")}, {"target", V("wheel")},
        {"generation", V(I{1})}, {"enabled", V(false)}}, {0, 0, -12});
    check(accepted(off) && c::inspect(fixture.world->snapshot().state).mode == c::Mode::drive_off &&
          !c::inspect(fixture.world->snapshot().state).complete() && fixture.world->snapshot().state.material == completed,
          "A satisfied inventory cannot cache readiness after the current drive stops.");
}
void partial_work_and_links() {
    auto fixture = fresh("partial");
    const auto cog = bridge(fixture, true);
    check(c::inspect(fixture.world->snapshot().state).ready(), "The reverse build order reaches the same current spindle specification.");
    for (int n = 0; n < 16; ++n) {
        const auto work = fixture.world->snapshot().state.material.processing;
        if (work && work->remaining_ticks > 0 && work->remaining_ticks < work->recipe.cycle_ticks) break;
        ticks(fixture, 1);
    }
    const auto partial = fixture.world->snapshot().state.material;
    check(partial.processing && partial.processing->remaining_ticks > 0 &&
          partial.processing->remaining_ticks < partial.processing->recipe.cycle_ticks,
          "The native continuation cut contains original positively progressed work.");
    restore(fixture);
    check(accepted(remove(fixture, cog, {4, 0, 0})), "A bridge cog can be serviced while preserving partial production.");
    ticks(fixture, 4);
    check(fixture.world->snapshot().state.material == partial && !c::inspect(fixture.world->snapshot().state).ready(),
          "Disconnected work pauses without material loss, renaming or progress reset.");
    check(accepted(place(fixture, {4, 4, 0}, false, 2, {4, 0, 0})), "The refunded cog restores the original powered line.");
    produce(fixture);
    check(c::inspect(fixture.world->snapshot().state).complete(), "The repaired partial run reaches the original four-plate goal.");

    auto disconnected = fresh("handoff", true);
    bridge(disconnected);
    check(!c::inspect(disconnected.world->snapshot().state).ready(), "Correct mechanical rate alone cannot hide an absent material handoff.");
    check(accepted(send(disconnected, {{"action", V("place_belt_span")}, {"target", V("pulley-first")}, {"generation", V(I{1})},
        {"to", V("pulley-last")}, {"to_generation", V(I{1})}}, {10, 0, 4})), "Current shafts restore the physical handoff through World.");
    check(c::inspect(disconnected.world->snapshot().state).ready(), "Readiness derives the repaired current link without a progress flag.");
}
void terminal() {
    const std::string bridge_commands = "walk east 4\nwalk south 8\nplace gear 4 4 -8 z 2\nwalk north 4\nplace shaft 4 4 -4 z 2\nwalk north 4\nplace gear 4 4 0 z 2\n";
    const std::string collect = "wait 8\ncollect processor\nwait 8\ncollect processor\nwait 8\ncollect processor\nwait 8\ncollect processor\n";
    auto run = [](const std::string& commands, int expected, const std::string& marker) {
        const std::array<std::string_view, 2> args{"play", "spindle"};
        std::istringstream input(commands); std::ostringstream output, errors;
        const auto code = factory::repair_scenarios::workbench(args, input, output, errors);
        if (code != expected || !errors.str().empty() || output.str().find(marker) == std::string::npos)
            throw std::runtime_error("Terminal expected " + marker + ", code " + std::to_string(expected) +
                                     "; got code " + std::to_string(code) + ": " + errors.str() + output.str());
        ++checks;
        return output.str();
    };
    run("place gear 4 4 -8 z 2\n" + bridge_commands + "walk east 8\nwalk north 4\n" + collect, 0, "Complete: spindle calibrated and four plates retrieved");
    const std::string wrong = "walk south 4\nplace gear 0 0 -4 z 2\nwalk north 4\nplace gear 0 0 0 z 2\nwalk east 6\nwalk north 4\nwait 8\n";
    run(wrong + "inspect\nquit\n", 1, "Spindle: wrong_rate rate=1/1");
    const auto recovered = run(wrong + "recover_belt belt 0\ninspect\nquit\n", 1, "products=0/4");
    const auto last_cargo = recovered.rfind("Cargo raw=");
    check(last_cargo != std::string::npos && recovered.compare(last_cargo, 12, "Cargo raw=0 ") != 0,
          "The terminal belt recovery moves the retained blank into the actor's cargo.");
    const auto corrected = run(wrong + "walk west 6\nwalk south 4\nremove native-part-2\nremove native-part-1\n" + bridge_commands +
        "walk east 8\nwalk north 4\n" + collect, 0, "Accepted: ok (native-part-5)");
    check(corrected.find("Cargo raw=0 products=4/4") != std::string::npos && corrected.find("Spindle: calibrated rate=-2/1") != std::string::npos,
          "The same terminal run produces plates after correcting the bridge.");
    run("wait 32\nreset\nplace gear 4 4 0 q 2\ninspect\nquit\n", 1, "Stock source=16 collector=0 belt=0 input=0 output=0");
    run(bridge_commands + "quit\n", 1, "Spindle: calibrated rate=-2/1");
}
}  // namespace

int main() {
    try {
        check(c::catalogue().size() == 1 && !c::make("missing") && !c::make("co-drive"), "The new initializer never substitutes another challenge.");
        wrong_rate_correction(); partial_work_and_links(); terminal();
        std::cout << checks << " native spindle-calibration checks, 0 failures; engine_calls=0, physical_producers=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n'; return 1;
    }
}
