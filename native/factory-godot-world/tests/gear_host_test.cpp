#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <algorithm>
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
    if (std::string(kind) == "wheel") command.emplace("level", V(I{4}));
    if (axis) command.emplace("axis", V(axis));
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

O low_flat_site() {
    auto site = factory::godot_world::tests::flat_site();
    site.at("heights") = V(A{V(-1.0), V(-1.0), V(-1.0), V(-1.0)});
    return site;
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
        saw_gear |= field<I>(entry, "teeth") == 2 && field<I>(entry, "count") == 8;
        saw_large |= field<I>(entry, "teeth") == 4 && field<I>(entry, "count") == 2;
    }
    check(saw_gear, "The UI sees the actual carried gear specification, not only an aggregate count.");
    check(saw_large, "The native starter kit exposes two finite large cogs to the UI.");
    for (const auto& entry : std::get<A>(specs.at("Q").storage()))
        check(field<I>(entry, "count") == 0, "An empty actor kit cannot borrow the other actor's parts.");
    auto base = wire("place_foundation", "collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{1})})); base.emplace("level", V(I{4}));
    check(accepted(host.command("P", base)), "The synthetic stream bank supports a collector foundation.");
    const auto wheel = create(host, machine("wheel", -2, "wheel", "z"));
    auto collector_wire = machine("collector", 0, "collector", "z");
    collector_wire.emplace("level", V(I{4}));
    const auto collector = create(host, collector_wire);
    observe(host, 0, 0, 2);
    observe(host, -3.3, 0, 3);
    create(host, gear(-8, 4, 8, "upper", "z"));
    observe(host, 0, 0, 4);
    const auto a = create(host, gear(-4, 4, 8, "gear-A", "z"));
    const auto original_b = gear(0, 4, 8, "gear-B", "z");
    const auto b = create(host, original_b);
    auto power = wire("set_power", "start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The source enables the actual geometry train.");
    check(field<I>(motion(host, a), "numerator") == -1 && field<I>(motion(host, a), "denominator") == 3 &&
          field<I>(motion(host, b), "numerator") == 1 && field<I>(motion(host, b), "denominator") == 3 &&
          field<I>(motion(host, collector), "numerator") == 1,
          "Meshing equal gears reverses the exact signed rate through the touching axles.");
    check(field<bool>(host.projection(), "powered") &&
          field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 8 &&
          field<I>(V(field<O>(host.projection(), "parts")), "gear") == 7,
          "The powered train retains the remaining shafts and cogs.");
    const auto ticked = host.advance();
    check(field<I>(V(field<O>(ticked, "stock")), "source") == 4095 &&
          field<I>(V(field<O>(ticked, "stock")), "collector") == 1,
          "The current direction-insensitive machine adapter extracts one unit from the larger finite node.");
    check(accepted(host.command("P", target("remove", b, "remove-B"))),
          "An individual gear can be removed while the source stays enabled.");
    check(!field<bool>(host.projection(), "powered"), "Removing a gear disconnects the source.");
    observe(host, 0, 1.65, 5);
    const auto misaligned = create(host, gear(0, 8, 8, "misaligned", "z"));
    check(!field<bool>(host.projection(), "powered"), "A cog in the adjacent tile cannot power the collector through a diagonal gap.");
    check(accepted(host.command("P", target("remove", misaligned, "remove-misaligned"))),
          "The actual misplaced part returns before reconstruction.");
    observe(host, 0, 0, 6);
    const auto rebuilt = create(host, gear(0, 4, 8, "rebuild-B", "z"));
    check(rebuilt != b && field<bool>(host.projection(), "powered") &&
          field<I>(motion(host, rebuilt), "numerator") == 1,
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
              accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())) &&
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
    observe(host, -1.65, 3.3, 1);
    auto base = wire("place_foundation", "direct-collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{1})})); base.emplace("level", V(I{4}));
    check(accepted(host.command("P", base)), "The fixture supports the collector foundation.");
    const auto wheel = create(host, machine("wheel", -2, "direct-wheel", "z"));
    auto collector_wire = machine("collector", 0, "direct-collector", "z");
    collector_wire.emplace("level", V(I{4}));
    const auto collector = create(host, collector_wire);
    observe(host, 0, 0, 2);
    observe(host, -3.3, 0, 3);
    const auto upper = create(host, gear(-8, 4, 8, "direct-upper", "z"));
    observe(host, 0, 0, 4);
    const auto a = create(host, gear(-4, 4, 8, "direct-cog-a", "z"));
    const auto b = create(host, gear(0, 4, 8, "direct-cog-b", "z"));
    observe(host, -1.65, 0, 5);
    const auto redundant = host.command("P", connection(wheel, upper, "direct-redundant"));
    check(!accepted(redundant) && field<std::string>(redundant, "reason") == "individual_shaft_required" &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 8,
          "Endpoint shaft construction is refused without consuming a part.");
    auto power = wire("set_power", "direct-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The current is enabled without installing a shaft.");
    check(field<I>(motion(host, wheel), "numerator") == 1 && field<I>(motion(host, wheel), "denominator") == 3 &&
              field<I>(motion(host, a), "numerator") == -1 &&
              field<I>(motion(host, b), "numerator") == 1 &&
              field<I>(motion(host, collector), "numerator") == 1 &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 8,
          "Adjacent axle faces carry signed rotation without consuming any finite shaft.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::channel_site())) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "Fresh Host restore retains direct axle geometry and part custody exactly.");
    check(accepted(host.command("P", target("remove", b, "direct-remove"))) &&
              field<std::string>(motion(host, collector), "state") != "rotating",
          "Removing the actual cog interrupts the adjacent-axle route.");
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
    auto overlapping = gear(-4, 4, 8, "actor-overlap");
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

void perpendicular_belt_line() {
    auto site = factory::godot_world::tests::channel_site();
    auto water = std::get<A>(site.at("water").storage());
    for (auto& sample_value : water) {
        auto sample = std::get<A>(sample_value.storage());
        sample[4] = V(I{-200});
        sample_value = V(std::move(sample));
    }
    site.at("water") = V(std::move(water));
    Host host;
    check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
              accepted(host.configure_terrain(site)),
          "The perpendicular-line Host binds its synthetic terrain.");
    observe(host, -1.65, 3.3, 1);
    auto base = wire("place_foundations", "line-collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{1})})); base.emplace("end_cell", V(A{V(I{2}), V(I{1})})); base.emplace("level", V(I{4}));
    check(accepted(host.command("P", base)), "The synthetic line has a supported collector.");
    const std::array<const char*, 4> roles{"wheel", "collector", "belt", "processor"};
    std::array<std::string, 4> hubs, cogs;
    observe(host, -1.65, 3.3, 2);
    hubs[0] = create(host, machine("wheel", -2, "line-machine-0", "z"));
    observe(host, -3.3, 0, 3);
    cogs[0] = create(host, gear(-8, 4, 8, "line-gear-0", "z", 2));
    create(host, gear(-4, 4, 8, "line-bridge", "z", 2));
    for (std::size_t n = 1; n < roles.size(); ++n) {
        const I x = static_cast<I>(n) - 1;
        observe(host, static_cast<double>(x) * 1.65, 0, static_cast<I>(n) + 4);
        const auto machine_id = "line-machine-" + std::to_string(n);
        const auto gear_id = "line-gear-" + std::to_string(n);
        auto machine_wire = machine(roles[n], x, machine_id.c_str(), "z");
        machine_wire.emplace("level", V(I{4}));
        hubs[n] = create(host, machine_wire);
        cogs[n] = create(host, gear(4 * x, 4, 8, gear_id.c_str(), "z", 2));
    }
    observe(host, -1.65, 0, 8);
    auto power = wire("set_power", "line-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The actor enables the source for the perpendicular line.");
    const auto projected = host.projection();
    check(field<A>(projected, "links").size() == 2 &&
              field<I>(V(field<O>(projected, "parts")), "shaft") == 8 &&
              field<I>(V(field<O>(projected, "parts")), "gear") == 5,
          "The connected line uses five small cogs and retains its shafts.");
    for (std::size_t n = 0; n < hubs.size(); ++n)
        check(field<I>(motion(host, hubs[n]), "numerator") == (n == 0 || n % 2 ? -1 : 1) &&
                  field<I>(motion(host, hubs[n]), "denominator") == 3,
              "The actual Host reports alternating signed machine rotation.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
              accepted(fresh.configure_terrain(site)) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "The full perpendicular route and finite kit survive fresh Host restoration.");
    for (int tick = 0; tick < 3; ++tick) (void)host.advance();
    const auto reversed = host.projection();
    check(field<I>(V(field<O>(reversed, "stock")), "input") == 0 &&
              field<A>(reversed, "dropped_material").size() == 1,
          "Positive Z belt rotation sends a blank to the reverse end instead of the press.");
    const auto drop = field<A>(reversed, "dropped_material").front();
    check(!factory::values::typed_difference(V(field<A>(drop, "center")), V(A{V(I{2}), V(I{4}), V(I{4})})) && field<I>(drop, "raw") == 1,
          "The loose blank has the native world-space reverse-end point.");
    const auto reverse_save = host.checkpoint();
    Host loaded;
    check(accepted(loaded.initialize("other", {"P", "Q"})) &&
              accepted(loaded.configure_terrain(site)) &&
              accepted(loaded.restore_checkpoint(reverse_save)),
          "The reverse-end blank survives a fresh Host checkpoint restore.");
    observe(loaded, 100.0, 100.0, 1);
    auto far_pickup = wire("pickup_material", "pickup-too-far");
    far_pickup.emplace("center", V(A{V(I{2}), V(I{4}), V(I{4})}));
    far_pickup.emplace("expected", V(O{{"raw", V(I{1})}, {"products", V(I{0})}, {"work_lots", V(A{})}}));
    const auto far_result = loaded.command("P", far_pickup);
    check(!accepted(far_result) && field<std::string>(far_result, "reason") == "out_of_reach" &&
              field<A>(loaded.projection(), "dropped_material").size() == 1,
          "A distant actor cannot pick up or consume the stack.");
    observe(loaded, 0.0, 0.0, 2);
    auto pickup = wire("pickup_material", "pickup-reverse");
    pickup.emplace("center", V(A{V(I{2}), V(I{4}), V(I{4})}));
    pickup.emplace("expected", far_pickup.at("expected"));
    auto stale = pickup;
    stale.at("request") = V("pickup-stale");
    stale.at("expected") = V(O{{"raw", V(I{0})}, {"products", V(I{1})}, {"work_lots", V(A{})}});
    const auto stale_result = loaded.command("P", stale);
    check(!accepted(stale_result) && field<std::string>(stale_result, "reason") == "drop_changed" &&
              field<A>(loaded.projection(), "dropped_material").size() == 1,
          "A stale selection cannot collect replacement material at the same point.");
    const auto result = loaded.command("P", pickup);
    check(accepted(result) && field<I>(result, "moved_raw") == 1 && field<A>(loaded.projection(), "dropped_material").empty(),
          "A reachable actor collects the original blank into canonical cargo.");
    check(accepted(loaded.publish_actor("Q", {V(0.0), V(1.0), V(0.0)}, 1)), "Q has a separate nearby synthetic observation.");
    auto competing = wire("pickup_material", "pickup-competing");
    competing.at("client") = V("Q");
    competing.emplace("center", V(A{V(I{2}), V(I{4}), V(I{4})}));
    competing.emplace("expected", far_pickup.at("expected"));
    const auto denied = loaded.command("Q", competing);
    check(!accepted(denied) && field<std::string>(denied, "reason") == "unavailable_drop" &&
              field<I>(field<O>(loaded.projection(), "cargo").at("Q"), "raw") == 0,
          "A second actor cannot acquire a stack already picked up by P.");
    check(field<bool>(loaded.command("P", pickup), "duplicate") && accepted(loaded.validate_checkpoint(loaded.checkpoint())),
          "Pickup retry and saved wire history retain the original outcome.");
    observe(host, 1.65, 0, 9);
    check(accepted(host.command("P", target("remove", cogs[2], "line-remove-belt-cog"))) &&
              field<std::string>(motion(host, hubs[2]), "state") != "rotating",
          "Removing the belt cog breaks belt power and returns the physical part.");
    check(accepted(host.command("P", target("recover", hubs[2], "line-recover-belt"))) &&
              accepted(host.command("P", target("remove", hubs[2], "line-remove-belt"))) &&
              field<A>(host.projection(), "dropped_material").size() == 1,
          "Recovering and dismantling the belt leaves its reverse-end blank in world custody.");
    const auto after_removal = host.checkpoint();
    Host after;
    check(accepted(after.initialize("after", {"P", "Q"})) &&
              accepted(after.configure_terrain(site)) &&
              accepted(after.restore_checkpoint(after_removal)),
          "A fresh Host retains loose material after its belt has been removed.");
    observe(after, 0.0, 0.0, 1);
    auto pickup_after = wire("pickup_material", "pickup-after-removal");
    pickup_after.emplace("center", V(A{V(I{2}), V(I{4}), V(I{4})}));
    pickup_after.emplace("expected", far_pickup.at("expected"));
    check(accepted(after.command("P", pickup_after)), "The independent loose stack remains reachable after belt removal.");
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
    const V lot(O{{"id", V(I{1})}, {"recipe", V(O{{"input_units_per_product", V(I{1})}, {"cycle_ticks", V(I{2})}})},
                 {"remaining_ticks", V(I{1})}, {"completed_subticks", V(I{123})}});
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

void belt_spindle_orientation() {
    Host host;
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
          "The belt orientation Host binds its site.");
    observe(host, -1.65, 3.3, 1);
    const auto before = world_state(host);
    for (const auto* wrong_axis : {"y"}) {
        const auto reply = host.command("P", machine("belt", 1, wrong_axis, wrong_axis));
        check(!accepted(reply) && field<std::string>(reply, "reason") == "invalid_belt_axis" &&
                  !factory::values::typed_difference(before, world_state(host)),
              "A belt refuses a vertical spindle without consuming the part.");
    }
    const auto belt = create(host, machine("belt", 1, "default-belt", nullptr));
    check(field<I>(V(field<O>(host.projection(), "entities").at(belt)), "axis") == 2,
          "A default belt uses the Z spindle perpendicular to its fixed X material path.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P"})) &&
              accepted(fresh.configure_terrain(factory::godot_world::tests::flat_site())) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "The perpendicular belt orientation survives checkpoint restoration.");
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
              field<I>(V(field<O>(host.projection(), "parts")), "belt") == 0,
          "The projection identifies the actual endpoints and consumed finite belt.");
    const auto intrusion = host.command("P", gear(4, 0, 0, "span-obstruction", "z"));
    check(!accepted(intrusion) && field<std::string>(intrusion, "reason") == "occupied",
          "A later cog cannot be placed through the installed belt.");
    const auto checkpoint = host.checkpoint();
    auto unsupported = std::get<O>(checkpoint.storage());
    auto unsupported_world = std::get<O>(unsupported.at("world").storage());
    auto unsupported_state = std::get<O>(unsupported_world.at("state").storage());
    auto unsupported_topology = std::get<O>(unsupported_state.at("topology").storage());
    auto unsupported_parts = std::get<A>(unsupported_topology.at("parts").storage());
    for (auto& entry : unsupported_parts) {
        auto value = std::get<O>(entry.storage());
        if (field<std::string>(entry, "id") != right) continue;
        value.at("center") = V(A{V(I{8}), V(I{8}), V(I{0})});
        entry = V(std::move(value));
    }
    unsupported_topology.at("parts") = V(std::move(unsupported_parts));
    unsupported_state.at("topology") = V(std::move(unsupported_topology));
    unsupported_world.at("state") = V(std::move(unsupported_state));
    unsupported.at("world") = V(std::move(unsupported_world));
    Host shallow;
    check(accepted(shallow.initialize("fresh", {"P"})) &&
              accepted(shallow.configure_terrain(factory::godot_world::tests::flat_site())), "The shallower site binds.");
    const auto buried_incline = shallow.validate_checkpoint(V(unsupported));
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
              field<I>(V(field<O>(restored.projection(), "parts")), "belt") == 1,
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
        observe_at(0, 0.825 + example.start_y * 1.65 / 4, -1.65, 1);
        const auto first = create(host, shaft(0, example.start_y, 0, "3d-first", example.axis));
        observe_at(example.x * 1.65 / 4, 0.825 + example.y * 1.65 / 4, example.z * 1.65 / 4 - 1.65, 2);
        const auto last = create(host, shaft(example.x, example.y, example.z, "3d-last", example.axis));
        auto install = wire("place_belt_span", "3d-blocked");
        install.emplace("from", V(first)); install.emplace("to", V(last));
        const double mx = example.x * 1.65 / 8, my = 0.825 + (example.start_y + example.y) * 1.65 / 8, mz = example.z * 1.65 / 8;
        observe_at(mx, my, mz, 3);
        const auto blocked = host.command("P", install);
        check(!accepted(blocked) && field<std::string>(blocked, "reason") == "actor_occupied", "A body intersecting the path refuses placement.");
        observe_at(mx, my, mz - 1.65, 4);
        install.at("request") = V("3d-clear");
        const auto span = create(host, install);
        check(field<O>(host.projection(), "belt_spans").contains(span), "The Host admits the nonhorizontal span.");
        if (std::string(example.axis) == "z" && example.x == 8 && example.start_y == 4) {
            const auto obstruction = host.command("P", gear(4, 8, 0, "3d-cog-intersection", "z"));
            check(!accepted(obstruction) && field<std::string>(obstruction, "reason") == "occupied",
                  "A later cog cannot intersect the inclined body.");
            create(host, gear(4, 0, 0, "3d-cog-below", "z"));
        }
        const auto checkpoint = host.checkpoint();
        Host loaded;
        check(accepted(loaded.initialize("fresh", {"P"})) &&
                  accepted(loaded.configure_terrain(low_flat_site())) &&
                  accepted(loaded.restore_checkpoint(checkpoint)) &&
                  !factory::values::typed_difference(checkpoint, loaded.checkpoint()), "The span survives a fresh Host restore.");
        auto blocked_site = low_flat_site();
        blocked_site.at("obstacles") = V(A{V(A{V(A{V(mx - 0.1), V(my - 0.1), V(mz - 0.1)}),
                                                 V(A{V(mx + 0.1), V(my + 0.1), V(mz + 0.1)})})});
        Host obstructed;
        check(accepted(obstructed.initialize("fresh", {"P"})) && accepted(obstructed.configure_terrain(blocked_site)) &&
                  !accepted(obstructed.validate_checkpoint(checkpoint)), "Restore refuses a site obstacle through the physical path.");
        if (std::string(example.axis) == "z" && example.x == 8 && example.start_y == 4) {
            auto clear_below = low_flat_site();
            clear_below.at("obstacles") = V(A{V(A{V(A{V(mx - 0.1), V(1.8), V(-0.1)}),
                                                    V(A{V(mx + 0.1), V(1.9), V(0.1)})})});
            Host below;
            check(accepted(below.initialize("fresh", {"P"})) && accepted(below.configure_terrain(clear_below)) &&
                      accepted(below.validate_checkpoint(checkpoint)), "Clearance does not fill the empty space below an incline.");
        }
    }
}

void complete_span_route_host() {
    Host host;
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)}, heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    const O stream{{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})},
        {"water", V(A{V(A{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})})})}};
    check(accepted(host.initialize("cog-api", {"P"})) && accepted(host.configure_terrain(stream)),
          "The complete span route binds an invented channel.");
    I epoch{};
    const auto at = [&](double x, double z) { observe(host, x, z, ++epoch); };
    at(-1.65, 3.3);
    auto wheel = machine("wheel", -2, "route-wheel", "x");
    wheel.at("cell") = V(A{V(I{-2}), V(I{0})});
    create(host, wheel);
    at(0, 0);
    auto base = wire("place_foundation", "raised-collector-base");
    base.emplace("cell", V(A{V(I{0}), V(I{1})})); base.emplace("level", V(I{4}));
    create(host, base);
    auto collector_command = machine("collector", 0, "route-collector", "z");
    collector_command.emplace("level", V(I{4}));
    const auto collector = create(host, collector_command);
    at(-3.3, 0);
    create(host, gear(-4, 4, 0, "route-input", "x", 4));
    at(-3.3, -1.65);
    create(host, gear(0, 4, -4, "route-output", "z", 4));
    for (I x : {I{0}, I{4}}) {
        at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
        const auto id = "route-cog-" + std::to_string(x);
        create(host, gear(x, 4, 0, id.c_str(), "z"));
    }
    for (I x : {I{4}, I{8}, I{12}}) {
        at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
        const auto id = "route-rear-cog-" + std::to_string(x);
        create(host, gear(x, 4, -4, id.c_str(), "z"));
    }
    at(4.95, -3.3);
    create(host, shaft(12, 4, 0, "route-press-drive"));
    at(1.65, 0);
    const auto first = create(host, shaft(4, 4, 4, "route-first"));
    at(3.3, 0);
    const auto last = create(host, shaft(8, 4, 4, "route-last"));
    at(2.475, 0);
    auto install = wire("place_belt_span", "route-span");
    install.emplace("from", V(first)); install.emplace("to", V(last));
    const auto span = create(host, install);
    at(4.95, 0);
    auto press_base = wire("place_foundation", "raised-press-base");
    press_base.emplace("cell", V(A{V(I{3}), V(I{1})})); press_base.emplace("level", V(I{4}));
    create(host, press_base);
    auto press_command = machine("processor", 3, "route-press", "z");
    press_command.emplace("level", V(I{4}));
    const auto press = create(host, press_command);
    at(-1.65, 0);
    auto power = wire("set_power", "route-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The source starts the complete constructed route.");
    check(field<std::string>(motion(host, collector), "state") == "rotating" &&
              field<std::string>(motion(host, first), "state") == "rotating" &&
              field<std::string>(motion(host, press), "state") == "rotating" &&
              field<I>(motion(host, first), "numerator") < 0,
          "The actual source powers collector, forward belt shafts and processor; collector=" + field<std::string>(motion(host, collector), "state") +
          ", shaft=" + field<std::string>(motion(host, first), "state") + ", press=" + field<std::string>(motion(host, press), "state") +
          ", shaft rate=" + std::to_string(field<I>(motion(host, first), "numerator")) + ".");
    for (int i = 0; i < 9; ++i) (void)host.advance();
    const auto in_flight_slots = field<A>(field<O>(host.projection(), "belt_spans").at(span), "slots");
    check(std::any_of(in_flight_slots.begin(), in_flight_slots.end(),
              [](const V& item) { return item.type() != factory::values::Type::null; }),
          "The checkpoint is taken with confirmed cargo on the actual belt.");
    const auto in_flight = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize("fresh", {"P"})) &&
              accepted(restored.configure_terrain(stream)) &&
              accepted(restored.restore_checkpoint(in_flight)), "An in-flight route restores in a fresh Host.");
    for (int i = 0; i < 100; ++i) {
        (void)host.advance(); (void)restored.advance();
    }
    check(!factory::values::typed_difference(host.checkpoint(), restored.checkpoint()) &&
              field<I>(V(field<O>(restored.projection(), "stock")), "output") > 0 &&
              field<O>(restored.projection(), "belt_spans").contains(span),
          "The original and restored constructed routes process transported material with identical custody.");
    at(4.95, 0);
    auto retrieve = target("retrieve", press, "route-retrieve"); retrieve.emplace("amount", V(I{1}));
    check(accepted(host.command("P", retrieve)) && field<I>(field<O>(host.projection(), "cargo").at("P"), "products") == 1,
          "The constructed route yields a finished product in the actor's custody.");
}

void rotated_belt_host() {
    const std::array<std::array<int, 3>, 6> orders{{
        {{0, 1, 2}}, {{0, 2, 1}}, {{1, 0, 2}},
        {{1, 2, 0}}, {{2, 0, 1}}, {{2, 1, 0}}
    }};
    const std::array<const char*, 3> kinds{{"collector", "belt", "processor"}};
    for (const auto& order : orders) {
        Host host;
        check(accepted(host.initialize("cog-api", {"P"})) &&
                  accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
              "The rotated route binds a synthetic flat site.");
        std::array<std::string, 3> ids;
        I epoch = 0;
        for (int index : order) {
            observe(host, -1.65, 1.65 * (index + 1), ++epoch);
            const auto request = "rotated-" + std::to_string(index);
            auto command = machine(kinds[index], 0, request.c_str(), index == 1 ? "x" : "z");
            command.at("cell") = V(A{V(I{0}), V(I{index + 1})});
            ids[index] = create(host, command);
        }
        const auto projection = host.projection();
        const auto& links = field<A>(projection, "links");
        check(links.size() == 2 && field<I>(V(field<O>(projection, "entities").at(ids[1])), "axis") == 0,
              "The Z material line auto-connects for every placement order and projects an X axle.");
        const auto saved = host.checkpoint();
        Host restored;
        check(accepted(restored.initialize("fresh", {"P"})) &&
                  accepted(restored.configure_terrain(factory::godot_world::tests::flat_site())) &&
                  accepted(restored.restore_checkpoint(saved)) &&
                  !factory::values::typed_difference(saved, restored.checkpoint()),
              "The rotated line and its historical requests restore exactly.");
    }
}

void cross_axis_belt_line() {
    Host host;
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)}, heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    const O stream{{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})},
        {"water", V(A{V(A{V(I{-8}), V(I{4}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})})})}};
    check(accepted(host.initialize("cog-api", {"P"})) &&
              accepted(host.configure_terrain(stream)),
          "The cross-axis Host binds an invented flowing stream.");
    I epoch{};
    const auto at = [&](double x, double z) { observe(host, x, z, ++epoch); };
    at(0, 0);
    auto base = wire("place_foundations", "cross-bases");
    base.emplace("cell", V(A{V(I{0}), V(I{1})}));
    base.emplace("end_cell", V(A{V(I{2}), V(I{1})})); base.emplace("level", V(I{4}));
    create(host, base);
    const std::array<const char*, 4> roles{"wheel", "collector", "belt", "processor"};
    std::array<std::string, 4> hubs;
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const I x = n == 0 ? -2 : static_cast<I>(n) - 1;
        at(n == 0 ? -1.65 : static_cast<double>(x) * 1.65, n == 0 ? 3.3 : 0);
        const auto id = "cross-machine-" + std::to_string(n);
        auto machine_wire = machine(roles[n], x, id.c_str(), n ? "z" : "x");
        if (n) machine_wire.emplace("level", V(I{4}));
        hubs[n] = create(host, machine_wire);
    }
    at(-3.3, 0);
    const auto input = create(host, gear(-4, 4, 4, "cross-input", "x", 4));
    at(-3.3, 1.65);
    const auto output = create(host, gear(0, 4, 8, "cross-output", "z", 4));
    std::array<std::string, 3> small;
    for (std::size_t n = 0; n < small.size(); ++n) {
        const I x = static_cast<I>(n) * 4;
        at(static_cast<double>(x) * 1.65 / 4.0, 3.3);
        const auto id = "cross-small-" + std::to_string(n);
        small[n] = create(host, gear(x, 4, 12, id.c_str(), "z", 2));
    }
    at(-3.3, 3.3);
    for (std::size_t n = 2; n < hubs.size(); ++n) {
        at(static_cast<double>(n - 1) * 1.65, 0);
        const auto id = "cross-machine-shaft-" + std::to_string(n);
        check(accepted(host.command("P", shaft(static_cast<I>(n - 1) * 4, 4, 8, id.c_str()))),
              "The actor installs one shaft tile between each machine and its cog.");
    }
    at(-1.65, 0);
    auto power = wire("set_power", "cross-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The source starts the cross-axis line.");
    for (std::size_t n = 1; n < hubs.size(); ++n) {
        check(field<I>(motion(host, hubs[n]), "numerator") == (n % 2 ? -1 : 1) &&
                  field<I>(motion(host, hubs[n]), "denominator") == 3,
              "Every machine reports its signed cross-axis motion.");
    }
    const auto advanced = host.advance();
    check(field<I>(V(field<O>(advanced, "stock")), "source") == 4095 &&
              field<I>(V(field<O>(advanced, "stock")), "collector") == 1,
          "The flowing wheel powers the collector and advances one source unit.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P"})) &&
              accepted(fresh.configure_terrain(stream)) &&
              accepted(fresh.restore_checkpoint(saved)) && !factory::values::typed_difference(saved, fresh.checkpoint()),
          "The complete one-tile shaft route restores exactly in a fresh Host.");
    at(-3.3, 1.65);
    check(accepted(host.command("P", target("remove", output, "cross-remove"))) &&
              field<std::string>(motion(host, hubs[2]), "state") != "rotating",
          "Removing the corner cog interrupts belt power.");
}

void equivalent_gear_exclusion() {
    for (const auto* axis : std::array<const char*, 4>{"x", "y", "z", nullptr}) {
        const auto* effective_axis = axis ? axis : "x";
        const bool axial_x = std::string(effective_axis) == "x";
        const A blocked{V(axial_x ? 0.0 : 1.1), V(0.9), V(axial_x ? 2.75 : 1.65)};
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
    check(accepted(host.publish_actor("P", {V(16.5), V(6.0), V(6.0)}, 1)),
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
    create(host, machine("wheel", -2, "shaft-wheel", "z"));
    observe(host, -1.65, 0, 2);
    const auto first_wire = shaft(-8, 4, 8, "first-segment");
    const auto first = create(host, first_wire);
    const auto before_parts = field<O>(host.projection(), "transmission_parts");
    const auto duplicate = shaft(-8, 4, 8, "overlap-identical");
    check(field<std::string>(host.command("P", duplicate), "reason") == "occupied" &&
              field<std::string>(host.command("P", shaft(-8, 4, 9, "off-grid")), "reason") == "invalid_cell" &&
              !factory::values::typed_difference(V(field<O>(host.projection(), "transmission_parts")), V(before_parts)) &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 7,
          "Occupied and off-grid shaft placements are refused without consuming parts.");
    check(field<bool>(host.command("P", duplicate), "duplicate"),
          "An overlapping placement refusal is stable on replay.");
    observe(host, -1.65, 3.3, 3);
    const auto second = create(host, shaft(-8, 4, 12, "second-segment"));
    auto power = wire("set_power", "shaft-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)) && field<I>(motion(host, second), "numerator") == 1,
          "Two individually placed, touching shaft segments carry the wheel rotation.");
    check(field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 6,
          "Both segment placements consume their own finite parts.");
    check(accepted(host.command("P", target("remove", first, "remove-first-segment"))) &&
              field<I>(motion(host, second), "numerator") == 0 &&
              field<I>(V(field<O>(host.projection(), "parts")), "shaft") == 7,
          "Removing the first segment disconnects the second and refunds one part.");
    const auto replacement = create(host, shaft(-8, 4, 8, "replacement-segment"));
    check(field<I>(motion(host, replacement), "numerator") == 1 &&
              field<I>(motion(host, second), "numerator") == 1,
          "A replacement one-tile segment reconnects the source to the remaining segment.");
    observe(host, 0, 3.3, 4);
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

void forward_belt_route() {
    Host host;
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)}, heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    const O stream{{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})},
        {"water", V(A{V(A{V(I{-8}), V(I{4}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})})})}};
    check(accepted(host.initialize("cog-api", {"P"})) && accepted(host.configure_terrain(stream)),
          "The alternate belt route binds an explicit invented stream.");
    I epoch{};
    const auto at = [&](double x, double z) { observe(host, x, z, ++epoch); };
    at(0, 0);
    auto base = wire("place_foundations", "forward-bases");
    base.emplace("cell", V(A{V(I{0}), V(I{1})}));
    base.emplace("end_cell", V(A{V(I{2}), V(I{1})})); base.emplace("level", V(I{4}));
    create(host, base);
    const std::array<const char*, 4> roles{"wheel", "collector", "belt", "processor"};
    std::array<std::string, 4> hubs;
    for (std::size_t n = 0; n < hubs.size(); ++n) {
        const I x = n == 0 ? -2 : static_cast<I>(n) - 1;
        at(n == 0 ? -1.65 : static_cast<double>(x) * 1.65, n == 0 ? 3.3 : 0);
        const auto id = "forward-machine-" + std::to_string(n);
        auto machine_wire = machine(roles[n], x, id.c_str(), n ? "z" : "x");
        if (n) machine_wire.emplace("level", V(I{4}));
        hubs[n] = create(host, machine_wire);
    }
    at(-3.3, 0);
    create(host, gear(-4, 4, 4, "forward-input", "x", 4));
    at(-3.3, -1.65);
    create(host, gear(0, 4, 0, "forward-output", "z", 4));
    std::array<std::string, 3> cogs;
    for (std::size_t n = 0; n < cogs.size(); ++n) {
        const I x = static_cast<I>(n) * 4;
        at(static_cast<double>(x) * 1.65 / 4.0, -3.3);
        const auto id = "forward-cog-" + std::to_string(n);
        cogs[n] = create(host, gear(x, 4, -4, id.c_str(), "z", 2));
    }
    for (std::size_t n = 2; n < hubs.size(); ++n) {
        at(static_cast<double>(n - 1) * 1.65, -3.3);
        const auto id = "forward-shaft-" + std::to_string(n);
        check(accepted(host.command("P", shaft(static_cast<I>(n - 1) * 4, 4, 0, id.c_str()))),
              "The forward route connects each machine to its cog with one shaft tile.");
    }
    at(-3.3, 0);
    auto power = wire("set_power", "forward-start"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The extended cog train can start.");
    const auto wheel_rate = field<I>(motion(host, hubs[0]), "numerator");
    const auto belt_rate = field<I>(motion(host, hubs[2]), "numerator");
    check(wheel_rate < 0 && belt_rate < 0 &&
              field<I>(V(field<O>(host.projection(), "parts")), "gear") == 5,
          "The raised corner cogs drive the belt forward within the finite kit; wheel=" +
          std::to_string(wheel_rate) + ", belt=" + std::to_string(belt_rate) + ".");
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
    for (std::size_t axis = 0; axis < axes.size(); ++axis) {
        for (const bool alias : {false, true}) {
            Host host;
            check(accepted(host.initialize("cog-api", {"P", "Q"})) &&
                      accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The cog axle clearance Host starts.");
            check(accepted(host.publish_actor("P", {V(0.0), V(3.8), V(-2.0)}, 1)), "The builder is within reach and clear.");
            std::array<double, 3> blocker{0.0, 3.8, 0.0};
            blocker[axis] += axis == 1 ? 1.55 : 0.7;
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
        std::array<double, 3> obstacle{0.0, 2.475, 0.0};
        obstacle[part_case == 2 ? (axis + 1) % 3 : axis] += 0.5;
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
        const double half_height = (is_gear || axis == 1) ? 0.825 : 0.1;
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
              accepted(clear.configure_terrain(site_at(0.825 - half_height))), "The contact site binds.");
        observe(clear, 0, -1.65, 1);
        check(accepted(clear.command("P", command("contact"))),
              "A transmission part may touch the terrain without penetrating it.");
        const auto saved = clear.checkpoint();
        Host buried;
        check(accepted(buried.initialize("cog-api", {"P"})) &&
              accepted(buried.configure_terrain(site_at(0.825 - half_height + 0.01))), "The penetrating site binds.");
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
        check(!accepted(restore) && field<std::string>(restore, "reason") == "site_occupied",
              "Checkpoint validation applies the same terrain clearance.");
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
    for (std::size_t axis = 0; axis < axes.size(); ++axis) for (const bool is_gear : {false, true}) {
        const auto base = [] (const char* id) {
            auto command = wire("place_foundation", id);
            command.emplace("cell", V(A{V(I{0}), V(I{0})})); command.emplace("level", V(I{6}));
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
            moved.at("center") = V(A{V(I{0}), V(I{6}), V(I{0})});
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
    area.emplace("level", V(I{6}));
    const auto rejected = host.command("P", area);
    check(!accepted(rejected) && field<std::string>(rejected, "reason") == "occupied" &&
              !factory::values::typed_difference(before, world_state(host)),
          "An obstructed foundation area refuses atomically without consuming any blocks.");
    auto touching = wire("place_foundation", "touching-base");
    touching.emplace("cell", V(A{V(I{1}), V(I{0})})); touching.emplace("level", V(I{6}));
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

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--tile-center-only") { transmission_tile_center(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--foundation-only") { transmission_foundation_clearance(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--terrain-only") { transmission_terrain_clearance(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--raised-route-only") { complete_span_route_host(); return 0; }
        if (argc == 2 && std::string(argv[1]) == "--transmission-site-only") {
            transmission_site_clearance();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_transmission_site\",\"checks\":" << checks << "}" << std::endl;
            return 0;
        }
        if (argc == 2 && std::string(argv[1]) == "--one-tile-only") {
            one_tile_placement();
            std::cout << "{\"status\":\"pass\",\"evidence\":\"native_one_tile_host\",\"checks\":" << checks << "}" << std::endl;
            return 0;
        }
        if (argc == 1) {
            finite_oriented_train_and_restore(); adjacent_axle_faces(); refusals_and_legacy_shape(); cog_axle_actor_clearance(); cog_at_belt_face(); transmission_site_clearance(); transmission_terrain_clearance(); transmission_foundation_clearance(); one_tile_placement();
            transmission_tile_center(); global_grid(); finite_large_cog(); perpendicular_belt_line(); belt_spindle_orientation(); typed_loose_host(); belt_span_host_commands(); nonhorizontal_span_host(); complete_span_route_host(); rotated_belt_host(); cross_axis_belt_line(); individual_shafts(); forward_belt_route();
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
