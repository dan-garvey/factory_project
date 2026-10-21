#include "factory/opening_engineering.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <array>
#include <iostream>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

namespace e = factory::opening_engineering;
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
namespace {
int checks{};
constexpr I starter_row{1}, upstream_row{0};
void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}
bool accepted(const V& value) { return field<bool>(value, "accepted"); }
bool same(const V& a, const V& b) { return !factory::values::typed_difference(a, b); }

V material(const V& checkpoint) {
    const auto world = field<O>(checkpoint, "world");
    const auto state = field<O>(V(world), "state");
    return state.at("material");
}

std::string entity(const Host& host, const std::string& kind) {
    const auto projection = host.projection();
    for (const auto& [id, part] : field<O>(projection, "entities"))
        if (field<std::string>(part, "kind") == kind) return id;
    throw std::runtime_error("Missing canonical entity: " + kind);
}

I amount(const Host& host, const char* group, const char* name) {
    const auto projection = host.projection();
    return std::get<I>(field<O>(projection, group).at(name).storage());
}

void conserved(const Host& host) {
    const auto projection = host.projection();
    I total{};
    const auto stock = field<O>(projection, "stock");
    for (const auto* name : {"source", "collector", "belt", "input", "held", "output", "player"}) {
        const auto value = std::get<I>(stock.at(name).storage());
        check(value >= 0, "Each canonical material holder remains a nonnegative integer.");
        total += value;
    }
    I products{};
    const auto inventories = field<O>(projection, "inventories");
    for (const auto& [actor, cargo] : field<O>(projection, "cargo")) {
        total += field<I>(cargo, "raw");
        products += field<I>(cargo, "products");
        check(field<I>(cargo, "products") == std::get<I>(inventories.at(actor).storage()), "Product projection aliases are counted only once.");
        for (const auto& lot : field<A>(cargo, "work_lots")) total += field<I>(lot, "recipe_input");
    }
    for (const auto& drop : field<A>(projection, "dropped_material")) total += field<I>(drop, "raw");
    check(total == field<I>(projection, "initial_feed") && products == std::get<I>(stock.at("player").storage()),
          "Every original material unit has exactly one owner.");
    std::map<std::string, I> parts{{"collector", 0}, {"belt", 0}, {"processor", 0}, {"wheel", 0}, {"shaft", 0}, {"gear", 0}, {"foundation", 0}};
    for (const auto& [actor, kit] : field<O>(projection, "part_kits")) {
        (void)actor;
        for (const auto& [kind, count] : std::get<O>(kit.storage())) parts.at(kind) += std::get<I>(count.storage());
    }
    for (const auto* name : {"entities", "transmission_parts"})
        for (const auto& [id, part] : field<O>(projection, name)) { (void)id; ++parts.at(field<std::string>(part, "kind")); }
    parts.at("foundation") += static_cast<I>(field<O>(projection, "foundations").size());
    check(parts == std::map<std::string, I>{{"collector", 1}, {"belt", 1}, {"processor", 1}, {"wheel", 1}, {"shaft", 8}, {"gear", 10}, {"foundation", 24}},
          "The actual opening kit is conserved without new parts or a different scenario profile.");
}

// Invented channel and current; this is a native topology fixture, not a playtest.
O stream_site() {
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)}, heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    return {{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})},
            {"water", V(A{V(A{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})}),
                          V(A{V(I{-8}), V(I{4}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})})})}};
}

struct Run {
    Host host;
    std::string prefix;
    I serial{}, epoch{};
    explicit Run(std::string name, const std::optional<V>& saved = std::nullopt) : prefix(std::move(name)) {
        check(accepted(host.initialize("upstream-drive", {"P", "Q"})), "The real opening Host initializes its existing finite profile.");
        check(accepted(host.configure_terrain(stream_site())),
              "The native fixture binds explicit synthetic terrain before placement or restore.");
        if (saved) check(accepted(host.restore_checkpoint(*saved)), "A fresh unobserved Host restores the retained comparison checkpoint.");
    }
    void observe(I row) {
        // Disclosed synthetic unit observations. No engine, ActorWorld body or
        // ordinary keyboard/mouse action is represented by these coordinates.
        check(accepted(host.publish_actor("P", {V(0.0), V(1.0), V(static_cast<double>(row + 1) * 1.65)}, ++epoch)),
              "The bounded native unit has a current supplied P observation.");
    }
    void observe_at(double x, double z) {
        check(accepted(host.publish_actor("P", {V(x), V(1.0), V(z)}, ++epoch)),
              "The native fixture supplies a current synthetic reach observation.");
    }
    V action(const char* name, O arguments = {}) {
        arguments.emplace("context", V("upstream-drive")); arguments.emplace("client", V("P"));
        arguments.emplace("request", V(prefix + '-' + std::to_string(++serial))); arguments.emplace("action", V(name));
        const auto result = host.command("P", arguments);
        check(accepted(result), std::string(name) + " succeeds through the actual Host wire; reason=" + field<std::string>(result, "reason"));
        conserved(host);
        return result;
    }
    std::string place(const char* kind, I x, I row) {
        O args{{"kind", V(kind)}, {"cell", V(A{V(x), V(row)})}, {"axis", V(std::string(kind) == "wheel" ? "x" : "z")}};
        if (std::string(kind) == "wheel") args.emplace("level", V(I{4}));
        return field<std::string>(action("place", std::move(args)), "entity");
    }
    std::string gear(I x, I z, const char* axis = "x", I teeth = 2) {
        return field<std::string>(action("place_gear", {{"center", V(A{V(x), V(I{0}), V(z)})}, {"axis", V(axis)}, {"teeth", V(teeth)}}), "entity");
    }
    void connect(const char* kind, const std::string& from, const std::string& to) {
        (void)action(kind, {{"from", V(from)}, {"to", V(to)}});
    }
    void target(const char* name, const std::string& id) { (void)action(name, {{"entity", V(id)}}); }
    void tick() {
        const auto result = host.advance();
        check(std::get<O>(result.storage()).contains("stock"), "The owning Host advances without selecting another model.");
        conserved(host);
    }
    void collect_until(I target_count) {
        for (int turn = 0; turn < 128 && e::inspect(host, "P").products < target_count; ++turn) {
            if (amount(host, "stock", "output") > 0)
                (void)action("retrieve", {{"entity", V(entity(host, "processor"))}, {"amount", V(I{1})}});
            else tick();
        }
        check(e::inspect(host, "P").products == target_count, "The required products came from actual native processing and retrieval.");
    }
};

void build_route(Run& run, I wheel_row, I machine_row, const std::array<std::string, 3>& machines) {
    const double wheel_z = static_cast<double>(wheel_row) * 1.65;
    const bool different_rows = wheel_row != machine_row;
    const I small_row = different_rows ? wheel_row - 1 : wheel_row - 2;
    const double small_z = static_cast<double>(small_row) * 1.65;
    run.observe_at(-3.3, wheel_z);
    (void)run.action("place_gear", {{"center", V(A{V(I{-12}), V(I{4}), V(wheel_row * 4)})}, {"axis", V("x")}, {"teeth", V(I{2})}});
    (void)run.gear(-12, wheel_row * 4, "x", 2);
    (void)run.gear(-16, wheel_row * 4, "x", 4);
    run.observe_at(-3.3, wheel_z);
    const auto output = run.gear(-12, wheel_row * 4 - 4, "z", 4);
    for (std::size_t n = different_rows ? 1 : 0; n < 6; ++n) {
        const I x = static_cast<I>(n) * 4 - 12;
        run.observe_at(static_cast<double>(x) * 1.65 / 4.0, small_z + 1.65);
        (void)run.gear(x, small_row * 4, "z", 2);
    }
    (void)output; // The adjacent cog axle faces already touch.
    for (std::size_t n = 0; n < machines.size(); ++n) {
        run.observe_at((static_cast<double>(n) + 1.0) * 1.65, (small_z + static_cast<double>(machine_row) * 1.65) / 2.0);
        if (small_row != machine_row - 1)
            (void)run.action("place_shaft", {{"center", V(A{V(static_cast<I>(n) * 4), V(I{0}), V((machine_row - 1) * 4)})},
                                              {"axis", V("z")}, {"half_span", V(I{2})}});
    }
}

void clear_route(Run& run) {
    const auto parts = field<O>(run.host.projection(), "transmission_parts");
    for (const auto* kind : {"shaft", "gear"}) {
        for (const auto& [id, part] : parts) {
            if (field<std::string>(part, "kind") != kind) continue;
            const auto center = field<A>(part, "center");
            const auto x = std::get<I>(center[0].storage()), z = std::get<I>(center[2].storage());
            run.observe_at(static_cast<double>(x) * 1.65 / 4.0, static_cast<double>(z) * 1.65 / 4.0);
            run.target("remove", id);
        }
    }
}

V baseline() {
    Run run("base");
    check(e::inspect(run.host, "missing").phase == e::Phase::unavailable, "An unknown actor cannot borrow another player's objective.");
    check(e::inspect(run.host, "P").phase == e::Phase::first_shift, "A fresh game preserves its existing first objective.");
    run.observe(starter_row);
    (void)run.place("wheel", -2, starter_row);
    const auto collector = run.place("collector", 0, starter_row);
    const auto belt = run.place("belt", 1, starter_row);
    const auto press = run.place("processor", 2, starter_row);
    check(field<A>(run.host.projection(), "links").size() == 2,
          "Placing the adjacent machines connects both material ports.");
    build_route(run, starter_row, starter_row, {collector, belt, press});
    run.observe_at(-1.65, 0.0);
    (void)run.action("set_power", {{"active", V(true)}});
    run.observe(starter_row);
    run.collect_until(4);
    // One extra powered step retains a partly processed original lot. Reuse
    // this checkpoint for the different alternatives; do not replay this prefix.
    for (int turn = 0; turn < 12; ++turn) {
        const auto projection = run.host.projection();
        if (field<I>(V(field<O>(projection, "stock")), "held") > 0 && field<I>(projection, "remaining") == 1) break;
        run.tick();
    }
    const auto saved = run.host.checkpoint();
    const auto processing = field<O>(material(saved), "processing");
    check(std::get<I>(processing.at("remaining_ticks").storage()) == 1,
          "The shared comparison cut has a real partial workpiece, not a fresh empty line.");
    check(e::inspect(run.host, "P").phase == e::Phase::move_source &&
          e::inspect(run.host, "P").placed_gears == 10 && e::inspect(run.host, "P").placed_shafts == 3,
          "The first four products do not bypass the upstream constraint.");
    check(same(saved, run.host.checkpoint()), "Repeated eligibility reads neither step the world nor record progress.");
    check(accepted(run.host.validate_checkpoint(saved)), "The original partial-work checkpoint is valid for both comparisons.");
    return saved;
}

std::string move_source(Run& run) {
    run.observe(starter_row);
    const auto old_wheel = entity(run.host, "wheel");
    clear_route(run);
    run.observe(starter_row);
    run.target("remove", old_wheel);
    run.observe(upstream_row);
    const auto wheel = run.place("wheel", -2, upstream_row);
    const auto progress = e::inspect(run.host, "P");
    check(progress.source_at_target && !progress.machines_running && progress.phase == e::Phase::restore_drive,
          "Moving the original wheel spends its real refund but does not fabricate a working transmission.");
    return wheel;
}

void resume_and_finish(Run& run, const std::string& press, const char* layout) {
    check(e::inspect(run.host, "P").phase == e::Phase::deliver_more, "A repaired drive still needs the additional product objective.");
    const auto saved = run.host.checkpoint();
    Run resumed(std::string(layout) + "-fresh", saved);
    check(same(saved, resumed.host.checkpoint()) && e::inspect(resumed.host, "P").phase == e::Phase::deliver_more,
          "Typed fresh-Host continuation preserves the entire material/topology/receipt state and rederives eligibility.");
    resumed.observe(std::string(layout) == "relocated" ? upstream_row : starter_row);
    check(entity(resumed.host, "processor") == press, "Continuation retains the current actual press identity.");
    resumed.collect_until(8);
    const auto progress = e::inspect(resumed.host, "P");
    check(progress.phase == e::Phase::ready && progress.source_at_target && progress.machines_running && progress.belt_forward &&
          progress.placed_shafts == 3,
          "The current upstream layout and eight individually carried plates satisfy native eligibility.");
    check(e::inspect(resumed.host, "Q").products == 0 && e::inspect(resumed.host, "Q").phase == e::Phase::first_shift,
          "Aggregate player stock does not award P's completed objective to Q.");
    const auto before = resumed.host.checkpoint();
    (void)e::inspect(resumed.host, "P");
    check(same(before, resumed.host.checkpoint()), "Eligibility is a read of current authority, with no hidden completion state or consumption.");
    resumed.observe(upstream_row);
    (void)resumed.action("set_power", {{"active", V(false)}});
    check(e::inspect(resumed.host, "P").phase == e::Phase::restore_drive && e::inspect(resumed.host, "P").products == 8,
          "Current drive facts are reread rather than cached from an earlier success.");
    std::cout << "{\"layout\":\"" << layout << "\",\"products\":8,\"placed_gears\":" << progress.placed_gears
              << ",\"placed_shafts\":" << progress.placed_shafts << ",\"engine_calls\":0,\"physical_producers\":0}\n";
}

void relocate(const V& baseline) {
    Run run("relocated", baseline);
    (void)move_source(run);
    run.observe(starter_row);
    const auto old_collector = entity(run.host, "collector"), old_belt = entity(run.host, "belt"), old_press = entity(run.host, "processor");
    const auto collector_raw = amount(run.host, "stock", "collector");
    const auto belt_raw = amount(run.host, "stock", "belt");
    const auto press_raw = amount(run.host, "stock", "input");
    for (const auto& id : {old_collector, old_belt, old_press}) run.target("recover", id);
    const auto projection = run.host.projection();
    const auto cargo = field<O>(projection, "cargo");
    const auto carried = cargo.at("P");
    check(collector_raw > 0 && belt_raw > 0 && press_raw > 0 &&
          field<I>(carried, "raw") == collector_raw + belt_raw + press_raw && field<A>(carried, "work_lots").size() == 1 &&
          field<I>(field<A>(carried, "work_lots").front(), "remaining") == 1,
          "Relocation carries all three raw buffers and the same partial work with its progress.");
    const auto work_id = field<I>(field<A>(carried, "work_lots").front(), "id");
    for (const auto& id : {old_collector, old_belt, old_press}) run.target("remove", id);
    run.observe(upstream_row);
    const auto collector = run.place("collector", 0, upstream_row), belt = run.place("belt", 1, upstream_row), press = run.place("processor", 2, upstream_row);
    check(collector != old_collector && belt != old_belt && press != old_press, "The relocation route genuinely rebuilds all three machines under fresh identities.");
    check(field<A>(run.host.projection(), "links").size() == 2,
          "Rebuilding adjacent machines reconnects both material ports.");
    build_route(run, upstream_row, upstream_row, {collector, belt, press});
    run.observe(upstream_row);
    (void)run.action("insert_work", {{"entity", V(press)}, {"work_id", V(work_id)}});
    for (const auto& [id, quantity] : {std::pair{collector, collector_raw}, std::pair{belt, belt_raw}, std::pair{press, press_raw}})
        (void)run.action("insert_raw", {{"entity", V(id)}, {"amount", V(quantity)}});
    check(same(material(baseline), material(run.host.checkpoint())), "Moving the line restores the exact original material cut, without resetting work or stock.");
    check(e::inspect(run.host, "P").placed_gears == 10 && amount(run.host, "parts", "gear") == 0,
          "The relocation alternative rebuilds the finite ten-cog route.");
    resume_and_finish(run, press, "relocated");
}

void gear_route(const V& baseline) {
    Run run("geared", baseline);
    (void)move_source(run);
    const auto collector = entity(run.host, "collector"), belt = entity(run.host, "belt"), press = entity(run.host, "processor");
    run.observe(upstream_row);
    run.observe_at(-1.65, -1.65);
    const auto wrong = run.gear(-4, upstream_row * 4);
    check(e::inspect(run.host, "P").phase == e::Phase::restore_drive, "An unconnected, misaligned cog cannot power the original line.");
    run.target("remove", wrong);
    build_route(run, upstream_row, starter_row, {collector, belt, press});
    check(e::inspect(run.host, "P").machines_running, "The refunded cog supports a corrected cross-axis route.");
    const auto projection = run.host.projection();
    const auto motion = field<O>(projection, "motion");
    check(field<I>(motion.at(collector), "numerator") == 2 && field<I>(motion.at(belt), "numerator") == -2 &&
          field<I>(motion.at(press), "numerator") == 2, "The cross-axis cog train alternates signed machine motion and drives the belt forward: " +
          std::to_string(field<I>(motion.at(collector), "numerator")) + "," + std::to_string(field<I>(motion.at(belt), "numerator")) + "," + std::to_string(field<I>(motion.at(press), "numerator")));
    check(entity(run.host, "collector") == collector && entity(run.host, "belt") == belt && entity(run.host, "processor") == press &&
          same(material(baseline), material(run.host.checkpoint())), "The cog route preserves all original machine identities and the entire stocked material cut.");
    check(e::inspect(run.host, "P").placed_gears == 9 && amount(run.host, "parts", "gear") == 1,
          "Keeping the line in place rebuilds the finite cog route.");
    resume_and_finish(run, press, "geared");
}

void count_only(const V& baseline) {
    Run run("count-only", baseline);
    run.observe(starter_row);
    run.collect_until(8);
    const auto progress = e::inspect(run.host, "P");
    check(progress.products == 8 && progress.machines_running && !progress.source_at_target && progress.phase == e::Phase::move_source,
          "Eight plates on the original straight layout cannot bypass the new upstream construction constraint.");
}
}  // namespace

int main() {
    try {
        Host absent;
        check(e::inspect(absent, "P").phase == e::Phase::unavailable, "Missing native ownership cannot produce goal eligibility.");
        const auto saved = baseline();
        count_only(saved);
        relocate(saved);
        gear_route(saved);
        std::cout << checks << " native opening-engineering checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
