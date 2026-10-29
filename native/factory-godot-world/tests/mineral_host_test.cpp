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

O source_contact_site(bool extra_obstacle = false, double height = -0.02) {
    auto terrain = flat(height);
    A obstacles{V(A{V(A{V(-1.03), V(0.35), V(-0.2)}),
                    V(A{V(-0.76), V(0.65), V(1.2)})})};
    if (extra_obstacle)
        obstacles.emplace_back(A{V(A{V(-0.97), V(0.40), V(-0.1)}),
                                  V(A{V(-0.88), V(0.58), V(0.1)})});
    terrain.at("obstacles") = V(std::move(obstacles));
    terrain.emplace("source_obstacle", V(I{0}));
    return terrain;
}

void grounded_intake_clearance() {
    auto missing = source_contact_site();
    missing.erase("source_obstacle");
    Host unmarked; initialize(unmarked, missing); observe(unmarked);
    outcome(unmarked.command("P", place("unmarked", "collector", 0, 0)), false, "site_occupied");
    auto wrong = source_contact_site();
    wrong.at("source_obstacle") = V(I{1});
    Host invalid;
    outcome(invalid.initialize("mineral-site", {"P", "Q"}), true, "initialized");
    outcome(invalid.configure_terrain(wrong), false, "invalid_terrain");
    for (const I cell : {I{0}, I{1}}) {
        Host host; initialize(host, source_contact_site());
        observe(host, 1.0, cell * 1.65 + 1.65);
        const auto placed = host.command("P", place("contact", "collector", 0, cell));
        check(accepted(placed), "The trusted source hull permits the occupied pickup at both admitted cells.");
        Host loaded; initialize(loaded, source_contact_site());
        outcome(loaded.restore_checkpoint(host.checkpoint()), true, "restored");
        check(same(material_state(host), material_state(loaded)),
              "A fresh Host verifies the same source clearance and restores exact material custody.");
        Host incompatible; initialize(incompatible, missing);
        const auto before = incompatible.checkpoint();
        outcome(incompatible.restore_checkpoint(host.checkpoint()), false, "site_occupied");
        check(same(before, incompatible.checkpoint()), "Missing source identity refuses restore without changing the Host.");
    }
    Host blocked; initialize(blocked, source_contact_site(true)); observe(blocked);
    const auto before = material_state(blocked);
    outcome(blocked.command("P", place("blocked", "collector", 0, 0)), false, "site_occupied");
    check(same(before, material_state(blocked)), "A different obstacle in the pickup remains a material-atomic refusal.");
    Host actor; initialize(actor, source_contact_site());
    observe(actor, 1.0, 0.0, -0.85);
    outcome(actor.command("P", place("actor", "collector", 0, 0)), false, "actor_occupied");
    Host neighboring_foundation; initialize(neighboring_foundation, source_contact_site());
    observe(neighboring_foundation);
    check(accepted(neighboring_foundation.command("P", place("contact", "collector", 0, 0))),
          "The ground collector occupies its source-facing intake before a neighboring foundation is placed.");
    auto clear_base = foundation("clear-neighbor", 4);
    clear_base.at("cell") = V(A{V(I{-1}), V(I{0})});
    outcome(neighboring_foundation.publish_actor("P", {V(0.0), V(1.0), V(2.0)}, 2),
            true, "actor_published");
    const auto before_stock = child(neighboring_foundation.projection(), "stock");
    outcome(neighboring_foundation.command("P", clear_base), true, "ok");
    check(same(before_stock, child(neighboring_foundation.projection(), "stock")),
          "A neighboring 3U slab clears the ground pickup without spending ore.");
    Host intake_after_foundation; initialize(intake_after_foundation, source_contact_site());
    observe(intake_after_foundation, 1.0, 2.0, 0.0);
    outcome(intake_after_foundation.command("P", clear_base), true, "ok");
    outcome(intake_after_foundation.command("P", place("collector-after-foundation", "collector", 0, 0)),
            true, "ok");
    check(same(before_stock, child(intake_after_foundation.projection(), "stock")),
          "The opposite construction order retains the same finite mineral stock.");
}

void raised_source_lift_clearance() {
    for (const I cell : {I{0}, I{1}}) {
        Host host; initialize(host, source_contact_site(false, 0.0));
        observe(host, 2.65, cell * 0.825 + 1.65);
        const auto base = foundation("raised-base", 4);
        outcome(host.command("P", base), true, "ok");
        const auto before = material_state(host);
        const auto raised = place("raised-lift", "collector", 0, cell, 4);
        outcome(host.command("P", raised), false, "occupied");
        check(same(before, material_state(host)),
              "A full-size lift cannot enter its 3U support slab or spend native material.");
        const auto duplicate = host.command("P", raised);
        check(!accepted(duplicate) && field<bool>(duplicate, "duplicate") &&
              field<std::string>(duplicate, "reason") == "occupied",
              "The exact occupied lift refusal replays without another placement.");
    }
}

void foundations_and_restore() {
    Host ground; initialize(ground, flat(0.0)); observe(ground);
    outcome(ground.command("P", place("ground", "collector", 0, 0)), true, "ok");
    const auto saved = ground.checkpoint();
    Host fresh; initialize(fresh, flat(0.0));
    outcome(fresh.restore_checkpoint(saved), true, "restored");
    check(same(saved, fresh.checkpoint()),
          "The grounded collector and finite source restore on the half-U profile.");
    Host raised; initialize(raised, flat(0.0)); observe(raised, 2.65);
    outcome(raised.command("P", foundation("raised-base", 4)), true, "ok");
    const auto before = material_state(raised);
    outcome(raised.command("P", place("raised", "collector", 0, 0, 4)), false, "occupied");
    check(same(before, material_state(raised)),
          "The solid 3U support refuses the old lift without moving ore or kits.");
}

void full_finite_depletion() {
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

    Host host; initialize(host, site);
    outcome(host.publish_actor("P", {V(-3.3), V(1.0), V(3.3)}, 1), true, "actor_published");
    outcome(host.publish_actor("Q", {V(2.0), V(1.0), V(0.0)}, 1), true, "actor_published");
    auto wheel_wire = place("wheel", "wheel", -6, 2);
    wheel_wire.emplace("axis", V("z")); wheel_wire.emplace("tiles", V(I{3}));
    outcome(host.command("P", wheel_wire), true, "ok");
    outcome(host.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 2), true, "actor_published");
    auto collector_wire = place("collector", "collector", 0, 1);
    collector_wire.emplace("axis", V("z"));
    const auto collector_reply = host.command("P", collector_wire);
    outcome(collector_reply, true, "ok");
    const auto collector = field<std::string>(collector_reply, "entity");
    outcome(host.publish_actor("P", {V(-4.95), V(1.0), V(4.0)}, 3), true, "actor_published");
    for (const auto& [x, z] : {std::pair<I, I>{-24, 12}, {-20, 12}, {-16, 12}, {-12, 12},
                              {-8, 12}, {-4, 12}, {-4, 8}, {0, 8}}) {
        if (x == -8)
            outcome(host.publish_actor("P", {V(-1.0), V(1.0), V(4.0)}, 4), true, "actor_published");
        auto cog = request("place_gear", "ground-cog-" + std::to_string(x) + "-" + std::to_string(z));
        cog.emplace("center", V(A{V(x), V(I{0}), V(z)}));
        cog.emplace("axis", V("z")); cog.emplace("teeth", V(I{2}));
        outcome(host.command("P", cog), true, "ok");
    }
    check(field<bool>(host.projection(), "powered"),
          "The full-size wheel powers a legal ground collector without its raised lift.");
    outcome(host.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 5), true, "actor_published");
    for (I batch = 0; batch < 128; ++batch) {
        for (int tick = 0; tick < 32; ++tick) (void)host.advance();
        const auto before = host.projection();
        check(field<I>(child(before, "stock"), "source") == 4096 - (batch + 1) * 32 &&
              field<I>(child(before, "stock"), "collector") == 32,
              "The legal ground route extracts each finite 32-unit batch exactly once.");
        const char* actor = batch % 2 == 0 ? "P" : "Q";
        outcome(host.command(actor, targeted("recover", "batch-" + std::to_string(batch), collector, actor)),
                true, "ok");
        const auto view = host.projection();
        const auto cargo = child(view, "cargo");
        check(field<I>(child(cargo, "P"), "raw") == ((batch + 2) / 2) * 32 &&
              field<I>(child(cargo, "Q"), "raw") == ((batch + 1) / 2) * 32 &&
              field<I>(child(view, "stock"), "collector") == 0,
              "Alternating actors own the recovered raw batches without duplication.");
        for (const auto* slot : {"belt", "input", "held", "output", "player"})
            check(field<I>(child(view, "stock"), slot) == 0,
                  "The unbelted ground route invents no other material holder or product.");
        for (const auto* owner : {"P", "Q"})
            check(field<I>(child(cargo, owner), "products") == 0 &&
                  field<A>(child(cargo, owner), "work_lots").empty(),
                  "Recovered mineral remains raw and carries no invented work.");
    }
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)) && field<I>(host.projection(), "order") == 138,
          "Ten physical construction requests and 128 recoveries fit native history bounds.");
    retain_checkpoint(saved, site);
    Host fresh; initialize(fresh, site);
    outcome(fresh.restore_checkpoint(saved), true, "restored");
    check(same(child(saved, "world"), child(fresh.checkpoint(), "world")),
          "Fresh native restoration preserves depleted stock and complete receipt history.");
    const auto restored = material_state(fresh);
    for (I batch = 0; batch < 2; ++batch) {
        const char* actor = batch == 0 ? "P" : "Q";
        const auto duplicate = fresh.command(actor, targeted("recover", "batch-" + std::to_string(batch), collector, actor));
        check(accepted(duplicate) && field<bool>(duplicate, "duplicate") &&
              same(restored, material_state(fresh)),
              "Accepted recovery receipts replay without another admission or raw unit.");
    }
    outcome(fresh.publish_actor("P", {V(2.0), V(1.0), V(0.0)}, 1), true, "actor_published");
    outcome(fresh.command("P", targeted("remove", "remove", collector)), true, "ok");
    auto rebuilt_wire = place("rebuilt", "collector", 0, 1);
    rebuilt_wire.emplace("axis", V("z"));
    const auto rebuilt = fresh.command("P", rebuilt_wire);
    outcome(rebuilt, true, "ok");
    check(field<std::string>(rebuilt, "entity") != collector && field<bool>(fresh.projection(), "powered"),
          "A rebuilt ground collector has a new identity and keeps the physical wheel drive.");
    for (int tick = 0; tick < 40; ++tick) (void)fresh.advance();
    const auto final = fresh.projection();
    check(field<I>(child(final, "stock"), "source") == 0 &&
          field<I>(child(final, "stock"), "collector") == 0 &&
          field<I>(child(child(final, "cargo"), "P"), "raw") == 2048 &&
          field<I>(child(child(final, "cargo"), "Q"), "raw") == 2048 &&
          accepted(fresh.validate_checkpoint(fresh.checkpoint())),
          "The depleted source cannot refill a rebuilt powered collector or move either actor's cargo.");
}

}  // namespace

int main() {
    try {
        footprint_and_profile(); grounded_intake_clearance(); raised_source_lift_clearance();
        foundations_and_restore(); full_finite_depletion();
        std::cout << checks << " native mineral placement, depletion and checkpoint checks passed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
