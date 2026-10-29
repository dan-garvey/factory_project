#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <algorithm>
#include <array>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
constexpr I grid_scale = static_cast<I>(1.65 / factory::godot_world::site_geometry::pitch);
static_assert(grid_scale * factory::godot_world::site_geometry::pitch == 1.65);
constexpr double u_scale = factory::godot_world::site_geometry::pitch / 1.65;
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
    if (std::string(kind) == "wheel") command.emplace("level", V(I{4}));
    if (axis) command.emplace("axis", V(axis));
    return command;
}

O channel_wheel(const char* id, const char* axis = "z") {
    auto command = machine("wheel", -3 * grid_scale, id, axis);
    command.at("cell") = V(A{V(I{-3} * grid_scale), V(I{1} * grid_scale)});
    command.at("level") = V(I{4} * grid_scale);
    return command;
}

O ground_channel_site() {
    auto site = factory::godot_world::tests::channel_site();
    auto heights = field<A>(V(site), "heights");
    for (auto& height : heights)
        if (std::get<double>(height.storage()) == -1.65) height = V(-3.3);
    site.at("heights") = V(std::move(heights));
    auto water = field<A>(V(site), "water");
    for (auto& sample : water) {
        auto values = std::get<A>(sample.storage());
        values[3] = V(I{-1600});
        sample = V(std::move(values));
    }
    site.at("water") = V(std::move(water));
    return site;
}

O ground_channel_wheel(const char* id, const char* axis = "z") {
    auto command = channel_wheel(id, axis);
    command.at("level") = V(I{0});
    return command;
}

O gear(I x, I y, I z, const char* id, const char* axis = "y", I teeth = 2) {
    auto command = wire("place_gear", id);
    command.emplace("center", V(A{V(x), V(y), V(z)}));
    command.emplace("axis", V(axis)); command.emplace("teeth", V(teeth));
    return command;
}

O shaft(I x, I y, I z, const char* id, const char* axis = "z", I span = 2) {
    auto command = wire("place_shaft", id);
    command.emplace("center", V(A{V(x), V(y), V(z)}));
    command.emplace("axis", V(axis)); command.emplace("half_span", V(span));
    return command;
}

O relay(const char* kind, I x, I y, I z, const char* id,
        const char* axis, const char* link_axis = nullptr) {
    auto command = wire("place_relay", id);
    command.emplace("kind", V(kind)); command.emplace("center", V(A{V(x), V(y), V(z)}));
    command.emplace("axis", V(axis));
    if (link_axis) command.emplace("relay_axis", V(link_axis));
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

I raw_on_belts(const V& projection) {
    I result = 0;
    for (const auto& [id, span] : field<O>(projection, "belt_spans")) {
        (void)id;
        for (const auto& item : field<A>(span, "slots")) {
            if (item.type() == factory::values::Type::null) continue;
            result += field<I>(item, "raw");
            for (const auto& lot : field<A>(item, "work_lots")) result += field<I>(lot, "recipe_input");
        }
    }
    return result;
}

void observe(Host& host, double x, double z, I epoch) {
    check(accepted(host.publish_actor("P", {V(x), V(1.0), V(z)}, epoch)),
          "The disclosed synthetic observation is accepted for this native unit only.");
}

O low_flat_site() {
    auto site = factory::godot_world::tests::flat_site();
    site.at("heights") = V(A{V(-1.0), V(-1.0), V(-1.0), V(-1.0)});
    return site;
}

void transmission_request_shapes() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
          accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
          "The placement contract test binds an actual finite Host and site.");
    observe(host, 0, 0, 1);
    const auto before = host.checkpoint();
    const auto before_world = field<O>(before, "world");
    const auto before_state = field<O>(V(before_world), "state");
    const auto before_projection = host.projection();
    auto extra_shaft = shaft(4, 4, 4, "shape-extra-shaft");
    extra_shaft.emplace("extra", V(true));
    auto center_shaft = shaft(4, 4, 4, "shape-center-shaft");
    center_shaft.at("center") = V(false);
    auto axis_shaft = shaft(4, 4, 4, "shape-axis-shaft");
    axis_shaft.at("axis") = V(false);
    auto span_shaft = shaft(4, 4, 4, "shape-span-shaft");
    span_shaft.at("half_span") = V(false);
    auto extra_gear = gear(4, 4, 4, "shape-extra-gear");
    extra_gear.emplace("extra", V(true));
    auto teeth_gear = gear(4, 4, 4, "shape-teeth-gear");
    teeth_gear.at("teeth") = V(false);
    auto kind_relay = relay("gearbox", 4, 8, 4, "shape-kind-relay", "y");
    kind_relay.at("kind") = V(false);
    auto axis_relay = relay("chain_drive", 4, 8, 4, "shape-axis-relay", "x", "z");
    axis_relay.at("relay_axis") = V(false);
    for (const auto& [request, reason] : std::vector<std::pair<O, std::string>>{
             {extra_shaft, "invalid_command"}, {center_shaft, "invalid_center"},
             {axis_shaft, "invalid_axis"}, {span_shaft, "invalid_shaft"},
             {extra_gear, "invalid_command"}, {teeth_gear, "invalid_gear"},
             {kind_relay, "invalid_command"}, {axis_relay, "invalid_command"}}) {
        const auto reply = host.command("P", request);
        check(!accepted(reply) && field<std::string>(reply, "reason") == reason,
              "Malformed transmission placement keeps its existing refusal meaning.");
    }
    const auto after_world = field<O>(host.checkpoint(), "world");
    const auto after_state = field<O>(V(after_world), "state");
    check(field<I>(before_projection, "revision") == field<I>(host.projection(), "revision") &&
          !factory::values::typed_difference(V(before_state), V(after_state)),
          "Malformed transmission wires leave native material, state and revision unchanged.");
}

void finite_oriented_train_and_restore() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})), "The finite half-U profile initializes.");
    const auto site = ground_channel_site();
    check(accepted(host.configure_terrain(site)), "The test binds explicit synthetic terrain.");
    observe(host, -3.3, 3.3, 1);
    const auto specs = field<O>(host.projection(), "part_specifications");
    bool saw_gear = false, saw_large = false;
    for (const auto& entry : std::get<A>(specs.at("P").storage())) {
        if (field<std::string>(entry, "kind") != "gear") continue;
        saw_gear |= field<I>(entry, "teeth") == 2 && field<I>(entry, "count") == 8;
        saw_large |= field<I>(entry, "teeth") == 4 && field<I>(entry, "count") == 2;
    }
    check(saw_gear, "The UI sees the actual carried gear specification, not only an aggregate count.");
    check(saw_large, "The native starter kit exposes two finite large cogs to the UI.");
    for (const auto& entry : std::get<A>(specs.at("Q").storage()))
        check(field<I>(entry, "count") == 0, "An empty actor kit cannot borrow the other actor's parts.");
    const auto wheel = create(host, ground_channel_wheel("wheel"));
    observe(host, 2.0, 0, 2);
    auto collector_wire = machine("collector", 0, "collector", "z");
    collector_wire.emplace("level", V(I{0}));
    const auto collector = create(host, collector_wire);
    observe(host, -4.95, 4.0, 3);
    create(host, gear(-24, 0, 12, "upper", "z"));
    for (I x : {I{-20}, I{-16}, I{-12}})
        create(host, gear(x, 0, 12, ("bridge-" + std::to_string(x)).c_str(), "z"));
    observe(host, -1.0, 4.0, 4);
    for (I x : {I{-8}, I{-4}})
        create(host, gear(x, 0, 12, ("bridge-" + std::to_string(x)).c_str(), "z"));
    const auto a = create(host, gear(-4, 0, 8, "gear-A", "z"));
    const auto original_b = gear(0, 0, 8, "gear-B", "z");
    const auto b = create(host, original_b);
    const I direction = -1;
    check(field<I>(motion(host, a), "numerator") == direction * 25 && field<I>(motion(host, a), "denominator") == 84 &&
          field<I>(motion(host, b), "numerator") == -direction * 25 && field<I>(motion(host, b), "denominator") == 84 &&
          field<I>(motion(host, collector), "numerator") == -direction * 25,
          "Meshing equal gears reverses the exact signed rate through the touching axles.");
    check(!field<bool>(motion(host, a), "overloaded") &&
              field<double>(motion(host, a), "capacity") > field<double>(motion(host, a), "impact") &&
              field<double>(motion(host, collector), "capacity") == field<double>(motion(host, a), "capacity"),
          "The host projects the same non-overloaded component capacity to its members.");
    check(field<bool>(host.projection(), "powered") &&
          field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 8 &&
          field<I>(V(field<O>(host.projection(), "parts")), "gear") == 2,
          "The powered train retains the remaining shafts and cogs.");
    const auto ticked = host.advance();
    check(field<I>(V(field<O>(ticked, "stock")), "source") == 4095 &&
          field<I>(V(field<O>(ticked, "stock")), "collector") == 1,
          "The current direction-insensitive machine adapter extracts one unit from the larger finite node.");
    check(accepted(host.command("P", target("remove", b, "remove-B"))),
          "An individual gear can be removed while the source stays enabled.");
    check(!field<bool>(host.projection(), "powered"), "Removing a gear disconnects the source.");
    observe(host, 0, 1.65, 5);
    const auto misaligned = create(host, gear(4, 0, 8, "misaligned", "z"));
    check(!field<bool>(host.projection(), "powered"), "A cog in the adjacent tile cannot power the collector through a diagonal gap.");
    check(accepted(host.command("P", target("remove", misaligned, "remove-misaligned"))),
          "The actual misplaced part returns before reconstruction.");
    observe(host, 0, 0, 6);
    const auto rebuilt = create(host, gear(0, 0, 8, "rebuild-B", "z"));
    check(rebuilt != b && field<bool>(host.projection(), "powered") &&
          field<I>(motion(host, rebuilt), "numerator") == -direction * 25,
          "Correct reconstruction restores geometric transmission with a new identity.");
    observe(host, 20, 20, 7);
    const auto retry = host.command("P", original_b);
    check(accepted(retry) && field<bool>(retry, "duplicate") && field<std::string>(retry, "entity") == b,
          "The original gear request replays before present pose and rebuilt-target lookup.");
    auto changed = original_b; changed.at("axis") = V("x");
    check(field<std::string>(host.command("P", changed), "reason") == "request_reuse",
          "Changing an old gear's orientation cannot retarget its cached request.");
    observe(host, 0, 0, 8);
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "The complete oriented train and original wire histories validate.");
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
              accepted(fresh.configure_terrain(site)) &&
              accepted(fresh.restore_checkpoint(saved)),
          "A fresh native Host restores the original profile without resetting its kit.");
    check(!factory::values::typed_difference(saved, fresh.checkpoint()),
          "Every typed quantity, axis, height, shaft, identity and old receipt survives exactly.");
    check(field<bool>(fresh.command("P", original_b), "duplicate"),
          "Restored historical gear lookup precedes fresh native readiness.");
}

void adjacent_axle_faces() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
          accepted(host.configure_terrain(factory::godot_world::tests::channel_site())),
          "The direct-axle control binds an invented flowing channel.");
    observe(host, -3.3, 3.3, 1);
    const auto wheel = create(host, channel_wheel("direct-wheel"));
    const auto upper = create(host, gear(-12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 4, "direct-upper", "z"));
    const auto redundant = host.command("P", connection(wheel, upper, "direct-redundant"));
    check(!accepted(redundant) && field<std::string>(redundant, "reason") == "individual_shaft_required" &&
          field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 8,
          "Adjacent wheel and cog faces do not consume a finite shaft.");
    check(field<std::string>(motion(host, wheel), "state") == "rotating" &&
          field<std::string>(motion(host, upper), "state") == "rotating" &&
          field<I>(motion(host, wheel), "numerator") == field<I>(motion(host, upper), "numerator") &&
          field<I>(motion(host, wheel), "denominator") == field<I>(motion(host, upper), "denominator"),
          "The full-size wheel powers an adjacent outboard cog through its actual axle faces.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "Fresh Host restore retains direct axle geometry and part custody exactly.");
    check(accepted(host.command("P", target("remove", upper, "direct-remove"))) &&
              !field<O>(host.projection(), "motion").contains(upper),
          "Removing the outboard cog removes the direct axle route.");

}

void refusals_and_legacy_shape() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})), "The refusal fixture initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The refusal fixture binds explicit synthetic terrain.");
    observe(host, -4 * factory::godot_world::site_geometry::height_step,
        8 * factory::godot_world::site_geometry::height_step, 1);
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
    auto overlapping = gear(-4, 4, 8, "actor-overlap");
    reject(overlapping, "actor_occupied");
    observe(host, 2.0, 0.0, 2);
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
    create(host, gear(-4, 8, 12, "large-second", "y", 4));
    const auto refused = host.command("P", gear(0, 8, 4, "exhausted-large", "y", 4));
    check(!accepted(refused) && field<std::string>(refused, "reason") == "unavailable_part",
          "The finite large-cog kit cannot place a third large cog.");
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

void finite_relays_and_restore() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})), "The relay Host initializes.");
    check(accepted(host.configure_terrain(low_flat_site())), "The relay Host binds its site.");
    // Keep the synthetic actor beside the complete frame, rather than inside
    // a formerly unmodelled post below the elevated relay shell.
    observe(host, -1.65, 0.0, 1);
    const auto horizontal = create(host, relay("gearbox", -4, 8, 4, "horizontal-box", "y"));
    observe(host, 0.0, 0.0, 2);
    const auto vertical = create(host, relay("vertical_gearbox", 0, 8, 4, "vertical-box", "x"));
    observe(host, 1.65, 0.0, 3);
    const auto chain = create(host, relay("chain_drive", 4, 8, 4, "chain-case", "x", "z"));
    const auto projection = host.projection();
    const auto& projected = field<O>(projection, "transmission_parts");
    check(field<std::string>(V(projected.at(horizontal)), "kind") == "gearbox" &&
          field<std::string>(V(projected.at(vertical)), "kind") == "vertical_gearbox" &&
          field<I>(V(projected.at(chain)), "relay_axis") == 2,
          "The confirmed projection preserves both gearbox variants and the chain link axis.");
    auto off_grid = relay("chain_drive", 5, 8, 4, "off-grid-chain", "x", "z");
    check(!accepted(host.command("P", off_grid)), "A chain case cannot leave the global tile grid.");
    check(!accepted(host.command("P", relay("gearbox", 8, 8, 4, "wrong-box", "x"))) &&
          !accepted(host.command("P", relay("chain_drive", 8, 8, 4, "wrong-link", "x", "x"))),
          "Horizontal gearbox and chain side-axis requirements are authoritative.");
    const auto saved = host.checkpoint();
    auto forged_root = std::get<O>(saved.storage());
    auto forged_world = field<O>(saved, "world");
    auto forged_history = field<O>(V(forged_world), "history");
    auto records = field<A>(V(forged_history), "records");
    bool changed = false;
    for (auto& entry : records) {
        auto record = std::get<O>(entry.storage());
        auto intent = field<O>(entry, "intent");
        if (field<std::string>(V(intent), "request") != "chain-case") continue;
        auto original = field<O>(V(intent), "wire");
        original.at("kind") = V("gearbox");
        intent.at("wire") = V(std::move(original));
        record.at("intent") = V(std::move(intent));
        entry = V(std::move(record));
        changed = true;
        break;
    }
    check(changed, "The saved chain request is present for a wire-only negative control.");
    forged_history.at("records") = V(std::move(records));
    forged_world.at("history") = V(std::move(forged_history));
    forged_root.at("world") = V(std::move(forged_world));
    const auto forged_reply = host.validate_checkpoint(V(std::move(forged_root)));
    check(!accepted(forged_reply) && field<std::string>(forged_reply, "reason") == "inconsistent_wire_history" &&
          !factory::values::typed_difference(saved, host.checkpoint()),
          "A saved relay wire cannot change kind while keeping the accepted native placement.");
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
          accepted(fresh.configure_terrain(low_flat_site())) &&
          accepted(fresh.restore_checkpoint(saved)), "The new relay parts survive a fresh native Host restore.");
    check(!factory::values::typed_difference(saved, fresh.checkpoint()),
          "Save and restore preserve relay geometry and finite custody exactly.");
    check(accepted(host.command("P", target("remove", chain, "remove-chain"))),
          "Removing a chain case refunds its exact finite item.");
    create(host, relay("chain_drive", 4, 8, 4, "replace-chain", "x", "z"));
}

void stacked_vertical_relay_support() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
          accepted(host.configure_terrain(low_flat_site())),
          "The stacked relay Host binds the disclosed flat site.");
    observe(host, 1.65, -1.65, 1);
    create(host, shaft(0, 4, 0, "lower-inlet", "x"));
    const auto lower = create(host, relay("vertical_gearbox", 4, 4, 0, "lower-vertical", "z"));
    const auto upper = create(host, relay("vertical_gearbox", 4, 8, 0, "upper-vertical", "z"));
    const auto high = create(host, relay("gearbox", 0, 8, 0, "upper-horizontal", "y"));
    const auto projection = host.projection();
    const auto& projected = field<O>(projection, "transmission_parts");
    const auto& support = field<O>(projected.at(upper), "support");
    const auto& foot = std::get<A>(support.at("foot").storage());
    check(std::abs(std::get<double>(foot[0].storage()) -
            4 * factory::godot_world::site_geometry::height_step) >=
            1.2 / grid_scale - 1e-9,
          "The elevated bearing uses a lateral post outside the lower relay shell.");
    const auto& high_support = field<O>(projected.at(high), "support");
    const auto& high_foot = std::get<A>(high_support.at("foot").storage());
    check(std::get<double>(high_foot[0].storage()) < -1.0 / grid_scale,
          "The upper horizontal case seats beyond both the lower shaft and adjacent relay: x=" +
          std::to_string(std::get<double>(high_foot[0].storage())));
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
          accepted(fresh.configure_terrain(low_flat_site())) &&
          accepted(fresh.restore_checkpoint(saved)) &&
          !factory::values::typed_difference(saved, fresh.checkpoint()),
          "The two finite relays and their derived supports survive a fresh Host restore.");
    (void)lower;
}

void relay_shell_terrain() {
    auto raised_corner = low_flat_site();
    const A axis{V(-128.0), V(0.0), V(0.8 / grid_scale), V(2.3 / grid_scale), V(128.0)};
    A heights(25, V(-1.0));
    heights[3 * 5 + 2] = V(3.0);
    raised_corner.at("axis") = V(axis);
    raised_corner.at("heights") = V(heights);
    Host clear;
    check(accepted(clear.initialize("cog-api", {"P", "Q"})) &&
          accepted(clear.configure_terrain(low_flat_site())), "The clear relay site binds.");
    observe(clear, -1.65, 1.65, 1);
    create(clear, relay("chain_drive", 0, 4, 4, "clear-case", "x", "z"));
    const auto saved = clear.checkpoint();
    Host blocked;
    check(accepted(blocked.initialize("cog-api", {"P", "Q"})) &&
          accepted(blocked.configure_terrain(raised_corner)), "The raised shell-corner site binds.");
    observe(blocked, -1.65, 1.65, 1);
    const auto refused = blocked.command("P", relay("chain_drive", 0, 4, 4, "buried-case", "x", "z"));
    check(!accepted(refused) && field<std::string>(refused, "reason") == "site_occupied",
          "A chain case cannot bury a shell corner outside its narrow axle footprint.");
    Host restored_site;
    check(accepted(restored_site.initialize("fresh", {"P", "Q"})) &&
          accepted(restored_site.configure_terrain(raised_corner)),
          "A fresh Host binds the raised corner before restore.");
    const auto restored = restored_site.restore_checkpoint(saved);
    check(!accepted(restored) && field<std::string>(restored, "reason") == "site_occupied",
          "Restoring a case against raised corner terrain enforces the same full shell: " +
          field<std::string>(restored, "reason"));
}

void powered_relay_route() {
    Host host;
    const auto valid = [&host](const char* stage) {
        const auto result = host.validate_checkpoint(host.checkpoint());
        check(accepted(result), std::string(stage) + " checkpoint validates" +
            (accepted(result) ? std::string{} : ": " + field<std::string>(result, "reason")));
    };
    check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
          accepted(host.configure_terrain(factory::godot_world::tests::channel_site())),
          "The powered relay fixture uses the ordinary native Host and channel site.");
    observe(host, -3.3, 3.3, 1);
    create(host, channel_wheel("relay-wheel"));
    valid("Wheel");
    create(host, shaft(-12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 4, "wheel-outboard-shaft", "z"));
    valid("Wheel outboard shaft");
    const auto first = create(host, relay("chain_drive", -12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 8, "first-chain", "z", "x"));
    valid("First chain");
    observe(host, -1.65, 1.65, 2);
    const auto second = create(host, relay("chain_drive", -12 * grid_scale + 4, 4 * grid_scale,
        4 * grid_scale + 8, "second-chain", "z", "x"));
    valid("Second chain");
    observe(host, -1.65, 3.3, 3);
    const auto gearbox = create(host, relay("gearbox", -12 * grid_scale + 4, 4 * grid_scale,
        4 * grid_scale + 12, "relay-box", "y"));
    valid("Gearbox");
    observe(host, 0.0, 3.3, 4);
    const auto output = create(host, shaft(-12 * grid_scale + 8, 4 * grid_scale,
        4 * grid_scale + 12, "relay-output", "x"));
    valid("Output shaft");
    observe(host, -3.3, 3.3, 5);
    const auto motion_detail = [&](const std::string& id) {
        const auto value = motion(host, id);
        return field<std::string>(value, "state") + " " +
            std::to_string(field<I>(value, "numerator")) + "/" +
            std::to_string(field<I>(value, "denominator"));
    };
    check(field<std::string>(motion(host, first), "state") == "rotating" &&
          field<I>(motion(host, first), "numerator") == field<I>(motion(host, second), "numerator") &&
          field<std::string>(motion(host, gearbox), "state") == "rotating" &&
          field<std::string>(motion(host, output), "state") == "rotating" &&
          field<I>(motion(host, first), "numerator") == field<I>(motion(host, gearbox), "numerator") &&
          field<I>(motion(host, first), "numerator") == field<I>(motion(host, output), "numerator") &&
          field<I>(motion(host, first), "denominator") == field<I>(motion(host, output), "denominator"),
          "A placed waterwheel drives both chain cases, the gearbox and its turned shaft: " +
              motion_detail(first) + ", " + motion_detail(second) + ", " +
              motion_detail(gearbox) + ", " + motion_detail(output));
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
          accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())),
          "A fresh Host binds the same channel before restoring the powered relay.");
    const auto restored = fresh.restore_checkpoint(saved);
    check(accepted(restored),
          "A powered relay route survives a fresh Host checkpoint restore" +
              (accepted(restored) ? std::string{} : ": " + field<std::string>(restored, "reason")));
    check(!factory::values::typed_difference(saved, fresh.checkpoint()),
          "The restored powered relay route retains exact native topology, custody and signed motion.");
}

void ground_collector_output_gap() {
    auto site = ground_channel_site();
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
              accepted(host.configure_terrain(site)),
          "The perpendicular-line Host binds its synthetic terrain.");
    observe(host, -3.3, 3.3, 1);
    std::string wheel, collector, first, last, belt;

    wheel = create(host, ground_channel_wheel("line-machine-0"));
    observe(host, -4.95, 4.0, 2);
    const auto inlet = create(host, shaft(-24, 0, 12, "line-drive-first"));
    observe(host, -1.0, 4.0, 3);
    const auto outlet = create(host, shaft(-4, 0, 12, "line-drive-last"));
    auto drive = wire("place_belt_span", "line-drive-span");
    drive.emplace("from", V(inlet)); drive.emplace("to", V(outlet));
    observe(host, -2.9, 3.5, 4);
    create(host, drive);
    observe(host, 2.0, 0.0, 5);
    auto collector_wire = machine("collector", 0, "line-collector", "z");
    collector_wire.emplace("level", V(I{0}));
    collector = create(host, collector_wire);
    observe(host, -1.0, 4.0, 6);
    create(host, gear(-4, 0, 8, "line-bridge", "z", 2));
    create(host, gear(0, 0, 8, "line-collector-cog", "z", 2));
    observe(host, 2.0, 3.0, 7);
    create(host, gear(4, 0, 8, "line-output-bridge", "z", 2));
    create(host, gear(8, 0, 8, "line-belt-cog", "z", 2));
    first = create(host, shaft(8, 0, 4, "line-first"));
    last = create(host, shaft(12, 0, 4, "line-last"));
    auto install = wire("place_belt_span", "line-span");
    install.emplace("from", V(first)); install.emplace("to", V(last));
    belt = create(host, install);
    observe(host, -3.3, 1.65, 8);

    const auto projected = host.projection();
    check(field<A>(projected, "links").empty() && field<O>(projected, "belt_spans").size() == 2 &&
              field<I>(V(field<O>(projected, "parts")), "shaft") == 4 &&
              field<I>(V(field<O>(projected, "parts")), "gear") == 6,
          "The connected line accounts for its cogs and physical belt shafts.");
    check(field<I>(motion(host, wheel), "numerator") == 25 &&
              field<I>(motion(host, collector), "numerator") == -25 &&
              field<I>(motion(host, first), "numerator") == -25 &&
              field<I>(motion(host, last), "numerator") == -25 &&
              field<I>(motion(host, first), "denominator") == 84 &&
              field<I>(motion(host, last), "denominator") == 84,
          "The output belt shafts share the exact signed rate from the geared source: " +
              std::to_string(field<I>(motion(host, wheel), "numerator")) + "," +
              std::to_string(field<I>(motion(host, collector), "numerator")) + "," +
              std::to_string(field<I>(motion(host, first), "numerator")) + "," +
              std::to_string(field<I>(motion(host, last), "numerator")) + ".");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
              accepted(fresh.configure_terrain(site)) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "The full perpendicular route and finite kit survive fresh Host restoration.");
    for (int tick = 0; tick < 96; ++tick) (void)host.advance();
    const auto reversed = host.projection();
    const auto blocked_slots = field<A>(field<O>(reversed, "belt_spans").at(belt), "slots");

    const auto stock = field<O>(reversed, "stock");
    check(field<I>(V(stock), "source") == 4064 && field<I>(V(stock), "collector") == 32 &&
          field<I>(V(stock), "input") == 0 && raw_on_belts(reversed) == 0 &&
          field<A>(reversed, "dropped_material").empty() &&
          std::all_of(blocked_slots.begin(), blocked_slots.end(), [](const V& slot) {
              return slot.type() == factory::values::Type::null;
          }),
          "The clear two-U output belt stays empty while the powered ground collector retains 32 finite raw units.");
    observe(host, 2.0, 3.0, 9);
    const auto direct = create(host, shaft(4, 0, 4, "line-direct-mouth"));
    auto blocked = wire("place_belt_span", "line-direct-overlap");
    blocked.emplace("from", V(direct)); blocked.emplace("to", V(first));
    const auto before = host.projection();
    const auto refusal = host.command("P", blocked);
    check(!accepted(refusal) && field<std::string>(refusal, "reason") == "occupied" &&
          !factory::values::typed_difference(V(field<O>(before, "stock")), V(field<O>(host.projection(), "stock"))) &&
          !factory::values::typed_difference(V(field<O>(before, "parts")), V(field<O>(host.projection(), "parts"))) &&
          !factory::values::typed_difference(V(field<O>(before, "belt_spans")), V(field<O>(host.projection(), "belt_spans"))),
          "The required one-U collector output span intersects its unchanged shell without spending a belt or raw stock.");
    const auto duplicate = host.command("P", blocked);
    check(!accepted(duplicate) && field<bool>(duplicate, "duplicate") &&
          field<std::string>(duplicate, "reason") == "occupied",
          "The occupied output span refusal replays without another admission.");
    const auto saved_empty = host.checkpoint();
    Host restored_empty;
    check(accepted(restored_empty.initialize("empty-route", {"P", "Q"})) &&
          accepted(restored_empty.configure_terrain(site)) &&
          accepted(restored_empty.restore_checkpoint(saved_empty)) &&
          !factory::values::typed_difference(saved_empty, restored_empty.checkpoint()),
          "The powered ground collector and refused output overlap restore exactly in a fresh Host.");
    for (int tick = 0; tick < 40; ++tick) (void)restored_empty.advance();
    const auto after = restored_empty.projection();
    check(field<I>(V(field<O>(after, "stock")), "source") == 4064 &&
          field<I>(V(field<O>(after, "stock")), "collector") == 32 &&
          raw_on_belts(after) == 0 && field<A>(after, "dropped_material").empty(),
          "Continued drive does not invent collector-to-belt transfer across the physical gap.");

}

void typed_loose_host() {
    Host seed;
    check(accepted(seed.initialize("cog-api", {"P"})) &&
              accepted(seed.configure_terrain(factory::godot_world::tests::flat_site())),
          "The typed loose-material fixture binds a synthetic site.");
    auto envelope = std::get<O>(seed.checkpoint().storage());
    auto logical = std::get<O>(envelope.at("world").storage());
    auto state = std::get<O>(logical.at("state").storage());
    auto material = std::get<O>(state.at("material").storage());
    auto stock = std::get<O>(material.at("stock").storage());
    stock.at("source") = V(field<I>(V(stock), "source") - 3);
    const V lot(O{{"id", V(I{1})}, {"recipe", V(O{{"input_units_per_product", V(I{1})},
        {"cycle_ticks", V(I{2})}, {"output_form", V("plate")}})},
                 {"remaining_ticks", V(I{1})}, {"completed_subticks", V(I{123})},
                 {"work_remainder", V(I{0})}, {"work_remainder_denominator", V(I{1})}});
    material.at("stock") = V(std::move(stock));
    material.at("next_work_id") = V(I{2});
    material.at("dropped_material") = V(A{V(O{{"point", V(A{V(I{0}), V(I{0}), V(I{4})})},
        {"cargo", V(O{{"raw_units", V(I{1})}, {"products", V(I{1})}, {"work_lots", V(A{lot})}})}})});
    state.at("material") = V(std::move(material));
    logical.at("state") = V(std::move(state));
    envelope.at("world") = V(std::move(logical));
    Host loaded;
    check(accepted(loaded.initialize("fresh", {"P"})) &&
              accepted(loaded.configure_terrain(factory::godot_world::tests::flat_site())) &&
              accepted(loaded.restore_checkpoint(V(envelope))),
          "A fresh Host restores a conserved mixed loose stack.");
    const auto drop = field<A>(loaded.projection(), "dropped_material").front();
    check(field<I>(drop, "raw") == 1 && field<I>(drop, "products") == 1 &&
              field<I>(field<A>(drop, "work_lots").front(), "completed_subticks") == 123,
          "The Host projects exact raw, plate and partial-work custody.");
    auto expected = std::get<O>(drop.storage()); expected.erase("center");
    auto pickup = wire("pickup_material", "typed-loose-pickup");
    pickup.emplace("center", V(A{V(I{0}), V(I{0}), V(I{4})})); pickup.emplace("expected", V(expected));
    observe(loaded, 50, 50, 1);
    const auto distant = loaded.command("P", pickup);
    check(!accepted(distant) && field<A>(loaded.projection(), "dropped_material").size() == 1,
          "A distant actor cannot pick up mixed loose material.");
    observe(loaded, 0, 0, 2);
    pickup.at("request") = V("typed-loose-stale");
    pickup.at("expected") = V(O{{"raw", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(A{})}});
    const auto stale = loaded.command("P", pickup);
    check(!accepted(stale) && field<std::string>(stale, "reason") == "drop_changed" &&
              field<A>(loaded.projection(), "dropped_material").size() == 1,
          "A stale selection cannot acquire the mixed stack.");
    pickup.at("request") = V("typed-loose-exact"); pickup.at("expected") = V(expected);
    const auto receipt = loaded.command("P", pickup);
    const auto cargo = field<O>(loaded.projection(), "cargo").at("P");
    check(accepted(receipt) && field<I>(cargo, "raw") == 1 && field<I>(cargo, "products") == 1 &&
              field<I>(field<A>(cargo, "work_lots").front(), "completed_subticks") == 123 &&
              field<A>(loaded.projection(), "dropped_material").empty(),
          "The exact stack enters the actor's cargo with work progress intact.");
    Host restored;
    check(accepted(restored.initialize("another", {"P"})) &&
              accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) &&
              accepted(restored.restore_checkpoint(loaded.checkpoint())) &&
              field<bool>(restored.command("P", pickup), "duplicate") &&
              field<I>(field<A>(field<O>(restored.projection(), "cargo").at("P"), "work_lots").front(), "id") == 1,
          "A fresh Host preserves typed cargo and the original idempotent pickup receipt.");
}

void retired_belt_machine() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
          "The retired belt Host binds its site.");
    observe(host, -1.65, 3.3, 1);
    const auto before = world_state(host);
    for (const auto* axis : std::array<const char*, 4>{"x", "y", "z", nullptr}) {
        const auto request = std::string("retired-belt-") + (axis ? axis : "default");
        const auto reply = host.command("P", machine("belt", 1, request.c_str(), axis));
        check(!accepted(reply) && field<std::string>(reply, "reason") == "unknown_kind" &&
                  !factory::values::typed_difference(before, world_state(host)),
              "A retired single-cell belt is refused without consuming the carried span part.");
    }
}

void select_belt_shaft_host() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) && accepted(host.configure_terrain(low_flat_site())),
          "The belt selection Host binds a synthetic flat site.");
    observe(host, 0, -1.65, 1);
    const auto first = create(host, shaft(0, 0, 0, "selection-shaft"));
    const auto state = world_state(host);
    auto selection = target("select_belt_shaft", first, "select-first");
    observe(host, 30, -1.65, 2);
    const auto far = host.command("P", selection);
    check(!accepted(far) && field<std::string>(far, "reason") == "out_of_reach" &&
              !factory::values::typed_difference(state, world_state(host)),
          "Selecting a distant first shaft is refused without changing custody.");
    selection.at("request") = V("select-near");
    observe(host, 0, -1.65, 3);
    check(accepted(host.command("P", selection)) && !factory::values::typed_difference(state, world_state(host)),
          "A nearby shaft selection is recorded without placing or consuming a belt.");
    const auto saved = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize("fresh", {"P"})) && accepted(restored.configure_terrain(low_flat_site())) &&
              accepted(restored.restore_checkpoint(saved)) && field<bool>(restored.command("P", selection), "duplicate"),
          "The selection receipt survives checkpoint restore and exact replay.");
    check(accepted(host.command("P", target("remove", first, "selection-remove"))) &&
              accepted(host.validate_checkpoint(host.checkpoint())),
          "Removing the selected shaft preserves the historical selection receipt.");
}

void long_selected_belt_host() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})) && accepted(host.configure_terrain(low_flat_site())),
          "The long belt fixture binds a synthetic site.");
    observe(host, 0, -1.65, 1);
    const auto first = create(host, shaft(0, 0, 0, "long-first"));
    check(accepted(host.command("P", target("select_belt_shaft", first, "long-selection"))),
          "The actor selects the first shaft while nearby.");
    observe(host, 31.35 / grid_scale, -1.65, 2);
    const auto last = create(host, shaft(76, 0, 0, "long-last"));
    auto span = wire("place_selected_belt_span", "long-span");
    span.emplace("from", V(first)); span.emplace("to", V(last)); span.emplace("selection", V("forged"));
    const auto forged = host.command("P", span);
    check(!accepted(forged) && field<std::string>(forged, "reason") == "invalid_belt_selection",
          "An unrecorded first-shaft selection cannot authorize a distant belt.");
    check(accepted(host.publish_actor("Q", {V(31.35 / grid_scale), V(1.0), V(-3.3)}, 1)), "A second actor is nearby and clear.");
    auto stolen = span; stolen.at("client") = V("Q"); stolen.at("request") = V("long-stolen");
    stolen.at("selection") = V("long-selection");
    const auto other_actor = host.command("Q", stolen);
    check(!accepted(other_actor) && field<std::string>(other_actor, "reason") == "invalid_belt_selection",
          "Another actor cannot reuse the first actor's shaft selection.");
    span.at("request") = V("long-span-far"); span.at("selection") = V("long-selection");
    observe(host, 20.0 / grid_scale, -1.65, 3);
    const auto far = host.command("P", span);
    check(!accepted(far) && field<std::string>(far, "reason") == "out_of_reach",
          "A valid first selection does not authorize a distant second endpoint.");
    observe(host, 31.35 / grid_scale, -1.65, 4);
    span.at("request") = V("long-span-valid");
    const auto id = create(host, span);
    check(field<O>(host.projection(), "belt_spans").contains(id) &&
              field<I>(V(field<O>(host.projection(), "parts")), "belt") == 1,
          "The full twenty-tile belt is built from the actor's second endpoint and consumes its belt.");
    auto reused = span; reused.at("request") = V("long-span-reuse");
    const auto repeat = host.command("P", reused);
    check(!accepted(repeat) && field<std::string>(repeat, "reason") == "invalid_belt_selection",
          "A successful first selection cannot be reused to install another belt.");
    const auto saved = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize("fresh", {"P", "Q"})) && accepted(restored.configure_terrain(low_flat_site())) &&
              accepted(restored.restore_checkpoint(saved)) && field<bool>(restored.command("P", span), "duplicate"),
          "The long belt and linked selection receipt survive checkpoint and exact replay.");
    observe(restored, 15.675 / grid_scale, -20, 1);
    const auto far_remove = restored.command("P", target("remove_belt_span", id, "long-remove-far"));
    check(!accepted(far_remove) && field<std::string>(far_remove, "reason") == "out_of_reach" &&
              field<O>(restored.projection(), "belt_spans").contains(id),
          "Removing a long belt remains restricted to a reachable path tile.");
    observe(restored, 15.675 / grid_scale, -1.65, 2);
    check(accepted(restored.command("P", target("remove_belt_span", id, "long-remove"))) &&
              field<O>(restored.projection(), "belt_spans").empty() &&
              field<I>(V(field<O>(restored.projection(), "parts")), "belt") == 2 &&
              accepted(restored.validate_checkpoint(restored.checkpoint())),
          "An empty long belt can be reclaimed from a reachable middle tile after restoration.");
}

void belt_span_host_commands() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(low_flat_site())),
          "The belt span Host binds a synthetic flat site.");
    observe(host, 0, -1.65, 1);
    const auto left = create(host, shaft(0, 0, 0, "span-left"));
    observe(host, 3.3, -1.65, 2);
    const auto right = create(host, shaft(8, 0, 0, "span-right"));
    auto install = wire("place_belt_span", "span-place");
    install.emplace("from", V(left)); install.emplace("to", V(right));
    observe(host, 1.65, 0, 3);
    const auto blocked = host.command("P", install);
    check(!accepted(blocked) && field<std::string>(blocked, "reason") == "actor_occupied",
          "A synthetic actor occupying the span prevents installation.");
    install.at("request") = V("span-place-clear");
    observe(host, 1.65, -1.65, 4);
    const auto id = create(host, install);
    const auto projected = field<O>(host.projection(), "belt_spans");
    check(projected.contains(id) && field<std::string>(projected.at(id), "from") == left &&
              field<std::string>(projected.at(id), "to") == right &&
              field<I>(V(field<O>(host.projection(), "parts")), "belt") == 1,
          "The projection identifies the actual endpoints and consumed finite belt.");
    const auto before_bad_belt = host.projection();
    const auto before_bad_belt_world = world_state(host);
    auto bad_place = wire("place_belt_span", "bad-belt-place");
    bad_place.emplace("from", V(I{1})); bad_place.emplace("to", V(right));
    auto bad_selected = wire("place_selected_belt_span", "bad-belt-selected");
    bad_selected.emplace("from", V(left)); bad_selected.emplace("to", V(right));
    bad_selected.emplace("selection", V(I{1}));
    auto bad_remove = target("remove_belt_span", id, "bad-belt-remove");
    bad_remove.emplace("slot", V(I{0}));
    auto bad_select = target("select_belt_shaft", left, "bad-belt-select");
    bad_select.at("entity") = V(I{1});
    auto bad_recover = target("recover_belt_slot", id, "bad-belt-recover");
    bad_recover.emplace("slot", V(1.0)); bad_recover.emplace("expected", V(O{}));
    auto bad_load = target("load_belt_slot", id, "bad-belt-load");
    bad_load.emplace("slot", V(I{1})); bad_load.emplace("item", V(false));
    bad_load.emplace("work_id", V(I{0}));
    for (const auto& malformed : {bad_place, bad_selected, bad_remove,
                                  bad_select, bad_recover, bad_load}) {
        const auto refused = host.command("P", malformed);
        check(!accepted(refused) && field<std::string>(refused, "reason") == "invalid_command",
              "Malformed belt requests refuse before topology or slot custody changes.");
    }
    const auto after_bad_belt = host.projection();
    check(field<I>(before_bad_belt, "revision") == field<I>(after_bad_belt, "revision") &&
          !factory::values::typed_difference(before_bad_belt_world, world_state(host)) &&
          !factory::values::typed_difference(V(field<O>(before_bad_belt, "belt_spans")),
              V(field<O>(after_bad_belt, "belt_spans"))) &&
          !factory::values::typed_difference(V(field<O>(before_bad_belt, "cargo")),
              V(field<O>(after_bad_belt, "cargo"))),
          "All six malformed belt requests preserve revision, native state, slots and cargo.");
    const auto before_pulley = world_state(host);
    const auto wrong_pulley = host.command("P", shaft(4, 0, 0, "span-wrong-pulley", "x"));
    check(!accepted(wrong_pulley) && !factory::values::typed_difference(before_pulley, world_state(host)),
          "A shaft across the belt spindle is refused without changing the world or kit.");
    const auto shaft_stock = field<I>(V(field<O>(host.projection(), "parts")), "shaft");
    const auto pulley = create(host, shaft(4, 0, 0, "span-add-pulley"));
    check(field<O>(host.projection(), "belt_spans").contains(id) &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == shaft_stock - 1,
          "A matching shaft can be added to the middle of an existing belt from the finite kit.");
    const auto pulley_checkpoint = host.checkpoint();
    Host pulley_restored;
    check(accepted(pulley_restored.initialize("fresh", {"P"})) &&
              accepted(pulley_restored.configure_terrain(low_flat_site())) &&
              accepted(pulley_restored.restore_checkpoint(pulley_checkpoint)) &&
              !factory::values::typed_difference(pulley_checkpoint, pulley_restored.checkpoint()),
          "The installed intermediate pulley and belt survive checkpoint restoration.");
    check(accepted(host.command("P", target("remove", pulley, "span-remove-pulley"))) &&
              field<O>(host.projection(), "belt_spans").contains(id) &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == shaft_stock &&
              accepted(host.validate_checkpoint(host.checkpoint())),
          "Removing the intermediate shaft refunds it and leaves the belt and a valid checkpoint.");
    const auto intrusion = host.command("P", gear(4, 0, 0, "span-obstruction", "z"));
    check(!accepted(intrusion) && field<std::string>(intrusion, "reason") == "occupied",
          "A later cog cannot be placed through the installed belt.");
    const auto checkpoint = host.checkpoint();
    Host inclined;
    check(accepted(inclined.initialize("cog-api", {"P"})) && accepted(inclined.configure_terrain(low_flat_site())),
          "The inclined fixture binds its own lower terrain.");
    check(accepted(inclined.publish_actor("P", {V(0.0), V(0.825), V(-1.65)}, 1)), "The actor reaches the low shaft.");
    const auto low = create(inclined, shaft(0, 0, 0, "incline-low"));
    check(accepted(inclined.publish_actor("P", {V(3.3), V(4.125), V(-1.65)}, 2)), "The actor reaches the high shaft.");
    const auto high = create(inclined, shaft(8, 8, 0, "incline-high"));
    check(accepted(inclined.publish_actor("P", {V(1.65), V(2.475), V(-1.65)}, 3)), "The actor reaches both inclined endpoints.");
    auto inclined_wire = wire("place_belt_span", "incline-span");
    inclined_wire.emplace("from", V(low)); inclined_wire.emplace("to", V(high));
    create(inclined, inclined_wire);
    Host shallow;
    check(accepted(shallow.initialize("fresh", {"P"})) &&
              accepted(shallow.configure_terrain(factory::godot_world::tests::flat_site())), "The shallower site binds.");
    const auto buried_incline = shallow.validate_checkpoint(inclined.checkpoint());
    check(!accepted(buried_incline) && field<std::string>(buried_incline, "reason") == "site_occupied",
          "An inclined span whose lower physical overhang enters terrain cannot be restored.");
    auto with_item = std::get<O>(checkpoint.storage());
    auto logical = std::get<O>(with_item.at("world").storage());
    auto saved_state = std::get<O>(logical.at("state").storage());
    auto material = std::get<O>(saved_state.at("material").storage());
    auto stock = std::get<O>(material.at("stock").storage());
    stock.at("source") = V(field<I>(V(stock), "source") - 1);
    auto lanes = std::get<O>(material.at("belt_lanes").storage());
    auto lane = std::get<O>(lanes.at(id).storage());
    auto slots = std::get<A>(lane.at("slots").storage());
    slots.at(1) = V(O{{"raw_units", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(A{})}});
    lane.at("phase") = V(I{321}); lane.at("slots") = V(std::move(slots));
    lanes.at(id) = V(std::move(lane)); material.at("belt_lanes") = V(std::move(lanes));
    material.at("stock") = V(std::move(stock)); saved_state.at("material") = V(std::move(material));
    logical.at("state") = V(std::move(saved_state)); with_item.at("world") = V(std::move(logical));
    Host loaded;
    check(accepted(loaded.initialize("projection", {"P"})) &&
              accepted(loaded.configure_terrain(low_flat_site())) &&
              accepted(loaded.restore_checkpoint(V(with_item))),
          "A valid synthetic checkpoint restores an item in the span's authoritative lane.");
    const auto projected_span = field<O>(loaded.projection(), "belt_spans").at(id);
    const auto projected_slots = field<A>(projected_span, "slots");
    check(projected_slots.size() == 3 && projected_slots[0].type() == factory::values::Type::null &&
              field<I>(projected_slots[1], "raw") == 1 && field<I>(projected_span, "phase") == 321,
          "The Host projects the exact confirmed lane slot and retained phase.");
    for (const bool work : {false, true}) {
        auto typed_envelope = with_item;
        auto typed_world = std::get<O>(typed_envelope.at("world").storage());
        auto typed_state = std::get<O>(typed_world.at("state").storage());
        auto typed_material = std::get<O>(typed_state.at("material").storage());
        auto typed_lanes = std::get<O>(typed_material.at("belt_lanes").storage());
        auto typed_lane = std::get<O>(typed_lanes.at(id).storage());
        auto typed_slots = std::get<A>(typed_lane.at("slots").storage());
        A lots;
        if (work) {
            lots.emplace_back(O{{"id", V(I{1})}, {"recipe", V(O{{"input_units_per_product", V(I{1})},
                {"cycle_ticks", V(I{2})}, {"output_form", V("plate")}})},
                {"remaining_ticks", V(I{1})}, {"completed_subticks", V(I{123})},
                {"work_remainder", V(I{0})}, {"work_remainder_denominator", V(I{1})}});
            typed_material.at("next_work_id") = V(I{2});
        }
        typed_slots[1] = V(O{{"raw_units", V(I{0})}, {"products", V(I{work ? 0 : 1})}, {"work_lots", V(std::move(lots))}});
        typed_lane.at("slots") = V(std::move(typed_slots));
        typed_lanes.at(id) = V(std::move(typed_lane));
        typed_material.at("belt_lanes") = V(std::move(typed_lanes));
        typed_state.at("material") = V(std::move(typed_material));
        typed_world.at("state") = V(std::move(typed_state));
        typed_envelope.at("world") = V(std::move(typed_world));
        Host typed;
        check(accepted(typed.initialize("typed-line", {"P"})) && accepted(typed.configure_terrain(low_flat_site())) &&
                  accepted(typed.restore_checkpoint(V(typed_envelope))),
              "The Host restores the conserved typed belt item.");
        check(field<I>(typed.projection(), "line_belt_raw") == (work ? 1 : 0),
              "The line count includes unfinished work but does not label a plate as a blank.");
    }
    auto recover = target("recover_belt_slot", id, "span-recover-far");
    recover.emplace("slot", V(I{1})); recover.emplace("expected", projected_slots[1]);
    observe(loaded, 50, 50, 1);
    check(!accepted(loaded.command("P", recover)), "Recovery refuses an actor far from the occupied slot.");
    observe(loaded, 1.65, -1.65, 2);
    recover.at("request") = V("span-recover-stale");
    recover.at("expected") = V(O{{"raw", V(I{0})}, {"products", V(I{1})}, {"work_lots", V(A{})}});
    check(!accepted(loaded.command("P", recover)) && field<I>(field<A>(field<O>(loaded.projection(), "belt_spans").at(id), "slots")[1], "raw") == 1,
          "A changed selection cannot take a replacement item.");
    recover.at("request") = V("span-recover"); recover.at("expected") = projected_slots[1];
    check(accepted(loaded.command("P", recover)) &&
              field<I>(field<O>(loaded.projection(), "cargo").at("P"), "raw") == 1 &&
              field<A>(field<O>(loaded.projection(), "belt_spans").at(id), "slots")[1].type() == factory::values::Type::null,
          "The confirmed item moves into the actor's canonical custody.");
    auto load = target("load_belt_slot", id, "span-load");
    load.emplace("slot", V(I{1})); load.emplace("item", V("raw")); load.emplace("work_id", V(I{0}));
    observe(loaded, 50, 50, 3);
    check(!accepted(loaded.command("P", load)), "Loading also refuses an actor far from the slot.");
    observe(loaded, 1.65, -1.65, 4); load.at("request") = V("span-load-near");
    check(accepted(loaded.command("P", load)) &&
              field<I>(field<O>(loaded.projection(), "cargo").at("P"), "raw") == 0 &&
              field<I>(field<A>(field<O>(loaded.projection(), "belt_spans").at(id), "slots")[1], "raw") == 1,
          "The Host loads one carried blank into the confirmed empty slot.");
    check(field<bool>(loaded.command("P", load), "duplicate") && accepted(loaded.validate_checkpoint(loaded.checkpoint())),
          "The loaded slot and its original wire receipt survive retry and checkpoint validation.");
    recover.at("request") = V("span-recover-after-load");
    check(accepted(loaded.command("P", recover)), "The newly loaded item remains recoverable.");
    check(accepted(loaded.command("P", target("remove_belt_span", id, "span-remove-recovered"))) &&
              field<bool>(loaded.command("P", recover), "duplicate") && accepted(loaded.validate_checkpoint(loaded.checkpoint())),
          "The emptied span can be removed and the recovery history survives removal and validation.");
    auto obstructed_site = low_flat_site();
    obstructed_site.at("obstacles") = V(A{V(A{V(A{V(1.5), V(0.4), V(-0.2)}),
                                                 V(A{V(1.8), V(0.7), V(0.2)})})});
    Host obstructed;
    check(accepted(obstructed.initialize("blocked", {"P"})) &&
              accepted(obstructed.configure_terrain(obstructed_site)) &&
              !accepted(obstructed.validate_checkpoint(checkpoint)),
          "A restored belt cannot pass through an obstacle in the bound site.");
    Host restored;
    check(accepted(restored.initialize("fresh", {"P"})) &&
              accepted(restored.configure_terrain(low_flat_site())) &&
              accepted(restored.restore_checkpoint(checkpoint)) &&
              !factory::values::typed_difference(checkpoint, restored.checkpoint()),
          "A fresh Host restores the span and both original wire histories.");
    check(field<bool>(restored.command("P", install), "duplicate"), "Construction retry keeps its original identity.");
    observe(restored, 1.65, -1.65, 1);
    const auto removed = restored.command("P", target("remove_belt_span", id, "span-remove"));
    check(accepted(removed) && field<O>(restored.projection(), "belt_spans").empty() &&
              field<I>(V(field<O>(restored.projection(), "parts")), "belt") == 2,
          "The Host removes the span and refunds its one belt.");
    check(accepted(restored.validate_checkpoint(restored.checkpoint())),
          "The removed span and its immutable wire history remain restorable.");
}

void nonhorizontal_span_host() {
    struct Case { const char* axis; I start_y, x, y, z; };
    for (const auto& example : {Case{"z", 4, 8, 12, 0}, Case{"z", 12, 8, 4, 0},
                                Case{"x", 4, 0, 12, 8}, Case{"x", 12, 0, 4, 8},
                                Case{"z", 4, 0, 12, 0}, Case{"y", 4, 8, 4, 0}}) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(low_flat_site())),
              "A nonhorizontal Host binds a flat synthetic site.");
        const auto observe_at = [&](double x, double y, double z, I epoch) {
            check(accepted(host.publish_actor("P", {V(x), V(y), V(z)}, epoch)), "Synthetic actor observation is accepted.");
        };
        observe_at(0, (0.825 + example.start_y * 1.65 / 4) * u_scale, -1.65, 1);
        const auto first = create(host, shaft(0, example.start_y, 0, "3d-first", example.axis));
        observe_at(example.x * 1.65 / 4 * u_scale,
            (0.825 + example.y * 1.65 / 4) * u_scale,
            example.z * 1.65 / 4 * u_scale - 1.65, 2);
        const auto last = create(host, shaft(example.x, example.y, example.z, "3d-last", example.axis));
        auto install = wire("place_belt_span", "3d-blocked");
        install.emplace("from", V(first)); install.emplace("to", V(last));
        const double mx = example.x * 1.65 / 8 * u_scale;
        const double my = (0.825 + (example.start_y + example.y) * 1.65 / 8) * u_scale;
        const double mz = example.z * 1.65 / 8 * u_scale;
        observe_at(mx, my, mz, 3);
        const auto blocked = host.command("P", install);
        check(!accepted(blocked) && field<std::string>(blocked, "reason") == "actor_occupied", "A body intersecting the path refuses placement.");
        observe_at(mx, my, mz - 1.65, 4);
        install.at("request") = V("3d-clear");
        const auto span = create(host, install);
        check(field<O>(host.projection(), "belt_spans").contains(span), "The Host admits the nonhorizontal span.");
        auto pulley = create(host, shaft(example.x / 2, (example.start_y + example.y) / 2,
                                                example.z / 2, "3d-add-pulley", example.axis));
        if (std::string(example.axis) == "z" && example.x == 8 && example.start_y == 4) {
            const auto obstruction = host.command("P", gear(4, 8, 0, "3d-cog-intersection", "z"));
            check(!accepted(obstruction) && field<std::string>(obstruction, "reason") == "occupied",
                  "A later cog cannot intersect the inclined body.");
            const auto before = V(field<O>(field<O>(host.projection(), "transmission_parts").at(pulley), "support"));
            create(host, gear(4, 0, 0, "3d-cog-below", "z"));
            const auto after = V(field<O>(field<O>(host.projection(), "transmission_parts").at(pulley), "support"));
            check(!factory::values::typed_difference(before, after),
                  "A lower cog fits without moving the raised pulley's physical stand.");
        }
        const auto checkpoint = host.checkpoint();
        Host loaded;
        check(accepted(loaded.initialize("fresh", {"P"})) &&
                  accepted(loaded.configure_terrain(low_flat_site())) &&
                  accepted(loaded.restore_checkpoint(checkpoint)) &&
                  !factory::values::typed_difference(checkpoint, loaded.checkpoint()), "The span survives a fresh Host restore.");
        observe_at(mx, my, mz - 1.65, 5);
        check(accepted(host.command("P", target("remove", pulley, "3d-remove-pulley"))) &&
                  field<O>(host.projection(), "belt_spans").contains(span),
              "Removing an intermediate pulley preserves each nonhorizontal belt.");
        auto blocked_site = low_flat_site();
        blocked_site.at("obstacles") = V(A{V(A{V(A{V(mx - 0.1 * u_scale), V(my - 0.1 * u_scale), V(mz - 0.1 * u_scale)}),
                                                 V(A{V(mx + 0.1 * u_scale), V(my + 0.1 * u_scale), V(mz + 0.1 * u_scale)})})});
        Host obstructed;
        check(accepted(obstructed.initialize("fresh", {"P"})) && accepted(obstructed.configure_terrain(blocked_site)) &&
                  !accepted(obstructed.validate_checkpoint(checkpoint)), "Restore refuses a site obstacle through the physical path.");
        if (std::string(example.axis) == "z" && example.x == 8 && example.start_y == 4) {
            auto clear_below = low_flat_site();
            clear_below.at("obstacles") = V(A{V(A{V(A{V(mx - 0.1 * u_scale), V(1.8 * u_scale), V(-0.1 * u_scale)}),
                                                    V(A{V(mx + 0.1 * u_scale), V(1.9 * u_scale), V(0.1 * u_scale)})})});
            Host below;
            check(accepted(below.initialize("fresh", {"P"})) && accepted(below.configure_terrain(clear_below)) &&
                      accepted(below.validate_checkpoint(checkpoint)), "Clearance does not fill the empty space below an incline.");
        }
    }
}

void raised_collector_route_refusal() {
    Host host;
    const auto site = ground_channel_site();
    check(accepted(host.initialize("cog-api", {"P"})) &&
          accepted(host.configure_terrain(site)),
          "The half-U raised-route refusal binds a finite flowing channel.");
    observe(host, -3.3, 3.3, 1);
    create(host, ground_channel_wheel("route-wheel"));
    observe(host, 2.0, 0.0, 2);
    auto base = wire("place_foundation", "raised-collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{0})}));
    base.emplace("level", V(I{4}));
    create(host, base);
    auto collector = machine("collector", 0, "route-collector", "z");
    collector.emplace("level", V(I{4}));
    const auto before = host.projection();
    const auto refused = host.command("P", collector);
    const auto after_refusal = host.projection();
    const bool stock_same = !factory::values::typed_difference(V(field<O>(before, "stock")),
        V(field<O>(after_refusal, "stock")));
    const bool parts_same = !factory::values::typed_difference(V(field<O>(before, "parts")),
        V(field<O>(after_refusal, "parts")));
    const bool entities_same = !factory::values::typed_difference(V(field<O>(before, "entities")),
        V(field<O>(after_refusal, "entities")));
    check(!accepted(refused) && field<std::string>(refused, "reason") == "occupied" &&
          stock_same && parts_same && entities_same,
          "The 3U support slab refuses the old raised collector without spending source or kit: " +
              field<std::string>(refused, "reason") + ", stock=" + std::to_string(stock_same) +
              ", parts=" + std::to_string(parts_same) + ", entities=" + std::to_string(entities_same));
    const auto duplicate = host.command("P", collector);
    check(!accepted(duplicate) && field<bool>(duplicate, "duplicate") &&
          field<std::string>(duplicate, "reason") == "occupied",
          "The blocked raised route replays the same refusal.");
    const auto saved = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize("fresh", {"P"})) &&
          accepted(restored.configure_terrain(site)) &&
          accepted(restored.restore_checkpoint(saved)) &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "The finite source and raised collector refusal restore without a phantom machine.");

}

void rotated_span_build_orders() {
    const std::array<std::array<int, 3>, 6> orders{{
        {{0, 1, 2}}, {{0, 2, 1}}, {{1, 0, 2}},
        {{1, 2, 0}}, {{2, 0, 1}}, {{2, 1, 0}}
    }};
    for (const auto& order : orders) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
              "The rotated route binds a synthetic flat site.");
        I epoch = 0;
        const auto at = [&](double z) { observe(host, -1.65, z, ++epoch); };
        for (const I z : {I{0}, I{2}}) {
            at(static_cast<double>(z) * factory::godot_world::site_geometry::pitch * 3);
            const auto id = "rotated-base-" + std::to_string(z);
            auto base = wire("place_foundation", id.c_str());
            base.emplace("cell", V(A{V(I{0}), V(z)})); base.emplace("level", V(I{4}));
            create(host, base);
        }
        at(factory::godot_world::site_geometry::pitch);
        const auto first = create(host, shaft(0, 4, 4, "rotated-first", "x"));
        at(2 * factory::godot_world::site_geometry::pitch);
        const auto last = create(host, shaft(0, 4, 8, "rotated-last", "x"));
        std::array<std::string, 3> ids;
        for (int index : order) {
            at(factory::godot_world::site_geometry::pitch *
                (index == 0 ? 0 : index == 1 ? 1.5 : 5));
            const auto request = "rotated-" + std::to_string(index);
            auto command = index == 1 ? wire("place_belt_span", request.c_str()) :
                machine(index == 0 ? "collector" : "processor", 0, request.c_str(), "x");
            if (index == 1) {
                command.emplace("from", V(first)); command.emplace("to", V(last));
            } else {
                command.at("cell") = V(A{V(I{0}), V(I{index == 0 ? 0 : 5})});
                command.emplace("level", V(I{4}));
                command.emplace("rotation", V(I{1}));
            }
            if (index == 0) {
                const auto before = host.projection();
                const auto refused = host.command("P", command);
                check(!accepted(refused) && field<std::string>(refused, "reason") == "occupied" &&
                      !factory::values::typed_difference(V(field<O>(before, "stock")),
                          V(field<O>(host.projection(), "stock"))) &&
                      !factory::values::typed_difference(V(field<O>(before, "parts")),
                          V(field<O>(host.projection(), "parts"))) &&
                      !factory::values::typed_difference(V(field<O>(before, "entities")),
                          V(field<O>(host.projection(), "entities"))),
                      "A rotated full-size collector cannot enter its 3U slab in any construction order.");
                continue;
            }
            ids[index] = create(host, command);
        }
        const auto projection = host.projection();
        const auto span = field<O>(projection, "belt_spans").at(ids[1]);
        check(field<A>(projection, "links").empty() && field<std::string>(span, "from") == first &&
                  field<std::string>(span, "to") == last &&
                  field<I>(field<O>(projection, "transmission_parts").at(first), "axis") == 0 &&
                  field<I>(V(field<O>(projection, "parts")), "belt") == 1,
              "Each order constructs the Z span on X-axis shafts and consumes one finite belt without machine links.");
        const auto saved = host.checkpoint();
        Host restored;
        check(accepted(restored.initialize("fresh", {"P"})) &&
                  accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) &&
                  accepted(restored.restore_checkpoint(saved)) &&
                  !factory::values::typed_difference(saved, restored.checkpoint()),
              "The rotated span, machines and their historical requests restore exactly.");
    }
}

void equivalent_gear_exclusion() {
    for (const auto* axis : std::array<const char*, 4>{"x", "y", "z", nullptr}) {
        const auto* effective_axis = axis ? axis : "x";
        const bool axial_x = std::string(effective_axis) == "x";
        const A blocked{V(axial_x ? 0.0 : 1.1 * u_scale), V(0.9 * u_scale),
                        V((axial_x ? 2.75 : 1.65) * u_scale)};
        Host legacy, modern;
        check(accepted(legacy.initialize("cog-api", {"P"})) && accepted(modern.initialize("cog-api", {"P"})) &&
                  accepted(legacy.configure_terrain(low_flat_site())) && accepted(modern.configure_terrain(low_flat_site())),
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

        const A clear{V(1.4), V(0.9 * u_scale), V(3.3)};
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
              field<I>(V(field<O>(legacy.projection(), "parts")), "gear") == 9,
              "Equivalent accepted aliases produce identical typed topology and retain nine carried gears.");
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
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The global-grid fixture initializes.");
    constexpr double step = factory::godot_world::site_geometry::height_step;
    check(accepted(host.publish_actor("P", {V(40 * step), V(16 * step), V(8 * step + 2.7)}, 1)),
          "A disclosed synthetic actor is near the new absolute grid point.");
    const auto placed = host.command("P", gear(40, 16, 8, "global-grid"));
    check(accepted(placed), "Cogwheels are no longer clipped to the old construction rectangle or height range.");
    check(accepted(host.validate_checkpoint(host.checkpoint())), "Global gear coordinates retain typed save and history validity.");
}

void individual_shafts() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::channel_site())),
          "The shaft fixture binds a synthetic flowing channel.");
    observe(host, -1.65, 3.3, 1);
    create(host, channel_wheel("shaft-wheel"));
    observe(host, -3.3, 1.65, 2);
    const auto first_wire = shaft(-12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 4, "first-segment");
    const auto first = create(host, first_wire);
    const auto before_parts = field<O>(host.projection(), "transmission_parts");
    const auto duplicate = shaft(-12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 4, "overlap-identical");
    check(field<std::string>(host.command("P", duplicate), "reason") == "occupied" &&
              field<std::string>(host.command("P", shaft(-12 * grid_scale, 4 * grid_scale,
                  4 * grid_scale + 5, "off-grid")), "reason") == "invalid_cell" &&
              !factory::values::typed_difference(V(field<O>(host.projection(), "transmission_parts")), V(before_parts)) &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 7,
          "Occupied and off-grid shaft placements are refused without consuming parts.");
    check(field<bool>(host.command("P", duplicate), "duplicate"),
          "An overlapping placement refusal is stable on replay.");
    observe(host, -1.65, 3.3, 3);
    const auto second = create(host, shaft(-12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 8, "second-segment"));
    check(field<I>(motion(host, second), "numerator") == 25 &&
              field<I>(motion(host, second), "denominator") == 84,
          "Two individually placed, touching shaft segments carry the wheel rotation.");
    check(field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 6,
          "Both segment placements consume their own finite parts.");
    check(accepted(host.command("P", target("remove", first, "remove-first-segment"))) &&
              field<I>(motion(host, second), "numerator") == 0 &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 7,
          "Removing the first segment disconnects the second and refunds one part.");
    const auto replacement = create(host, shaft(-12 * grid_scale, 4 * grid_scale,
        4 * grid_scale + 4, "replacement-segment"));
    check(field<I>(motion(host, replacement), "numerator") == 25 &&
              field<I>(motion(host, second), "numerator") == 25,
          "A replacement one-tile segment reconnects the source to the remaining segment.");
    observe(host, 0, 8 * factory::godot_world::site_geometry::height_step, 4);
    check(field<std::string>(host.command("P", shaft(0, 0, 8, "actor-overlap-shaft", "x")), "reason") == "actor_occupied",
          "A shaft cannot be placed through the observed actor.");
    check(field<std::string>(host.command("P", shaft(0, 0, 0, "bad-axis", "bad")), "reason") == "invalid_axis" &&
              field<std::string>(host.command("P", shaft(0, 0, 0, "bad-span", "x", 3)), "reason") == "invalid_shaft",
          "Invalid axis and unsupported shaft length are rejected.");
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "Individual shaft histories validate in the typed checkpoint.");
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "A fresh Host restores individual segment geometry, custody and request history exactly.");
    check(field<bool>(fresh.command("P", first_wire), "duplicate"), "A removed shaft request remains an exact historical replay.");
}

void raised_forward_collector_refusal() {
    Host host;
    const auto site = ground_channel_site();
    check(accepted(host.initialize("cog-api", {"P"})) &&
          accepted(host.configure_terrain(site)),
          "The half-U forward-route refusal binds a finite flowing channel.");
    observe(host, -3.3, 3.3, 1);
    const auto wheel = create(host, ground_channel_wheel("forward-wheel", "x"));
    const auto wheel_rate = field<I>(motion(host, wheel), "numerator");
    check(wheel_rate != 0,
          "The X-axis full-size wheel keeps a signed native flow rate before machine placement.");
    observe(host, 2.0, 0.0, 2);
    auto base = wire("place_foundation", "forward-collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{0})})); base.emplace("level", V(I{4}));
    create(host, base);
    auto collector = machine("collector", 0, "forward-collector", "z");
    collector.emplace("level", V(I{4}));
    const auto before = host.projection();
    const auto refused = host.command("P", collector);
    check(!accepted(refused) && field<std::string>(refused, "reason") == "occupied" &&
          !factory::values::typed_difference(V(field<O>(before, "stock")),
              V(field<O>(host.projection(), "stock"))) &&
          !factory::values::typed_difference(V(field<O>(before, "parts")),
              V(field<O>(host.projection(), "parts"))) &&
          field<I>(motion(host, wheel), "numerator") == wheel_rate,
          "The old raised forward collector intersects the 3U slab without spending material or changing wheel flow.");
    for (int tick = 0; tick < 32; ++tick) (void)host.advance();
    const auto after = host.projection();
    check(field<I>(V(field<O>(after, "stock")), "source") == 4096 &&
          field<I>(V(field<O>(after, "stock")), "collector") == 0 &&
          field<A>(after, "dropped_material").empty(),
          "A refused collector cannot extract source stock or invent dropped cargo during continued wheel motion.");

}

void cog_at_belt_face() {
    for (const I direction : {I{-1}, I{1}}) {
        for (const bool cog_first : {false, true}) {
            Host host;
            check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(low_flat_site())), "The face contact Host starts.");
            observe(host, 0, -1.65, 1);
            const auto first = create(host, shaft(0, 0, 0, "face-first"));
            observe(host, direction * 3.3, -1.65, 2);
            const auto last = create(host, shaft(direction * 8, 0, 0, "face-last"));
            auto belt = wire("place_belt_span", "face-belt");
            belt.emplace("from", V(first)); belt.emplace("to", V(last));
            auto cog = gear(direction * 12, 0, 0, "face-cog", "x");
            observe(host, direction * 2.5, -1.65, 3);
            if (cog_first) { create(host, cog); create(host, belt); }
            else { create(host, belt); create(host, cog); }
            const auto overlap = host.command("P", gear(direction * 4, 0, 0, "overlap-cog", "x"));
            check(!accepted(overlap) && field<std::string>(overlap, "reason") == "occupied", "A cog with real overlap still cannot occupy the belt.");
            const auto checkpoint = host.checkpoint();
            check(accepted(host.validate_checkpoint(checkpoint)), "Tile-face contact remains valid on restore.");
        }
    }
}

void cog_axle_actor_clearance() {
    const std::array<std::string, 3> axes{"x", "y", "z"};
    constexpr double scale = factory::godot_world::site_geometry::pitch / 1.65;
    for (std::size_t axis = 0; axis < axes.size(); ++axis) {
        for (const bool alias : {false, true}) {
            Host host;
            check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
                      accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The cog axle clearance Host starts.");
            check(accepted(host.publish_actor("P", {V(0.0), V(3.8 * scale), V(-2.0 * scale)}, 1)), "The builder is within reach and clear.");
            std::array<double, 3> blocker{0.0, 3.8 * scale, 0.0};
            blocker[axis] += (axis == 1 ? 1.55 : 0.7) * scale;
            check(accepted(host.publish_actor("Q", {V(blocker[0]), V(blocker[1]), V(blocker[2])}, 1)), "A second synthetic actor occupies only the axle envelope.");
            auto request = alias ? machine("gear", 0, "blocked-axle", axes[axis].c_str()) :
                gear(0, 8, 0, "blocked-axle", axes[axis].c_str());
            if (alias) {
                request.at("cell") = V(A{V(I{0}), V(I{0})});
                request.emplace("level", V(I{8}));
            }
            const auto refused = host.command("P", request);
            check(!accepted(refused) && field<std::string>(refused, "reason") == "actor_occupied",
                  "Either cog placement form refuses an actor at the exposed axle.");
            check(accepted(host.publish_actor("Q", {V(8.0), V(3.8), V(8.0)}, 2)), "The second actor moves clear.");
            request.at("request") = V("clear-axle");
            check(accepted(host.command("P", request)), "The cog can be placed after the axle is clear.");
            const auto checkpoint = host.checkpoint();
            check(accepted(host.validate_checkpoint(checkpoint)), "The placed cog retains a valid checkpoint.");
        }
    }
}

void transmission_site_clearance() {
    const std::array<const char*, 3> axes{"x", "y", "z"};
    for (std::size_t axis = 0; axis < axes.size(); ++axis) for (const int part_case : {0, 1, 2}) {
        const bool shaft_part = part_case == 0;
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The clearance fixture binds a flat site.");
        observe(host, 2.0, -1.65, 1);
        const auto clear = host.command("P", shaft_part ? shaft(0, 4, 0, "clear-shaft", axes[axis]) :
            gear(0, 4, 0, "clear-cog", axes[axis]));
        check(accepted(clear), "An elevated transmission part with clear terrain is accepted.");
        std::array<double, 3> obstacle{0.0,
            4 * factory::godot_world::site_geometry::height_step + factory::godot_world::site_geometry::anchor_height,
            0.0};
        obstacle[part_case == 2 ? (axis + 1) % 3 : axis] += 0.5 / grid_scale;
        auto obstructed_site = factory::godot_world::tests::flat_site();
        obstructed_site.at("obstacles") = V(A{V(A{
            V(A{V(obstacle[0] - 0.04), V(obstacle[1] - 0.04), V(obstacle[2] - 0.04)}),
            V(A{V(obstacle[0] + 0.04), V(obstacle[1] + 0.04), V(obstacle[2] + 0.04)})})});
        Host obstructed;
        check(accepted(obstructed.initialize("cog-api", {"P"})) && accepted(obstructed.configure_terrain(obstructed_site)),
              "The restore fixture binds a site obstacle.");
        const auto restored = obstructed.validate_checkpoint(host.checkpoint());
        check(!accepted(restored) && field<std::string>(restored, "reason") == "site_occupied",
              "Checkpoint validation refuses a site obstacle through the physical part.");
        observe(obstructed, 2.0, -1.65, 1);
        const auto blocked = obstructed.command("P", shaft_part ? shaft(0, 4, 0, "blocked-shaft", axes[axis]) :
            gear(0, 4, 0, "blocked-cog", axes[axis]));
        check(!accepted(blocked) && field<std::string>(blocked, "reason") == "site_occupied",
              "Construction refuses the same site obstacle as checkpoint validation; reason=" + field<std::string>(blocked, "reason") + ".");
        if (!shaft_part) {
            auto alias = machine("gear", 0, "blocked-cog-alias", axes[axis]);
            alias.at("cell") = V(A{V(I{0}), V(I{0})});
            alias.emplace("level", V(I{4}));
            const auto refused = obstructed.command("P", alias);
            check(!accepted(refused) && field<std::string>(refused, "reason") == "site_occupied",
                  "The equivalent cog placement form refuses the same obstacle.");
        }
    }
}

void transmission_terrain_clearance() {
    const std::array<const char*, 3> axes{"x", "y", "z"};
    for (std::size_t axis = 0; axis < axes.size(); ++axis) for (const bool is_gear : {false, true}) {
        const double half_height = (is_gear || axis == 1) ?
            factory::godot_world::site_geometry::pitch / 2 :
            0.1 * factory::godot_world::site_geometry::pitch / 1.65;
        const auto site_at = [](double height) {
            auto site = factory::godot_world::tests::flat_site();
            site.at("heights") = V(A{V(height), V(height), V(height), V(height)});
            return site;
        };
        const auto command = [&] (const char* id) {
            return is_gear ? gear(0, 0, 0, id, axes[axis]) : shaft(0, 0, 0, id, axes[axis]);
        };
        Host clear;
        check(accepted(clear.initialize("cog-api", {"P"})) &&
              accepted(clear.configure_terrain(site_at(factory::godot_world::site_geometry::anchor_height - half_height))), "The contact site binds.");
        observe(clear, 0, -1.65, 1);
        const auto contact = clear.command("P", command("contact"));
        const bool stand_fits = is_gear || axis == 1;
        check(accepted(contact) == stand_fits,
              "Terrain contact is admitted only when the complete fixed bearing can also fit.");
        if (!stand_fits)
            check(field<std::string>(contact, "reason") == "support_required",
                  "A horizontal axle touching the ground has no room for its fixed bearing bridge.");
        const auto saved = clear.checkpoint();
        Host buried;
        check(accepted(buried.initialize("cog-api", {"P"})) &&
              accepted(buried.configure_terrain(site_at(factory::godot_world::site_geometry::anchor_height - half_height + 0.01))), "The penetrating site binds.");
        observe(buried, 0, -1.65, 1);
        const auto before = world_state(buried);
        const auto refusal = buried.command("P", command("buried"));
        check(!accepted(refusal) && field<std::string>(refusal, "reason") == "site_occupied",
              "A part penetrating terrain is refused for every axle orientation.");
        if (is_gear) {
            auto alias = machine("gear", 0, "buried-alias", axes[axis]);
            alias.at("cell") = V(A{V(I{0}), V(I{0})});
            const auto alias_refusal = buried.command("P", alias);
            check(!accepted(alias_refusal) && field<std::string>(alias_refusal, "reason") == "site_occupied",
                  "The equivalent cog placement form also refuses terrain penetration.");
        }
        check(!factory::values::typed_difference(before, world_state(buried)),
              "Terrain refusal leaves parts and material custody unchanged.");
        const auto restore = buried.validate_checkpoint(saved);
        if (stand_fits)
            check(!accepted(restore) && field<std::string>(restore, "reason") == "site_occupied",
                  "Checkpoint validation applies the same terrain clearance.");
        else
            check(accepted(restore), "A refused low shaft leaves an empty, valid checkpoint.");
        Host unavailable;
        check(accepted(unavailable.initialize("cog-api", {"P"})), "The unbound site initializes.");
        observe(unavailable, 0, -1.65, 1);
        const auto missing = unavailable.command("P", command("no-terrain"));
        check(!accepted(missing) && field<std::string>(missing, "reason") == "terrain_unavailable",
              "Construction cannot assume clearance without a bound terrain.");
    }
}

void transmission_foundation_clearance() {
    const std::array<const char*, 3> axes{"x", "y", "z"};
    constexpr I collision_level = 8;
    for (std::size_t axis = 0; axis < axes.size(); ++axis) for (const bool is_gear : {false, true}) {
        const auto base = [collision_level] (const char* id) {
            auto command = wire("place_foundation", id);
            command.emplace("cell", V(A{V(I{0}), V(I{0})})); command.emplace("level", V(collision_level));
            return command;
        };
        const auto part = [&] (const char* id) {
            return is_gear ? gear(0, 4, 0, id, axes[axis]) : shaft(0, 4, 0, id, axes[axis]);
        };
        const bool penetrates = true; // The raised foundation cuts through the part's center.
        for (const bool foundation_first : {false, true}) {
            Host host;
            check(accepted(host.initialize("cog-api", {"P"})) &&
                      accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The foundation fixture binds its site.");
            observe(host, 2.5, 0, 1);
            create(host, foundation_first ? base("first-base") : part("first-part"));
            const auto before = world_state(host);
            const auto second = host.command("P", foundation_first ? part("second-part") : base("second-base"));
            check(accepted(second) != penetrates && (!penetrates || field<std::string>(second, "reason") == "occupied"),
                  std::string("Foundation and transmission collision must be symmetric: axis=") + axes[axis] +
                  ", gear=" + (is_gear ? "true" : "false") + ", foundation_first=" + (foundation_first ? "true" : "false") +
                  ", reason=" + field<std::string>(second, "reason") + ".");
            if (is_gear && foundation_first) {
                auto alias = machine("gear", 0, "alias-part", axes[axis]);
                alias.at("cell") = V(A{V(I{0}), V(I{0})}); alias.emplace("level", V(I{4}));
                const auto refused = host.command("P", alias);
                check(!accepted(refused) && field<std::string>(refused, "reason") == "occupied",
                      "The alternate cog construction form also rejects a foundation collision.");
            }
            if (penetrates) check(!factory::values::typed_difference(before, world_state(host)),
                                  "A foundation collision refusal preserves the whole World state.");
            check(accepted(host.validate_checkpoint(host.checkpoint())), "The retained non-overlapping state validates.");
        }
        if (penetrates) {
            Host host;
            check(accepted(host.initialize("cog-api", {"P"})) &&
                      accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The restore fixture binds its site.");
            observe(host, 2.5, 0, 1);
            auto low = base("low-base"); low.at("level") = V(I{0});
            const auto base_id = create(host, low);
            create(host, part("raised-part"));
            const auto saved = host.checkpoint();
            auto envelope = std::get<O>(saved.storage());
            auto world = std::get<O>(envelope.at("world").storage());
            auto state = std::get<O>(world.at("state").storage());
            auto foundations = std::get<O>(state.at("foundations").storage());
            auto moved = std::get<O>(foundations.at(base_id).storage());
            moved.at("center") = V(A{V(I{0}), V(collision_level), V(I{0})});
            foundations.at(base_id) = V(std::move(moved)); state.at("foundations") = V(std::move(foundations));
            world.at("state") = V(std::move(state)); envelope.at("world") = V(std::move(world));
            const auto refused = host.validate_checkpoint(V(envelope));
            check(!accepted(refused) && field<std::string>(refused, "reason") == "occupied" &&
                      !factory::values::typed_difference(saved, host.checkpoint()),
                  "Restore validation rejects a foundation moved through a transmission shape without changing the live World.");
        }
    }
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The area fixture binds its site.");
    observe(host, 0, -2.5, 1);
    create(host, gear(0, 4, 0, "area-cog", "z"));
    const auto before = world_state(host);
    auto area = wire("place_foundations", "blocked-area");
    area.emplace("cell", V(A{V(I{-1}), V(I{0})})); area.emplace("end_cell", V(A{V(I{1}), V(I{0})}));
    area.emplace("level", V(collision_level));
    const auto rejected = host.command("P", area);
    check(!accepted(rejected) && field<std::string>(rejected, "reason") == "occupied" &&
              !factory::values::typed_difference(before, world_state(host)),
          "An obstructed foundation area refuses atomically without consuming any blocks.");
    auto touching = wire("place_foundation", "touching-base");
    touching.emplace("cell", V(A{V(I{1}), V(I{0})})); touching.emplace("level", V(collision_level));
    check(accepted(host.command("P", touching)) && accepted(host.validate_checkpoint(host.checkpoint())),
          "A foundation may touch a cog at an adjacent tile face without overlapping it.");
}

void one_tile_placement() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The one-tile host starts on a known site.");
    observe(host, 0, 0, 1);
    for (const auto& position : std::array<std::array<I, 3>, 3>{{{5, 4, 4}, {4, 5, 4}, {4, 4, 5}}}) {
        auto off = gear(position[0], position[1], position[2],
                        ("off-" + std::to_string(checks)).c_str(), "x");
        const auto refused = host.command("P", off);
        check(!accepted(refused) && field<std::string>(refused, "reason") == "invalid_cell",
              "Cog coordinates off the shared tile grid are refused.");
    }
    check(!accepted(host.command("P", shaft(4, 4, 4, "long", "x", 4))),
          "An oversized shaft cannot be placed.");
    const auto one = host.command("P", shaft(4, 4, 4, "one", "x"));
    check(accepted(one), "An aligned single-tile shaft can be placed.");
    check(!accepted(host.command("P", gear(4, 4, 4, "occupied", "x"))),
          "A cog cannot occupy the shaft's tile.");
    check(accepted(host.command("P", gear(8, 4, 4, "next", "x"))),
          "A cog can occupy the adjacent tile.");
    const auto checkpoint = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize("fresh", {"P"})) &&
              accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) && accepted(restored.restore_checkpoint(checkpoint)) &&
              !factory::values::typed_difference(checkpoint, restored.checkpoint()),
          "The tile-aligned parts and custody restore exactly.");
}

void restored_transmission_geometry() {
    for (const bool cog : {false, true}) for (int defect = 0; defect < (cog ? 3 : 4); ++defect) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
              "The restore-grid fixture binds its site.");
        observe(host, 2.5, 0, 1);
        create(host, cog ? gear(0, 4, 0, "part", "z") : shaft(0, 4, 0, "part", "z"));
        const auto saved = host.checkpoint();
        auto envelope = std::get<O>(saved.storage());
        auto world = std::get<O>(envelope.at("world").storage());
        auto state = std::get<O>(world.at("state").storage());
        auto topology = std::get<O>(state.at("topology").storage());
        auto parts = std::get<A>(topology.at("parts").storage());
        auto part = std::get<O>(parts.front().storage());
        if (defect == 3) part.at("half_span") = V(I{4});
        else {
            auto center = std::get<A>(part.at("center").storage());
            center[defect] = V(std::get<I>(center[defect].storage()) + 1);
            part.at("center") = V(std::move(center));
        }
        parts.front() = V(std::move(part)); topology.at("parts") = V(std::move(parts));
        state.at("topology") = V(std::move(topology)); world.at("state") = V(std::move(state));
        envelope.at("world") = V(std::move(world));
        const V altered(std::move(envelope));
        const auto validation = host.validate_checkpoint(altered);
        check(!accepted(validation) && field<std::string>(validation, "reason") == "native_checkpoint_refused" &&
                  !factory::values::typed_difference(saved, host.checkpoint()),
              "Off-grid or oversized transmission fails native validation without changing the live world.");
        Host fresh;
        check(accepted(fresh.initialize("fresh", {"P"})) &&
                  accepted(fresh.configure_terrain(factory::godot_world::tests::flat_site())),
              "The malformed restore target is a fresh Host on the same site.");
        const auto initial = fresh.checkpoint();
        const auto rejection = fresh.restore_checkpoint(altered);
        check(!accepted(rejection) && field<std::string>(rejection, "reason") == "native_checkpoint_refused" &&
                  !factory::values::typed_difference(initial, fresh.checkpoint()),
              "Malformed transmission restore reaches native decoding and preserves the fresh Host.");
        check(accepted(fresh.restore_checkpoint(saved)) &&
                  !factory::values::typed_difference(saved, fresh.checkpoint()),
              "The original aligned one-tile checkpoint restores exactly after a malformed refusal.");
    }
}

void transmission_tile_center() {
    for (const bool cog : {false, true}) for (const auto* axis : {"x", "y", "z"}) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The tile-center fixture binds its site.");
        observe(host, 2.5, 0, 1);
        auto base = wire("place_foundation", "tile-base");
        base.emplace("cell", V(A{V(I{0}), V(I{0})})); base.emplace("level", V(I{4}));
        create(host, base);
        const auto placed = host.command("P", cog ? gear(0, 4, 0, "tile-cog", axis) : shaft(0, 4, 0, "tile-shaft", axis));
        check(accepted(placed), "A full-tile transmission part fits immediately above its supporting foundation; reason=" +
              field<std::string>(placed, "reason") + ".");
        check(accepted(host.validate_checkpoint(host.checkpoint())), "The supported transmission part survives checkpoint validation.");
    }
}

void transmission_above_supporting_foundation() {
    for (const auto* axis : {"x", "y", "z"}) for (const I teeth : {I{0}, I{2}, I{4}}) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
              "The supporting foundation fixture binds its site.");
        observe(host, 2.5, 0, 1);
        auto base = wire("place_foundation", "half-base");
        base.emplace("cell", V(A{V(I{0}), V(I{0})})); base.emplace("level", V(I{4}));
        create(host, base);
        const auto before = world_state(host);
        const auto intersecting = teeth == 0 ? shaft(0, 0, 0, "below", axis) : gear(0, 0, 0, "below", axis, teeth);
        const auto refused = host.command("P", intersecting);
        check(!accepted(refused) && field<std::string>(refused, "reason") == "occupied" &&
                  !factory::values::typed_difference(before, world_state(host)),
              "The lower global tile intersects the slab and is refused without consuming a part.");
        const auto before_kit = field<I>(V(field<O>(host.projection(), "part_kits").at("P")), teeth == 0 ? "shaft" : "gear");
        const auto command = teeth == 0 ? shaft(0, 4, 0, "above", axis) : gear(0, 4, 0, "above", axis, teeth);
        create(host, command);
        const auto after_kit = field<I>(V(field<O>(host.projection(), "part_kits").at("P")), teeth == 0 ? "shaft" : "gear");
        check(after_kit == before_kit - 1,
              "The snapped global tile consumes exactly one matching transmission part.");
        const auto saved = host.checkpoint();
        Host restored;
        check(accepted(restored.initialize("fresh", {"P"})) &&
                  accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) &&
                  accepted(restored.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, restored.checkpoint()),
              "The supporting slab and aligned transmission part restore exactly.");
    }
}

void half_tile_shaft_bridge() {
    for (const auto* axis : {"x", "z"}) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
              "The half-tile bridge uses the ordinary native Host and a known site.");
        observe(host, 2.5, 2.5, 1);
        const auto before = field<I>(V(field<O>(host.projection(), "part_kits").at("P")), "shaft");
        const auto bridge = std::string(axis) == "x" ?
            shaft(4, 4, 0, "half-tile-bridge", axis) :
            shaft(0, 4, 4, "half-tile-bridge", axis);
        const auto placed = host.command("P", bridge);
        check(accepted(placed), "A half-span-two shaft fits an admitted axle port along its axis; reason=" +
              field<std::string>(placed, "reason") + ".");
        const auto off_axis = std::string(axis) == "x" ?
            shaft(2, 4, 0, "off-axis-bridge", axis) :
            shaft(0, 4, 2, "off-axis-bridge", axis);
        const auto refused = host.command("P", off_axis);
        check(!accepted(refused) && field<std::string>(refused, "reason") == "invalid_cell" &&
              field<I>(V(field<O>(host.projection(), "part_kits").at("P")), "shaft") == before - 1,
              "An off-axis half-tile center refuses without spending a second shaft.");
        const auto saved = host.checkpoint();
        Host restored;
        check(accepted(restored.initialize("fresh", {"P"})) &&
              accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) &&
              accepted(restored.restore_checkpoint(saved)) &&
              !factory::values::typed_difference(saved, restored.checkpoint()),
              "The valid bridge and refused off-axis intent survive a fresh Host restore.");
    }
}

void building_rotation() {
    for (I turn = 0; turn < 4; ++turn) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
              "The rotation fixture uses one native Host and two actor identities.");
        check(accepted(host.publish_actor("P", {V(0.0), V(1.0), V(0.0)}, 1)),
              "The disclosed synthetic actor is within ordinary construction reach.");
        const auto before = field<O>(host.projection(), "part_kits");
        int bad_index = 0;
        for (const V& invalid : {V(I{-1}), V(I{4}), V(1.0), V("1"), V(true)}) {
            auto bad = machine("processor", 1, "invalid", "z");
            bad.at("cell") = V(A{V(I{1}), V(I{0})});
            bad.at("request") = V("bad-rotation-" + std::to_string(bad_index++));
            bad.emplace("rotation", invalid);
            const auto refused = host.command("P", bad);
            check(!accepted(refused) && field<std::string>(refused, "reason") == "invalid_rotation" &&
                  !factory::values::typed_difference(V(field<O>(host.projection(), "part_kits")), V(before)),
                  "Malformed or out-of-range rotation refuses without consuming any parts.");
        }
        auto build = machine("processor", 1, "rotated-building", turn % 2 == 0 ? "z" : "x");
        build.at("cell") = V(A{V(I{1}), V(I{0})});
        build.emplace("rotation", V(turn));
        const auto placed = host.command("P", build);
        check(accepted(placed), "The selected quarter turn is admitted by the native authority.");
        const auto id = field<std::string>(placed, "entity");
        const auto projection = host.projection();
        const auto& projected = field<O>(projection, "entities").at(id);
        check(field<I>(projected, "rotation") == turn &&
              field<I>(projected, "axis") == (turn % 2 == 0 ? 2 : 0),
              "The shared projection retains the exact facing and horizontal drive axis.");
        auto overlap = build;
        overlap.at("request") = V("overlapping-turn");
        overlap.at("rotation") = V((turn + 1) % 4);
        const auto remaining = field<O>(host.projection(), "part_kits");
        check(!accepted(host.command("P", overlap)) &&
              !factory::values::typed_difference(V(field<O>(host.projection(), "part_kits")), V(remaining)),
              "Rotating an occupied square cannot spend another carried part.");
        const auto saved = host.checkpoint();
        Host restored;
        check(accepted(restored.initialize("fresh", {"P", "Q"})) &&
              accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())),
              "A fresh Host binds the same site before restoring a turned building.");
        const auto restored_result = restored.restore_checkpoint(saved);
        check(accepted(restored_result), "A fresh native Host restores the turned building and both actor records: " +
              field<std::string>(restored_result, "reason"));
        check(!factory::values::typed_difference(saved, restored.checkpoint()) &&
              field<I>(field<O>(restored.projection(), "entities").at(id), "rotation") == turn,
              "Save and restore preserve the exact facing, custody and command history.");
    }
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--powered-relay-only") {
            powered_relay_route();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_river_relay\",\"checks\":" << checks << "}\n";
            return 0;
        }
        if (argc == 2 && std::string(argv[1]) == "--individual-shafts-only") {
            individual_shafts();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_river_shaft\",\"checks\":" << checks << "}\n";
            return 0;
        }
        if (argc == 2 && std::string(argv[1]) == "--stacked-relays-only") {
            stacked_vertical_relay_support();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_stacked_relays\",\"checks\":" << checks << "}\n";
            return 0;
        }
        if (argc == 2 && std::string(argv[1]) == "--building-rotation-only") {
            building_rotation();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_building_rotation\",\"checks\":" << checks << "}\n";
            return 0;
        }
        if (argc == 2 && std::string(argv[1]) == "--tile-center-only") { transmission_tile_center(); transmission_above_supporting_foundation(); half_tile_shaft_bridge(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--foundation-only") { transmission_foundation_clearance(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--terrain-only") { transmission_terrain_clearance(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--raised-route-only") { raised_collector_route_refusal(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--transmission-site-only") {
            transmission_site_clearance();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_transmission_site\",\"checks\":" << checks << "}" << std::endl;
            return 0;
        }
        if (argc == 2 && std::string(argv[1]) == "--one-tile-only") {
            one_tile_placement();
            restored_transmission_geometry();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_one_tile_host\",\"checks\":" << checks << "}" << std::endl;
            return 0;
        }
        if (argc == 1) {
            transmission_request_shapes();
            building_rotation();
            finite_oriented_train_and_restore(); adjacent_axle_faces(); refusals_and_legacy_shape(); cog_axle_actor_clearance(); cog_at_belt_face(); transmission_site_clearance(); transmission_terrain_clearance(); transmission_foundation_clearance(); one_tile_placement(); restored_transmission_geometry();
            transmission_tile_center(); transmission_above_supporting_foundation(); half_tile_shaft_bridge(); global_grid(); finite_large_cog(); finite_relays_and_restore(); stacked_vertical_relay_support(); relay_shell_terrain(); powered_relay_route(); ground_collector_output_gap(); retired_belt_machine(); typed_loose_host(); select_belt_shaft_host(); long_selected_belt_host(); belt_span_host_commands(); nonhorizontal_span_host(); raised_collector_route_refusal(); rotated_span_build_orders(); individual_shafts(); raised_forward_collector_refusal();
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
