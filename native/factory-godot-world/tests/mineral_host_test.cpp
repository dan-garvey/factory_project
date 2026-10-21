#include "factory/godot_world.hpp"
#include "factory/mineral_site.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
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
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class T> const T& field(const V& value, const char* name) {
    return std::get<T>(std::get<O>(value.storage()).at(name).storage());
}
V child(const V& value, const char* name) { return V(field<O>(value, name)); }
bool accepted(const V& value) { return field<bool>(value, "accepted"); }
bool same(const V& left, const V& right) { return !factory::values::typed_difference(left, right); }
void outcome(const V& value, bool wanted, const char* reason) {
    if (accepted(value) != wanted || field<std::string>(value, "reason") != reason)
        std::cerr << "Expected " << reason << " accepted=" << wanted << ", got "
                  << field<std::string>(value, "reason") << " accepted=" << accepted(value) << '\n';
    check(accepted(value) == wanted && field<std::string>(value, "reason") == reason, reason);
}
O request(const char* action, const std::string& id, const char* actor = "P") {
    return {{"context", V("mineral-site")}, {"client", V(actor)}, {"request", V(id)}, {"action", V(action)}};
}
O place(const std::string& id, const char* kind, I x, I z, I level = 0) {
    auto wire = request("place", id);
    wire.emplace("kind", V(kind)); wire.emplace("cell", V(A{V(x), V(z)})); wire.emplace("level", V(level));
    return wire;
}
O foundation(const std::string& id, I level) {
    auto wire = request("place_foundation", id);
    wire.emplace("cell", V(A{V(I{0}), V(I{0})})); wire.emplace("level", V(level));
    return wire;
}
O targeted(const char* action, const std::string& id, const std::string& entity, const char* actor = "P") {
    auto wire = request(action, id, actor); wire.emplace("entity", V(entity)); return wire;
}
O drive(const std::string& id, const std::string& from, const std::string& to) {
    auto wire = request("connect_drive", id); wire.emplace("from", V(from)); wire.emplace("to", V(to)); return wire;
}
V material_state(const Host& host) { return child(child(host.checkpoint(), "world"), "state"); }

// Retain the actual native checkpoint for a separate engine/Store encoding
// check without replaying extraction. Numeric payloads are decimal strings;
// explicit tags preserve integer versus floating types across JSON readers.
void hex_string(std::ostream& out, const std::string& value) {
    constexpr char hex[] = "0123456789abcdef";
    out << '"';
    for (const unsigned char byte : value) out << hex[byte >> 4] << hex[byte & 15];
    out << '"';
}
void tagged(std::ostream& out, const V& value) {
    using Type = factory::values::Type;
    const auto& data = value.storage();
    switch (value.type()) {
        case Type::null: out << "[\"null\"]"; break;
        case Type::boolean: out << "[\"boolean\"," << (std::get<bool>(data) ? "true" : "false") << ']'; break;
        case Type::integer: out << "[\"integer\",\"" << std::get<I>(data) << "\"]"; break;
        case Type::floating:
            out << "[\"floating\",\"" << std::setprecision(std::numeric_limits<double>::max_digits10)
                << std::get<double>(data) << "\"]"; break;
        case Type::string: out << "[\"string\","; hex_string(out, std::get<std::string>(data)); out << ']'; break;
        case Type::array: {
            out << "[\"array\",[";
            bool first = true;
            for (const auto& item : std::get<A>(data)) { if (!first) out << ','; first = false; tagged(out, item); }
            out << "]]"; break;
        }
        case Type::object: {
            out << "[\"object\",[";
            bool first = true;
            for (const auto& [key, item] : std::get<O>(data)) {
                if (!first) out << ',';
                first = false; out << '['; hex_string(out, key); out << ','; tagged(out, item); out << ']';
            }
            out << "]]"; break;
        }
    }
}
void retain_checkpoint(const V& saved, const O& site) {
    const auto* directory = std::getenv("TEST_UNDECLARED_OUTPUTS_DIR");
    if (!directory || !*directory) return;
    std::ofstream out(std::filesystem::path(directory) / "depleted-checkpoint.tagged.json", std::ios::binary);
    tagged(out, V(O{{"checkpoint", saved}, {"site", V(site)}})); out << '\n'; out.close();
    check(static_cast<bool>(out), "The actual native checkpoint is retained for consumer encoding checks.");
}
O flat(double height = -0.02) {
    auto site = factory::godot_world::tests::flat_site();
    site.at("heights") = V(A{V(height), V(height), V(height), V(height)});
    return site;
}
O wet_site() {
    A heights;
    for (int row = 0; row < 4; ++row)
        for (const auto height : {-1.65, -1.65, -0.02, -0.02}) heights.emplace_back(height);
    return {{"axis", V(A{V(-128.0), V(-2.8), V(-2.0), V(128.0)})},
        {"heights", V(std::move(heights))}, {"obstacles", V(A{})},
        {"water", V(A{V(A{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{0}), V(I{200})})})}};
}
void initialize(Host& host, const O& terrain = flat()) {
    outcome(host.initialize("mineral-site", {"P", "Q"}), true, "initialized");
    outcome(host.configure_terrain(terrain), true, "terrain_bound");
}
void observe(Host& host, double y = 1.0, double z = 1.65, double x = 1.65) {
    // Explicit synthetic cuts for a logical Host test, never body observations.
    outcome(host.publish_actor("P", {V(x), V(y), V(z)}, 1), true, "actor_published");
}

void footprint_and_profile() {
    Host host; initialize(host); observe(host);
    const auto view = host.projection();
    const auto deposit = child(view, "source_deposit");
    check(field<I>(view, "initial_feed") == 4096 && field<I>(deposit, "initial_units") == 4096 &&
          field<I>(child(view, "stock"), "source") == 4096, "One World starts with the declared finite node reserve.");
    check(field<I>(deposit, "collector_capacity") == 32 && field<double>(deposit, "maximum_depth") == 3.3,
          "The bounded batch buffer and shared-grid drill depth are disclosed.");
    check(same(V(field<A>(deposit, "cells")), V(A{V(A{V(I{0}), V(I{0})}), V(A{V(I{0}), V(I{1})})})),
          "The view receives the same two native mineral cells, not another source column.");
    const auto original = material_state(host);
    for (const I z : {I{-4}, I{-1}, I{2}, I{9}}) {
        Host outside; initialize(outside); observe(outside, 1.0, z * 1.65 + 1.65);
        const auto before = material_state(outside);
        const auto wire = place("outside", "collector", 0, z);
        outcome(outside.command("P", wire), false, "not_at_seam");
        check(same(before, material_state(outside)), "Off-deposit refusal preserves all material, kits and identities.");
        check(field<bool>(outside.command("P", wire), "duplicate"), "A cached source refusal is not a new placement.");
    }
    check(same(original, material_state(host)), "Reading the deposit descriptor does not alter its stock.");
    for (const I z : {I{0}, I{1}}) {
        Host inside; initialize(inside); observe(inside, 1.0, z * 1.65 + 1.65);
        check(accepted(inside.command("P", place("inside", "collector", 0, z))), "Either mineral surface tile can host the node's collector.");
    }
}

void foundations_and_restore() {
    for (const I level : {I{-4}, I{0}, I{4}, I{8}, I{12}}) {
        Host host; initialize(host, flat(0.0)); observe(host, level * 0.4125 + 1.0);
        check(accepted(host.command("P", foundation("foundation", level))), "The native foundation uses the shared global level.");
        const auto before = material_state(host);
        const auto response = host.command("P", place("collector", "collector", 0, 0, level));
        if (level < 0) outcome(response, false, "collector_below_source");
        else if (level > 8) outcome(response, false, "source_too_deep");
        else check(accepted(response), "A supported collector can extract through the permitted foundation height.");
        if (!accepted(response)) check(same(before, material_state(host)), "Height refusal is material- and kit-atomic.");
        else {
            Host fresh; initialize(fresh, flat(0.0));
            outcome(fresh.restore_checkpoint(host.checkpoint()), true, "restored");
            check(same(material_state(host), material_state(fresh)), "Elevated collector and foundation restore exactly.");
        }
    }
    auto slope = flat();
    slope.at("heights") = V(A{V(-0.3), V(-0.3), V(0.4), V(0.4)});
    Host host; initialize(host, slope); observe(host, 2.65);
    outcome(host.command("P", place("unsupported", "collector", 0, 0, 4)), false, "foundation_required");
    check(accepted(host.command("P", foundation("level-slope", 4))), "A foundation supplies a level global-grid deck over a slope.");
    check(accepted(host.command("P", place("supported", "collector", 0, 0, 4))), "The same mineral surface remains extractable below the leveled deck.");
    const auto saved = host.checkpoint();
    for (const auto& [terrain, reason] : {std::pair{flat(2.0), "collector_below_source"},
                                       std::pair{flat(-4.0), "source_too_deep"}}) {
        Host incompatible; initialize(incompatible, terrain);
        const auto before = incompatible.checkpoint();
        outcome(incompatible.restore_checkpoint(saved), false, reason);
        check(same(before, incompatible.checkpoint()), "A mismatched mineral-surface import leaves the fresh Host unchanged.");
    }
}

void full_finite_depletion() {
    const auto site = wet_site();
    Host host; initialize(host, site); observe(host, 1.0, 1.65, -1.65);
    outcome(host.publish_actor("Q", {V(1.65), V(1.0), V(1.65)}, 1), true, "actor_published");
    const auto collector_reply = host.command("P", place("collector", "collector", 0, 0));
    check(accepted(collector_reply), "The depletion case places its real native collector.");
    const auto collector = field<std::string>(collector_reply, "entity");
    const auto wheel_reply = host.command("P", place("wheel", "wheel", -2, 0, 4));
    check(accepted(wheel_reply), "The native wheel supplies the finite extraction case.");
    auto upper = request("place_gear", "upper");
    upper.emplace("center", V(A{V(I{-4}), V(I{4}), V(I{0})}));
    upper.emplace("axis", V("x")); upper.emplace("teeth", V(I{2}));
    const auto upper_reply = host.command("P", upper);
    auto lower = request("place_gear", "lower");
    lower.emplace("center", V(A{V(I{-4}), V(I{0}), V(I{0})}));
    lower.emplace("axis", V("x")); lower.emplace("teeth", V(I{2}));
    const auto lower_reply = host.command("P", lower);
    check(accepted(upper_reply) && accepted(lower_reply), "The two cogs transfer the raised wheel to the ground collector.");
    const auto lower_id = field<std::string>(lower_reply, "entity");
    auto power = request("set_power", "power"); power.emplace("active", V(true));
    check(accepted(host.command("P", power)), "The extraction case starts through the normal native command boundary.");
    for (I batch = 0; batch < 128; ++batch) {
        for (int tick = 0; tick < 32; ++tick) (void)host.advance();
        const auto before = host.projection();
        check(field<I>(child(before, "stock"), "source") == 4096 - (batch + 1) * 32 &&
              field<I>(child(before, "stock"), "collector") == 32, "Each batch mines its exact original raw units once.");
        const char* actor = batch % 2 == 0 ? "P" : "Q";
        check(accepted(host.command(actor, targeted("recover", "batch-" + std::to_string(batch), collector, actor))),
              "Either admitted actor can recover the finite collector batch into its own Cargo.");
        const auto view = host.projection();
        const auto cargo = child(view, "cargo");
        check(field<I>(child(cargo, "P"), "raw") == ((batch + 2) / 2) * 32 &&
              field<I>(child(cargo, "Q"), "raw") == ((batch + 1) / 2) * 32 &&
              field<I>(child(view, "stock"), "collector") == 0, "Shared custody and emptied buffer account for every mined unit.");
        for (const auto* slot : {"belt", "input", "held", "output", "player"})
            check(field<I>(child(view, "stock"), slot) == 0, "Raw extraction invents no other material holder or product.");
        for (const auto* owner : {"P", "Q"})
            check(field<I>(child(cargo, owner), "products") == 0 && field<A>(child(cargo, owner), "work_lots").empty(),
                  "Recovered raw units remain raw, with no invented work or product.");
    }
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "The entire finite depletion and history fit the native checkpoint budget.");
    retain_checkpoint(saved, site);
    check(field<I>(host.projection(), "order") == 133, "Five construction/power requests and 128 recoveries exhaust the node within history bounds.");
    Host fresh; initialize(fresh, site);
    outcome(fresh.restore_checkpoint(saved), true, "restored");
    check(same(child(saved, "world"), child(fresh.checkpoint(), "world")), "Fresh native restoration preserves the complete depleted state and original cache.");
    const auto restored = material_state(fresh);
    for (I batch = 0; batch < 2; ++batch) {
        const char* actor = batch == 0 ? "P" : "Q";
        const auto duplicate = fresh.command(actor, targeted("recover", "batch-" + std::to_string(batch), collector, actor));
        check(accepted(duplicate) && field<bool>(duplicate, "duplicate"), "Original accepted recovery outcomes replay without another native admission.");
        check(same(restored, material_state(fresh)), "Cached replay cannot duplicate or retarget depleted ore.");
    }
    observe(fresh, 1.0, 1.65, -1.65);
    check(accepted(fresh.command("P", targeted("remove", "remove", collector))), "The empty collector is removable after depletion.");
    const auto rebuilt = fresh.command("P", place("rebuilt", "collector", 0, 0));
    check(accepted(rebuilt) && field<std::string>(rebuilt, "entity") != collector, "Rebuilding the collector allocates a new identity rather than a new deposit.");
    check(field<bool>(fresh.projection(), "powered"), "The rebuilt collector uses the lower cog left in place by removal.");
    const auto before_duplicate_shaft = material_state(fresh);
    outcome(fresh.command("P", drive("new-shaft", lower_id, field<std::string>(rebuilt, "entity"))), false, "individual_shaft_required");
    check(same(before_duplicate_shaft, material_state(fresh)), "A duplicate shaft request preserves the depleted stock, kits and identities.");
    for (int tick = 0; tick < 40; ++tick) (void)fresh.advance();
    const auto final = fresh.projection();
    check(field<I>(child(final, "stock"), "source") == 0 && field<I>(child(final, "stock"), "collector") == 0 &&
          field<I>(child(child(final, "cargo"), "P"), "raw") == 2048 &&
          field<I>(child(child(final, "cargo"), "Q"), "raw") == 2048,
          "A rebuilt, powered collector cannot refill a depleted node or change either actor's custody.");
    check(accepted(fresh.validate_checkpoint(fresh.checkpoint())), "Depletion, replay and rebuilt identities remain checkpoint-valid.");
}
}  // namespace

int main() {
    try {
        footprint_and_profile(); foundations_and_restore(); full_finite_depletion();
        std::cout << checks << " native mineral placement, depletion and checkpoint checks passed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
