#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <array>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};

void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const V& value, const char* name) {
    return std::get<T>(std::get<O>(value.storage()).at(name).storage());
}
bool accepted(const V& value) { return field<bool>(value, "accepted"); }

O wire(const char* action, const char* id) {
    return {{"context", V("cog-api")}, {"client", V("P")}, {"request", V(id)}, {"action", V(action)}};
}

O machine(const char* kind, I x, const char* id, const char* axis = "y") {
    auto command = wire("place", id);
    command.emplace("kind", V(kind)); command.emplace("cell", V(A{V(x), V(I{1})}));
    if (axis) command.emplace("axis", V(axis));
    return command;
}

O gear(I x, I y, I z, const char* id, const char* axis = "y", I teeth = 2) {
    auto command = wire("place_gear", id);
    command.emplace("center", V(A{V(x), V(y), V(z)}));
    command.emplace("axis", V(axis)); command.emplace("teeth", V(teeth));
    return command;
}

O target(const char* action, const std::string& entity, const char* id) {
    auto command = wire(action, id); command.emplace("entity", V(entity)); return command;
}

O connection(const std::string& from, const std::string& to, const char* id) {
    auto command = wire("connect_drive", id);
    command.emplace("from", V(from)); command.emplace("to", V(to)); return command;
}

std::string create(Host& host, const O& command) {
    const auto reply = host.command("P", command);
    check(accepted(reply), "Placement " + field<std::string>(V(command), "request") +
          " must succeed; reason=" + field<std::string>(reply, "reason") + ".");
    return field<std::string>(reply, "entity");
}

V motion(const Host& host, const std::string& entity) {
    return V(field<O>(host.projection(), "motion").at(entity));
}

void observe(Host& host, double x, double z, I epoch) {
    check(accepted(host.publish_actor("P", {V(x), V(1.0), V(z)}, epoch)),
          "The disclosed synthetic observation is accepted for this native unit only.");
}

void finite_oriented_train_and_restore() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})), "The original finite profile initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::channel_site())), "The test binds explicit synthetic terrain.");
    observe(host, -1.65, 3.3, 1);
    const auto specs = field<O>(host.projection(), "part_specifications");
    bool saw_gear = false, saw_large = false;
    for (const auto& entry : std::get<A>(specs.at("P").storage())) {
        if (field<std::string>(entry, "kind") != "gear") continue;
        saw_gear |= field<I>(entry, "teeth") == 2 && field<I>(entry, "count") == 4;
        saw_large |= field<I>(entry, "teeth") == 4 && field<I>(entry, "count") == 1;
    }
    check(saw_gear, "The UI sees the actual carried gear specification, not only an aggregate count.");
    check(saw_large, "The native starter kit exposes one finite large cog to the UI.");
    for (const auto& entry : std::get<A>(specs.at("Q").storage()))
        check(field<I>(entry, "count") == 0, "An empty actor kit cannot borrow the other actor's parts.");
    auto base = wire("place_foundation", "collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{1})})); base.emplace("level", V(I{0}));
    check(accepted(host.command("P", base)), "The synthetic stream bank supports a collector foundation.");
    const auto wheel = create(host, machine("wheel", -1, "wheel", "z"));
    const auto collector = create(host, machine("collector", 0, "collector", "z"));
    observe(host, 0, 0, 2);
    const auto a = create(host, gear(-4, 0, 8, "gear-A", "z"));
    const auto original_b = gear(0, 0, 8, "gear-B", "z");
    const auto b = create(host, original_b);
    check(accepted(host.command("P", connection(wheel, a, "shaft-A"))) &&
          accepted(host.command("P", connection(b, collector, "shaft-B"))),
          "Two finite Z-axis shafts join actual machine and gear identifiers.");
    auto power = wire("set_power", "start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The source enables the actual geometry train.");
    check(field<I>(motion(host, a), "numerator") == 1 && field<I>(motion(host, a), "denominator") == 1 &&
          field<I>(motion(host, b), "numerator") == -1 && field<I>(motion(host, b), "denominator") == 1 &&
          field<I>(motion(host, collector), "numerator") == -1,
          "Meshing equal gears reverses the exact signed rate through the independent shafts.");
    check(field<bool>(host.projection(), "powered") &&
          field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 2 &&
          field<I>(V(field<O>(host.projection(), "parts")), "gear") == 3,
          "The powered train retains two spare shafts, two small cogs and the large cog.");
    const auto ticked = host.advance();
    check(field<I>(V(field<O>(ticked, "stock")), "source") == 15 &&
          field<I>(V(field<O>(ticked, "stock")), "collector") == 1,
          "The current direction-insensitive machine adapter moves one of sixteen raw units.");
    check(accepted(host.command("P", target("remove", b, "remove-B"))),
          "An individual gear can be removed while the source stays enabled.");
    check(!field<bool>(host.projection(), "powered"), "An orphaned shaft cannot invent a source connection.");
    const auto misaligned = create(host, gear(1, 0, 8, "misaligned", "z"));
    check(!field<bool>(host.projection(), "powered"), "A one-grid-unit displacement cannot mesh or power the collector.");
    check(accepted(host.command("P", target("remove", misaligned, "remove-misaligned"))),
          "The actual misplaced part returns before reconstruction.");
    const auto rebuilt = create(host, gear(0, 0, 8, "rebuild-B", "z"));
    check(rebuilt != b && field<bool>(host.projection(), "powered") &&
          field<I>(motion(host, rebuilt), "numerator") == -1,
          "Correct reconstruction restores geometric transmission with a new identity.");
    observe(host, 20, 20, 3);
    const auto retry = host.command("P", original_b);
    check(accepted(retry) && field<bool>(retry, "duplicate") && field<std::string>(retry, "entity") == b,
          "The original gear request replays before present pose and rebuilt-target lookup.");
    auto changed = original_b; changed.at("axis") = V("x");
    check(field<std::string>(host.command("P", changed), "reason") == "request_reuse",
          "Changing an old gear's orientation cannot retarget its cached request.");
    observe(host, 0, 0, 4);
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "The complete oriented train and original wire histories validate.");
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())) &&
              accepted(fresh.restore_checkpoint(saved)),
          "A fresh native Host restores the original profile without resetting its kit.");
    check(!factory::values::typed_difference(saved, fresh.checkpoint()),
          "Every typed quantity, axis, height, shaft, identity and old receipt survives exactly.");
    check(field<bool>(fresh.command("P", original_b), "duplicate"),
          "Restored historical gear lookup precedes fresh native readiness.");
}

void refusals_and_legacy_shape() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})), "The refusal fixture initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The refusal fixture binds explicit synthetic terrain.");
    observe(host, -1.65, 3.3, 1);
    const auto state_before = field<O>(V(field<O>(host.checkpoint(), "world")), "state");
    const auto reject = [&](O command, const char* reason) {
        const auto reply = host.command("P", command);
        check(!accepted(reply) && field<std::string>(reply, "reason") == reason,
              "Request " + std::get<std::string>(command.at("request").storage()) +
              " must refuse with " + reason + "; actual accepted=" +
              (accepted(reply) ? "true" : "false") + ", reason=" + field<std::string>(reply, "reason") + ".");
        check(!factory::values::typed_difference(V(state_before), V(field<O>(V(field<O>(host.checkpoint(), "world")), "state"))),
              "A refusal cannot consume parts, create identifiers or alter material custody.");
    };
    auto floating = gear(0, 4, 4, "float-center");
    floating.at("center") = V(A{V(0.0), V(I{4}), V(I{4})});
    reject(floating, "invalid_center");
    reject(gear(0, 4, 4, "invalid-axis", "bad"), "invalid_axis");
    reject(gear(0, 1000001, 4, "outside-native-integer-range"), "invalid_center");
    reject(gear(-4, 8, 4, "uncarried-size", "y", 3), "unavailable_part");
    auto boolean = machine("collector", 0, "boolean-axis"); boolean.at("axis") = V(false);
    reject(boolean, "invalid_axis");
    auto overlapping = gear(-4, 1, 8, "actor-overlap");
    reject(overlapping, "actor_occupied");
    const auto old = create(host, machine("collector", 0, "old-cell", nullptr));
    check(field<I>(V(field<O>(host.projection(), "entities").at(old)), "axis") == 0,
          "The unchanged two-dimensional cell wire retains its original default axis.");
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "Legacy placement and exact malformed refusals still round-trip.");
}

V world_state(const Host& host) {
    return V(field<O>(V(field<O>(host.checkpoint(), "world")), "state"));
}

void finite_large_cog() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})), "The large-cog Host initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The large-cog Host binds its site.");
    observe(host, -1.65, 3.3, 1);
    const auto large = create(host, gear(-4, 8, 4, "large", "y", 4));
    const auto refused = host.command("P", gear(0, 8, 4, "exhausted-large", "y", 4));
    check(!accepted(refused) && field<std::string>(refused, "reason") == "unavailable_part",
          "The finite large-cog kit cannot place a second large cog.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::flat_site())), "The fresh Host binds its site.");
    const auto restored = fresh.restore_checkpoint(saved);
    check(accepted(restored), "Large-cog checkpoint restore: " + field<std::string>(restored, "reason"));
    check(!factory::values::typed_difference(saved, fresh.checkpoint()),
          "The placed large cog and its depleted kit survive a fresh Host checkpoint restore.");
    check(accepted(host.command("P", target("remove", large, "remove-large"))), "Removing the large cog succeeds.");
    create(host, gear(-4, 8, 4, "replace-large", "y", 4));
    check(!accepted(host.command("P", gear(0, 8, 4, "exhausted-again", "y", 4))),
          "Removal returns exactly one large cog for replacement.");
}

void perpendicular_belt_line() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::channel_site())),
          "The perpendicular-line Host binds its synthetic terrain.");
    observe(host, -1.65, 3.3, 1);
    auto base = wire("place_foundation", "line-collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{1})})); base.emplace("level", V(I{0}));
    check(accepted(host.command("P", base)), "The synthetic line has a supported collector.");
    const std::array<const char*, 4> roles{"wheel", "collector", "belt", "processor"};
    std::array<std::string, 4> hubs, cogs;
    for (std::size_t n = 0; n < roles.size(); ++n) {
        const I x = static_cast<I>(n) - 1;
        observe(host, static_cast<double>(x) * 1.65, 0, static_cast<I>(n) + 2);
        const auto machine_id = "line-machine-" + std::to_string(n);
        const auto gear_id = "line-gear-" + std::to_string(n);
        const auto shaft_id = "line-shaft-" + std::to_string(n);
        hubs[n] = create(host, machine(roles[n], x, machine_id.c_str(), "z"));
        cogs[n] = create(host, gear(4 * x, 0, 8, gear_id.c_str(), "z", 2));
        check(accepted(host.command("P", connection(hubs[n], cogs[n], shaft_id.c_str()))),
              "The actor connects each real machine to its perpendicular cog with one carried shaft.");
    }
    observe(host, -1.65, 0, 6);
    auto power = wire("set_power", "line-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The actor enables the source for the perpendicular line.");
    const auto projected = host.projection();
    check(field<A>(projected, "links").size() == 2 &&
              field<I>(V(field<O>(projected, "parts")), "shaft") == 0 &&
              field<I>(V(field<O>(projected, "parts")), "gear") == 1,
          "The connected line uses exactly four small cogs and shafts, leaving its large cog.");
    for (std::size_t n = 0; n < hubs.size(); ++n)
        check(field<I>(motion(host, hubs[n]), "numerator") == (n % 2 ? -1 : 1) &&
                  field<I>(motion(host, hubs[n]), "denominator") == 1,
              "The actual Host reports alternating signed machine rotation.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "The full perpendicular route and finite kit survive fresh Host restoration.");
    observe(host, 1.65, 0, 7);
    check(accepted(host.command("P", target("remove", cogs[2], "line-remove-belt-cog"))) &&
              field<std::string>(motion(host, hubs[2]), "state") != "rotating",
          "Removing the belt cog breaks belt power and returns the physical part.");
}

void equivalent_gear_exclusion() {
    for (const auto* axis : std::array<const char*, 4>{"x", "y", "z", nullptr}) {
        const auto* effective_axis = axis ? axis : "x";
        const bool axial_x = std::string(effective_axis) == "x";
        const A blocked{V(axial_x ? 0.0 : 1.1), V(0.9), V(axial_x ? 2.75 : 1.65)};
        Host legacy, modern;
        check(accepted(legacy.initialize("cog-api", {"P"})) && accepted(modern.initialize("cog-api", {"P"})),
              "Equivalent gear aliases start from identical finite profiles.");
        const auto initial = world_state(legacy);
        check(accepted(legacy.publish_actor("P", blocked, 1)) && accepted(modern.publish_actor("P", blocked, 1)),
              "The literal source counterexample uses disclosed synthetic capsule observations.");
        const auto old_wire = machine("gear", 0, "blocked-alias", axis);
        const auto new_wire = gear(0, 0, 4, "blocked-alias", effective_axis);
        const auto old_refusal = legacy.command("P", old_wire);
        const auto new_refusal = modern.command("P", new_wire);
        check(!accepted(old_refusal) && field<std::string>(old_refusal, "reason") == "actor_occupied" &&
              !accepted(new_refusal) && field<std::string>(new_refusal, "reason") == "actor_occupied",
              "Both equivalent aliases refuse the same intersecting oriented disc, including default X.");
        check(!factory::values::typed_difference(initial, world_state(legacy)) &&
              !factory::values::typed_difference(initial, world_state(modern)),
              "Neither refusal consumes a gear, creates an identity or changes material custody.");

        const A clear{V(1.4), V(0.9), V(3.3)};
        check(accepted(legacy.publish_actor("P", clear, 2)) && accepted(modern.publish_actor("P", clear, 2)),
              "A newer clear observation does not rewrite the prior request.");
        const auto old_retry = legacy.command("P", old_wire);
        const auto new_retry = modern.command("P", new_wire);
        check(!accepted(old_retry) && field<bool>(old_retry, "duplicate") &&
              !accepted(new_retry) && field<bool>(new_retry, "duplicate") &&
              field<std::string>(old_retry, "reason") == "actor_occupied" &&
              field<std::string>(new_retry, "reason") == "actor_occupied" &&
              !std::get<O>(old_retry.storage()).contains("native_epoch") &&
              !std::get<O>(new_retry.storage()).contains("native_epoch"),
              "Cached adapter refusals precede present geometry without inventing a native admission epoch.");
        check(!factory::values::typed_difference(initial, world_state(legacy)) &&
              !factory::values::typed_difference(initial, world_state(modern)),
              "Retrying a refusal from a clear pose cannot allocate a part.");

        const auto old_clear = machine("gear", 0, "clear-alias", axis);
        const auto new_clear = gear(0, 0, 4, "clear-alias", effective_axis);
        const auto old_success = legacy.command("P", old_clear);
        const auto new_success = modern.command("P", new_clear);
        check(accepted(old_success) && accepted(new_success), "New requests at the clear pose both place the gear.");
        check(!factory::values::typed_difference(world_state(legacy), world_state(modern)) &&
              field<I>(V(field<O>(legacy.projection(), "parts")), "gear") == 4,
              "Equivalent accepted aliases produce identical typed topology and retain four carried gears.");
        const auto placed = world_state(legacy);
        check(accepted(legacy.publish_actor("P", blocked, 3)) && accepted(modern.publish_actor("P", blocked, 3)),
              "Present overlap is observed after placement without changing the saved part.");
        const auto old_cached = legacy.command("P", old_clear);
        const auto new_cached = modern.command("P", new_clear);
        check(accepted(old_cached) && field<bool>(old_cached, "duplicate") &&
              accepted(new_cached) && field<bool>(new_cached, "duplicate") &&
              field<I>(old_cached, "native_epoch") == 2 && field<I>(new_cached, "native_epoch") == 2 &&
              field<std::string>(old_cached, "entity") == field<std::string>(old_success, "entity") &&
              field<std::string>(new_cached, "entity") == field<std::string>(new_success, "entity"),
              "Accepted replay precedes present overlap and retains the original identity and epoch.");
        check(!factory::values::typed_difference(placed, world_state(legacy)) &&
              !factory::values::typed_difference(placed, world_state(modern)),
              "Historical replay cannot place or refund another gear.");
        check(accepted(legacy.validate_checkpoint(legacy.checkpoint())) &&
              accepted(modern.validate_checkpoint(modern.checkpoint())),
              "Both typed checkpoints validate with their original accepted and refused histories.");
    }
}
void global_grid() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})), "The global-grid fixture initializes.");
    check(accepted(host.publish_actor("P", {V(16.5), V(6.0), V(6.0)}, 1)),
          "A disclosed synthetic actor is near the new absolute grid point.");
    const auto placed = host.command("P", gear(40, 17, 8, "global-grid"));
    check(accepted(placed), "Cogwheels are no longer clipped to the old construction rectangle or height range.");
    check(accepted(host.validate_checkpoint(host.checkpoint())), "Global gear coordinates retain typed save and history validity.");
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 1) {
            finite_oriented_train_and_restore(); refusals_and_legacy_shape();
            global_grid(); finite_large_cog(); perpendicular_belt_line();
        } else if (argc != 2 || std::string(argv[1]) != "--placement-alias-only") {
            throw std::runtime_error("Expected no arguments or --placement-alias-only.");
        }
        equivalent_gear_exclusion();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_cog_host_api\",\"checks\":" << checks
                  << ",\"engine_calls\":0,\"physical_producers\":0}" << std::endl;
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Check " << checks << ": " << error.what() << '\n';
        return 1;
    }
}
