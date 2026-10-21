#include "factory/opening_engineering.hpp"

#include <iostream>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>

namespace e = factory::opening_engineering;
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
namespace {
int checks{};
void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class T> const T& field(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}
bool accepted(const V& value) { return field<bool>(value, "accepted"); }
bool same(const V& a, const V& b) { return !factory::values::typed_difference(a, b); }

void conserved(const Host& host) {
    const auto projection = host.projection();
    I total{};
    const auto stock = field<O>(projection, "stock");
    for (const auto* name : {"source", "collector", "belt", "input", "held", "output", "player"})
        total += std::get<I>(stock.at(name).storage());
    for (const auto& [id, cargo] : field<O>(projection, "cargo")) {
        (void)id;
        total += field<I>(cargo, "raw");
        for (const auto& lot : field<A>(cargo, "work_lots")) total += field<I>(lot, "recipe_input");
    }
    for (const auto& cargo : field<A>(projection, "dropped_material")) total += field<I>(cargo, "raw");
    for (const auto& [id, span] : field<O>(projection, "belt_spans")) {
        (void)id;
        for (const auto& cargo : field<A>(span, "slots"))
            if (cargo.type() != factory::values::Type::null) total += field<I>(cargo, "raw");
    }
    check(total == field<I>(projection, "initial_feed"), "Live, held, dropped and in-flight material stays conserved.");
    std::map<std::string, I> parts{{"collector", 0}, {"belt", 0}, {"processor", 0}, {"wheel", 0},
                                   {"shaft", 0}, {"gear", 0}, {"foundation", 0}};
    for (const auto& [actor, kit] : field<O>(projection, "part_kits")) {
        (void)actor;
        for (const auto& [kind, count] : std::get<O>(kit.storage())) parts.at(kind) += std::get<I>(count.storage());
    }
    for (const auto* group : {"entities", "transmission_parts"})
        for (const auto& [id, part] : field<O>(projection, group)) { (void)id; ++parts.at(field<std::string>(part, "kind")); }
    parts.at("belt") += static_cast<I>(field<O>(projection, "belt_spans").size());
    parts.at("foundation") += static_cast<I>(field<O>(projection, "foundations").size());
    check(parts == std::map<std::string, I>{{"collector", 1}, {"belt", 2}, {"processor", 1}, {"wheel", 1},
                                            {"shaft", 8}, {"gear", 10}, {"foundation", 24}},
          "The real finite construction kit is conserved across placed spans and player inventories.");
}

// Invented channel and actor observations; no game or desktop is run.
O stream_site(bool reverse = false, I speed = 200) {
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)}, heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    const I current = reverse ? -speed : speed;
    return {{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})},
            {"water", V(A{V(A{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{0}), V(current)}),
                          V(A{V(I{-8}), V(I{4}), V(I{-20}), V(I{-400}), V(I{0}), V(current)}),
                          V(A{V(I{-8}), V(I{-4}), V(I{-20}), V(I{-400}), V(I{0}), V(current)})})}};
}

struct Run {
    Host host;
    std::string prefix;
    I serial{}, epoch{};
    bool reverse{};
    Run(std::string name, bool reversed = false, const std::optional<V>& saved = std::nullopt, I speed = 200)
        : prefix(std::move(name)), reverse(reversed) {
        check(accepted(host.initialize("upstream-drive", {"P", "Q"})), "The real finite Host initializes.");
        check(accepted(host.configure_terrain(stream_site(reverse, speed))), "The fixture binds its invented channel.");
        if (saved) check(accepted(host.restore_checkpoint(*saved)), "A fresh Host restores the retained checkpoint.");
    }
    void at(double x, double z, double y = 1.0) {
        check(accepted(host.publish_actor("P", {V(x), V(y), V(z)}, ++epoch)), "Synthetic actor observation is accepted.");
    }
    V action(const char* name, O args = {}) {
        args.emplace("context", V("upstream-drive")); args.emplace("client", V("P"));
        args.emplace("request", V(prefix + '-' + std::to_string(++serial))); args.emplace("action", V(name));
        auto result = host.command("P", args);
        check(accepted(result), std::string(name) + " succeeds: " + field<std::string>(result, "reason"));
        return result;
    }
    std::string place(const char* kind, I x, I row, const char* axis) {
        return field<std::string>(action("place", {{"kind", V(kind)}, {"cell", V(A{V(x), V(row)})},
                                                    {"axis", V(axis)}, {"level", V(I{4})}}), "entity");
    }
    void foundation(I x, I row) {
        (void)action("place_foundation", {{"cell", V(A{V(x), V(row)})}, {"level", V(I{4})}});
    }
    void gear(I x, I z, const char* axis, I teeth, I height = 4) {
        (void)action("place_gear", {{"center", V(A{V(x), V(height), V(z)})}, {"axis", V(axis)}, {"teeth", V(teeth)}});
    }
    std::string shaft(I x, I z, const char* axis = "z", I height = 4) {
        return field<std::string>(action("place_shaft", {{"center", V(A{V(x), V(height), V(z)})},
                                                          {"axis", V(axis)}, {"half_span", V(I{2})}}), "entity");
    }
    void span(const std::string& first, const std::string& last) {
        (void)action("place_belt_span", {{"from", V(first)}, {"to", V(last)}});
    }
};

std::string build(Run& run, I wheel_row, bool install_span = true, bool two_spans = false, int fork_order = 0, bool moving_fork = false, bool inclined_fork = false, bool collector_after_fork = false) {
    const I offset = wheel_row * 4;
    const double dz = wheel_row * 1.65;
    const I press_x = two_spans ? 20 : 12;
    run.at(-1.65, 3.3 + dz); (void)run.place("wheel", -2, wheel_row, "x");
    run.at(0, dz); run.foundation(0, wheel_row + 1);
    if (!collector_after_fork) (void)run.place("collector", 0, wheel_row + 1, "z");
    run.at(-3.3, dz); run.gear(-4, offset, "x", 4);
    run.at(-3.3, -1.65 + dz); run.gear(0, offset - 4, "z", 4);
    const A front = two_spans ? A{V(I{0}), V(I{4}), V(I{12})} : A{V(I{0}), V(I{4})};
    const A rear = two_spans ? A{V(I{4}), V(I{8}), V(I{12}), V(I{16}), V(I{20})} : A{V(I{4}), V(I{8}), V(I{12})};
    for (const auto& value : front) {
        const auto x = std::get<I>(value.storage()); run.at(x * 1.65 / 4, -3.3 + dz); run.gear(x, offset, "z", 2);
    }
    for (const auto& value : rear) {
        const auto x = std::get<I>(value.storage()); run.at(x * 1.65 / 4, -3.3 + dz); run.gear(x, offset - 4, "z", 2);
    }
    run.at(press_x * 1.65 / 4, -3.3 + dz); (void)run.shaft(press_x, offset);
    run.at(1.65, dz); const auto first = run.shaft(4, offset + 4);
    run.at(3.3, dz); const auto last = run.shaft(8, offset + 4);
    const auto fork = [&] {
        if (moving_fork) {
            run.at(-3.3, 1.65 + dz); run.gear(-4, offset + 4, "x", 2, 8);
            run.at(-3.3, 3.3 + dz); run.gear(-4, offset + 8, "x", 2, 8);
            if (!inclined_fork) run.gear(-4, offset + 8, "x", 2);
        }
        run.at(-1.65, 3.3 + dz, inclined_fork ? 3.3 : 1.0); const auto a = run.shaft(0, offset + 8, "x", inclined_fork ? 8 : 4);
        run.at(-1.65, 4.95 + dz, inclined_fork ? 4.95 : 1.0); const auto b = run.shaft(0, offset + 12, "x", inclined_fork ? 12 : 4);
        run.at(-1.65, 4.125 + dz, inclined_fork ? 4.125 : 1.0);
        if (inclined_fork && collector_after_fork) run.span(b, a);
        else run.span(a, b);
    };
    if (fork_order == 1) fork();
    if (install_span) { run.at(2.475, dz); run.span(first, last); }
    if (fork_order == 2) fork();
    if (collector_after_fork) { run.at(0, dz); (void)run.place("collector", 0, wheel_row + 1, "z"); }
    if (two_spans) {
        run.at(4.95, dz); const auto next = run.shaft(12, offset + 4);
        run.at(6.6, dz); const auto end = run.shaft(16, offset + 4);
        run.at(5.775, dz); run.span(next, end);
    }
    run.at(press_x * 1.65 / 4, dz); run.foundation(press_x / 4, wheel_row + 1);
    const auto press = run.place("processor", press_x / 4, wheel_row + 1, "z");
    run.at(-1.65, dz); (void)run.action("set_power", {{"active", V(true)}});
    return press;
}

void forward_and_checkpoint(bool two_spans) {
    Run run(two_spans ? "two" : "one");
    check(e::inspect(run.host, "missing").phase == e::Phase::unavailable, "Unknown actors cannot claim progress.");
    check(e::inspect(run.host, "P").phase == e::Phase::first_shift, "Fresh progress starts at the first shift.");
    const auto press = build(run, 0, true, two_spans);
    const auto drive = e::inspect(run.host, "P");
    check(drive.source_at_target && drive.machines_running && drive.belt_forward,
          "A connected, powered span route is forward and both machines run.");
    // Use the actual processor position for retrieval on both layouts.
    for (int turn = 0; turn < 300 && e::inspect(run.host, "P").products < 4; ++turn) {
        const auto stock = field<O>(run.host.projection(), "stock");
        if (std::get<I>(stock.at("output").storage()) > 0) {
            run.at(two_spans ? 8.25 : 4.95, 1.65);
            (void)run.action("retrieve", {{"entity", V(press)}, {"amount", V(I{1})}});
        } else (void)run.host.advance();
    }
    check(e::inspect(run.host, "P").products == 4 && e::inspect(run.host, "P").phase == e::Phase::deliver_more,
          "Four real plates at the upstream source require four more.");
    const auto saved = run.host.checkpoint();
    check(accepted(run.host.validate_checkpoint(saved)), "The actual route checkpoint validates.");
    Run resumed(two_spans ? "two-resume" : "one-resume", false, saved);
    check(same(saved, resumed.host.checkpoint()) && e::inspect(resumed.host, "P").phase == e::Phase::deliver_more,
          "Restoring preserves the complete state and derives the same progress.");
    for (int turn = 0; turn < 300 && e::inspect(resumed.host, "P").products < 8; ++turn) {
        const auto stock = field<O>(resumed.host.projection(), "stock");
        if (std::get<I>(stock.at("output").storage()) > 0) {
            resumed.at(two_spans ? 8.25 : 4.95, 1.65);
            (void)resumed.action("retrieve", {{"entity", V(press)}, {"amount", V(I{1})}});
        } else (void)resumed.host.advance();
    }
    check(e::inspect(resumed.host, "P").products == 8 && e::inspect(resumed.host, "P").phase == e::Phase::ready,
          "Eight actual plates and the current route satisfy the challenge.");
    conserved(resumed.host);
    check(e::inspect(resumed.host, "Q").phase == e::Phase::first_shift, "The other actor does not receive P's products.");
    const auto before = resumed.host.checkpoint(); (void)e::inspect(resumed.host, "P");
    check(same(before, resumed.host.checkpoint()), "Inspection neither advances nor mutates the World.");
    resumed.at(-1.65, 0); (void)resumed.action("set_power", {{"active", V(false)}});
    check(e::inspect(resumed.host, "P").phase == e::Phase::restore_drive && !e::inspect(resumed.host, "P").belt_forward,
          "Stopping the drive invalidates current readiness without consuming products.");
}

void negative_routes() {
    Run disconnected("disconnected");
    (void)build(disconnected, 0, false);
    const auto absent = e::inspect(disconnected.host, "P");
    check(absent.machines_running && !absent.belt_forward, "Running machines with no connecting span do not form a route.");
    Run reversed("reverse", true);
    (void)build(reversed, 0);
    const auto backwards = e::inspect(reversed.host, "P");
    check(backwards.machines_running && !backwards.belt_forward, "A powered span carrying away from the press is not forward.");
}

void wrong_source() {
    Run run("wrong-source");
    const auto press = build(run, 0);
    for (int turn = 0; turn < 300 && e::inspect(run.host, "P").products < 4; ++turn) {
        const auto stock = field<O>(run.host.projection(), "stock");
        if (std::get<I>(stock.at("output").storage()) > 0) {
            run.at(4.95, 1.65); (void)run.action("retrieve", {{"entity", V(press)}, {"amount", V(I{1})}});
        } else (void)run.host.advance();
    }
    const auto entities = field<O>(run.host.projection(), "entities");
    std::string wheel;
    for (const auto& [id, part] : entities) if (field<std::string>(part, "kind") == "wheel") wheel = id;
    check(!wheel.empty(), "The constructed wheel is present.");
    run.at(-1.65, 0); (void)run.action("remove", {{"entity", V(wheel)}});
    run.at(-1.65, 4.95); (void)run.place("wheel", -2, 1, "x");
    const auto progress = e::inspect(run.host, "P");
    check(progress.products == 4 && !progress.source_at_target && progress.phase == e::Phase::move_source,
          "Moving the wheel away after four plates requires returning it to the target.");
}

void relocate_stocked_line() {
    Run run("relocate");
    const auto press = build(run, -1);
    bool partial = false;
    for (int i = 0; i < 200; ++i) {
        const auto view = run.host.advance();
        if (field<I>(V(field<O>(view, "stock")), "held") > 0 && field<I>(view, "remaining") == 1) {
            partial = true;
            break;
        }
    }
    check(partial, "The powered original line begins a real unfinished workpiece.");
    run.at(-1.65, -1.65); (void)run.action("set_power", {{"active", V(false)}});
    const auto stocked = run.host.projection();
    std::string collector;
    for (const auto& [id, entity] : field<O>(stocked, "entities"))
        if (field<std::string>(entity, "kind") == "collector") collector = id;
    check(!collector.empty(), "The original collector is present on the first seam tile.");
    run.at(4.95, 0);
    const auto recovery = run.action("recover", {{"entity", V(press)}});
    const auto work = field<A>(recovery, "moved_work");
    check(work.size() == 1 && field<I>(work.front(), "remaining_ticks") > 0 &&
              field<I>(work.front(), "remaining_ticks") < field<I>(work.front(), "cycle_ticks"),
          "Recovery retains a real unfinished workpiece and its remaining progress.");
    const auto work_id = field<I>(work.front(), "id");
    const auto remaining = field<I>(work.front(), "remaining_ticks");
    const auto subticks = field<I>(work.front(), "completed_subticks");
    run.at(0, 0); const auto collector_recovery = run.action("recover", {{"entity", V(collector)}});
    check(field<I>(collector_recovery, "moved_raw") > 0, "The stocked collector transfers actual raw material.");
    I recovered_slots = 0;
    const auto spans = field<O>(run.host.projection(), "belt_spans");
    for (const auto& [id, span] : spans) {
        const auto parts = field<O>(run.host.projection(), "transmission_parts");
        const auto first = field<A>(parts.at(field<std::string>(span, "from")), "center");
        const auto last = field<A>(parts.at(field<std::string>(span, "to")), "center");
        const auto slots = field<A>(span, "slots");
        for (std::size_t index = 0; index < slots.size(); ++index) {
            if (slots[index].type() == factory::values::Type::null) continue;
            const auto interpolate = [&](std::size_t axis) {
                const auto a = std::get<I>(first[axis].storage());
                const auto b = std::get<I>(last[axis].storage());
                return (a + (b - a) * static_cast<I>(index) / static_cast<I>(slots.size() - 1)) * 1.65 / 4.0;
            };
            run.at(interpolate(0), interpolate(2));
            (void)run.action("recover_belt_slot", {{"entity", V(id)}, {"slot", V(static_cast<I>(index))}, {"expected", slots[index]}});
            ++recovered_slots;
        }
        run.at((std::get<I>(first[0].storage()) + std::get<I>(last[0].storage())) * 1.65 / 8,
               (std::get<I>(first[2].storage()) + std::get<I>(last[2].storage())) * 1.65 / 8);
        (void)run.action("remove_belt_span", {{"entity", V(id)}});
    }
    check(recovered_slots > 0, "At least one in-flight belt item is recovered before removal.");
    const auto entities = field<O>(run.host.projection(), "entities");
    for (const auto& [id, entity] : entities) {
        const auto center = field<A>(entity, "center");
        run.at(std::get<I>(center[0].storage()) * 1.65 / 4, std::get<I>(center[2].storage()) * 1.65 / 4);
        (void)run.action("remove", {{"entity", V(id)}});
    }
    const auto parts = field<O>(run.host.projection(), "transmission_parts");
    for (const auto& [id, part] : parts) {
        const auto center = field<A>(part, "center");
        run.at(std::get<I>(center[0].storage()) * 1.65 / 4, std::get<I>(center[2].storage()) * 1.65 / 4);
        (void)run.action("remove", {{"entity", V(id)}});
    }
    const auto foundations = field<O>(run.host.projection(), "foundations");
    for (const auto& [id, foundation] : foundations) {
        const auto cell = field<A>(foundation, "cell");
        run.at(std::get<I>(cell[0].storage()) * 1.65, std::get<I>(cell[1].storage()) * 1.65);
        (void)run.action("remove", {{"entity", V(id)}});
    }
    conserved(run.host);
    const auto rebuilt = build(run, 0);
    run.at(4.95, 1.65);
    (void)run.action("insert_work", {{"entity", V(rebuilt)}, {"work_id", V(work_id)}});
    const auto cargo = field<O>(run.host.projection(), "cargo");
    check(field<A>(cargo.at("P"), "work_lots").empty(), "The original workpiece leaves player custody exactly once.");
    const auto before = run.host.checkpoint();
    const auto world = V(field<O>(before, "world"));
    const auto state = V(field<O>(world, "state"));
    const auto material = V(field<O>(state, "material"));
    const auto processing = field<O>(material, "processing");
    const auto resumed_work = V(processing);
    check(field<I>(resumed_work, "id") == work_id && field<I>(resumed_work, "remaining_ticks") == remaining &&
              field<I>(resumed_work, "completed_subticks") == subticks,
          "The rebuilt machine retains the same work identity and exact fractional progress.");
    Run restored("relocate-resume", false, before);
    check(same(before, restored.host.checkpoint()), "The relocated line and partial work restore exactly.");
    bool finished = false;
    for (int i = 0; i < 200; ++i) {
        const auto view = restored.host.advance();
        if (field<I>(V(field<O>(view, "stock")), "output") > 0) { finished = true; break; }
    }
    check(finished, "The relocated processor finishes the recovered workpiece.");
    restored.at(4.95, 1.65);
    (void)restored.action("retrieve", {{"entity", V(rebuilt)}, {"amount", V(I{1})}});
    conserved(restored.host);
}

void inclined_fork_fixture() {
    for (I speed : {I{200}, I{600}}) for (int order : {1, 2}) for (bool collector_last : {false, true}) {
        Run run("inclined-fork", false, std::nullopt, speed);
        const auto press = build(run, 0, true, false, order, true, true, collector_last);
        const bool starving = speed == 600 && order == 1;
        const auto initial = e::inspect(run.host, "P");
        check(initial.belt_forward != starving, "The inclined route accounts for a fast competing inlet.");
        for (int turn = 0; turn < 200 && e::inspect(run.host, "P").products < 8; ++turn) {
            const auto stock = field<O>(run.host.projection(), "stock");
            if (std::get<I>(stock.at("output").storage()) > 0) {
                run.at(4.95, 1.65);
                (void)run.action("retrieve", {{"entity", V(press)}, {"amount", V(I{1})}});
            }
            (void)run.host.advance();
        }
        const auto progress = e::inspect(run.host, "P");
        check(progress.belt_forward != starving && (starving ? progress.products == 0 : progress.products == 8),
              "Inclined competing cargo and challenge assessment agree for both construction orders.");
        if (order == 1) {
            I spilled = 0;
            for (const auto& drop : field<A>(run.host.projection(), "dropped_material")) spilled += field<I>(drop, "raw");
            check(spilled > 0, "The inclined competitor actually diverts material.");
        }
        conserved(run.host);
        const auto saved = run.host.checkpoint();
        Run restored("inclined-restored", false, saved, speed);
        check(e::inspect(restored.host, "P").belt_forward == progress.belt_forward,
              "An inclined collector and belt restore with the same assessment.");
    }
}

void moving_fork_fixture() {
    for (I speed : {I{200}, I{400}}) for (int order : {1, 2}) {
        Run run(order == 1 ? "moving-fork-first" : "moving-fork-last", false, std::nullopt, speed);
        const auto press = build(run, 0, true, false, order, true);
        const auto start = run.host.projection();
        const auto motion = field<O>(start, "motion");
        int rotating_spans = 0;
        for (const auto& [id, span] : field<O>(start, "belt_spans")) {
            (void)id;
            const auto from = field<std::string>(span, "from");
            if (field<std::string>(motion.at(from), "state") == "rotating") ++rotating_spans;
        }
        check(rotating_spans == 2, "The competing span and working span both rotate.");
        if (speed == 400 && order == 1) {
            const auto spans = field<O>(start, "belt_spans");
            bool fast_first = false;
            for (const auto& [id, span] : spans) {
                (void)id;
                if (field<I>(span, "order") != 0) continue;
                const auto entry = motion.at(field<std::string>(span, "from"));
                const auto numerator = field<I>(entry, "numerator");
                fast_first = numerator >= field<I>(entry, "denominator") ||
                             -numerator >= field<I>(entry, "denominator");
            }
            check(fast_first && !e::inspect(run.host, "P").belt_forward,
                  "A fast first competing inlet prevents a forward route before any ticks.");
        }
        for (int turn = 0; turn < 200 && e::inspect(run.host, "P").products < 8; ++turn) {
            const auto stock = field<O>(run.host.projection(), "stock");
            if (std::get<I>(stock.at("output").storage()) > 0) {
                run.at(4.95, 1.65);
                (void)run.action("retrieve", {{"entity", V(press)}, {"amount", V(I{1})}});
            }
            (void)run.host.advance();
        }
        const auto progress = e::inspect(run.host, "P");
        if (speed == 400 && order == 1) {
            check(progress.products == 0 && !progress.belt_forward,
                  "A faster first branch diverts production and must not be reported as a working route.");
        } else {
            check(progress.products == 8 && progress.belt_forward && progress.phase == e::Phase::ready,
                  "The working route produces plates when it receives collected material.");
        }
        if (order == 1) {
            I spilled = 0;
            for (const auto& drop : field<A>(run.host.projection(), "dropped_material")) spilled += field<I>(drop, "raw");
            check(spilled > 0, "The first competing span actually diverts and drops collected blanks.");
        }
        conserved(run.host);
        const auto saved = run.host.checkpoint();
        Run resumed(order == 1 ? "moving-first-resume" : "moving-last-resume", false, saved, speed);
        check(e::inspect(run.host, "P").belt_forward == e::inspect(resumed.host, "P").belt_forward,
              "Restoration preserves the same fork assessment.");
        for (int i = 0; i < 20; ++i) { (void)run.host.advance(); (void)resumed.host.advance(); }
        check(same(run.host.checkpoint(), resumed.host.checkpoint()),
              "Moving fork cargo and construction order survive checkpoint continuation.");
    }
}

void fork_fixture() {
    for (int order : {1, 2}) {
        Run run(order == 1 ? "fork-first" : "fork-last");
        (void)build(run, 0, true, false, order);
        const auto spans = field<O>(run.host.projection(), "belt_spans");
        check(spans.size() == 2, "Both branches are constructed through the finite Host.");
        for (int i = 0; i < 40; ++i) (void)run.host.advance();
        const auto projection = run.host.projection();
        const auto stock = field<O>(projection, "stock");
        check(std::get<I>(stock.at("input").storage()) > 0 ||
              std::get<I>(stock.at("output").storage()) > 0 ||
              std::get<I>(stock.at("held").storage()) > 0,
              "A stopped competing branch eventually fills, allowing the other route to process material.");
        check(e::inspect(run.host, "P").belt_forward,
              "A stopped competing branch does not hide an operating forward route.");
        if (order == 1) {
            const auto motion = field<O>(projection, "motion");
            bool stopped_branch_contains_raw = false;
            for (const auto& [id, span] : field<O>(projection, "belt_spans")) {
                (void)id;
                const auto& first = field<std::string>(span, "from");
                if (field<std::string>(motion.at(first), "state") == "rotating") continue;
                for (const auto& slot : field<A>(span, "slots"))
                    if (slot.type() != factory::values::Type::null && field<I>(slot, "raw") > 0)
                        stopped_branch_contains_raw = true;
            }
            check(stopped_branch_contains_raw, "The first stopped branch received and retained a real blank.");
        }
        const auto saved = run.host.checkpoint();
        Run resumed(order == 1 ? "fork-first-resume" : "fork-last-resume", false, saved);
        for (int i = 0; i < 20; ++i) { (void)run.host.advance(); (void)resumed.host.advance(); }
        check(same(run.host.checkpoint(), resumed.host.checkpoint()),
              "Fork order and in-flight material survive fresh-Host continuation.");
    }
}
}  // namespace

int main() {
    try {
        Host absent;
        check(e::inspect(absent, "P").phase == e::Phase::unavailable, "An uninitialized Host has no challenge state.");
        forward_and_checkpoint(false); forward_and_checkpoint(true); negative_routes(); wrong_source(); fork_fixture(); moving_fork_fixture(); inclined_fork_fixture(); relocate_stocked_line();
        std::cout << checks << " native opening-engineering checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
