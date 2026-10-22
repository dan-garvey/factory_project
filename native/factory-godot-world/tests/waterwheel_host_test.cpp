#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
template<class T> const T& field(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}
bool accepted(const V& value) { return field<bool>(value, "accepted"); }
O site(I velocity) {
    A axis{V(-128.0), V(-2.8), V(-2.0), V(128.0)};
    A heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    O result{{"axis", V(axis)}, {"heights", V(heights)}, {"obstacles", V(A{})}};
    result.emplace("water", V(A{V(A{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{0}), V(velocity)})}));
    return result;
}
O place(const char* id, I x, I level = 0, const char* axis = "x") {
    return {{"context", V("water-test")}, {"client", V("P")}, {"request", V(id)},
        {"action", V("place")}, {"kind", V("wheel")}, {"cell", V(A{V(x), V(I{0})})},
        {"level", V(level)}, {"axis", V(axis)}};
}
int main() {
    try {
        Host dry_profile;
        check(accepted(dry_profile.initialize("water-test", {"P"})) &&
              accepted(dry_profile.configure_terrain(factory::godot_world::tests::flat_site())) &&
              accepted(dry_profile.publish_actor("P", {V(0.0), V(1.0), V(1.65)}, 1)), "bind a dry site");
        const auto no_water = dry_profile.command("P", place("no-water", -1));
        check(!accepted(no_water) && field<std::string>(no_water, "reason") == "not_at_stream",
              "the old dry column cannot create a wheel without a water field");
        Host host;
        check(accepted(host.initialize("water-test", {"P"})), "initialize");
        check(accepted(host.configure_terrain(site(200))), "bind trusted flow");
        check(accepted(host.publish_actor("P", {V(-1.65), V(1.0), V(1.65)}, 1)), "actor");
        for (I size : {I{1}, I{2}}) {
            auto undersized = place(size == 1 ? "one" : "two", -2, 4);
            undersized.emplace("tiles", V(size));
            const auto rejected = host.command("P", undersized);
            check(!accepted(rejected) && field<std::string>(rejected, "reason") == "invalid_wheel_size",
                  "wheels below three tiles are refused");
        }
        const auto dry = host.command("P", place("dry", -1));
        check(!accepted(dry) && field<std::string>(dry, "reason") == "not_at_stream", "dry placement");
        const auto high = host.command("P", place("high", -2, 8));
        check(!accepted(high) && field<std::string>(high, "reason") == "not_at_stream", "above water");
        const auto vertical = host.command("P", place("vertical", -2, 0, "y"));
        check(!accepted(vertical), "vertical axle refusal");
        const auto wheel = host.command("P", place("wet", -2, 4));
        check(accepted(wheel), "immersed placement");
        const auto id = field<std::string>(wheel, "entity");
        const auto placed = host.projection();
        const auto wheel_motion = V(field<O>(placed, "motion").at(id));
        check(field<I>(wheel_motion, "numerator") == -25 && field<I>(wheel_motion, "denominator") == 84,
              "an immersed wheel rotates without a drive command");
        const auto& supports = field<A>(field<O>(placed, "entities").at(id), "supports");
        check(supports.size() == 2, "the placed horizontal wheel projects both riverbed support volumes");
        for (const auto& support : supports) {
            const auto& center = field<A>(support, "center");
            const auto& half = field<A>(support, "half");
            const auto foot = std::get<double>(center[1].storage()) - std::get<double>(half[1].storage());
            const auto bearing = std::get<double>(center[1].storage()) + std::get<double>(half[1].storage());
            check(foot < -1.5 && std::abs(bearing - 2.425) < 0.000001,
                  "the fixed support reaches the riverbed and stops under the visual axle");
        }
        O base{{"context", V("water-test")}, {"client", V("P")}, {"request", V("base")},
            {"action", V("place_foundation")}, {"cell", V(A{V(I{0}), V(I{0})})}, {"level", V(I{4})}};
        check(accepted(host.command("P", base)), "raised collector foundation");
        auto collector_wire = place("collector", 0, 4);
        collector_wire.at("kind") = V("collector");
        const auto collector = host.command("P", collector_wire);
        check(accepted(collector), "raised collector");
        O gear{{"context", V("water-test")}, {"client", V("P")}, {"request", V("gear")},
            {"action", V("place_gear")}, {"center", V(A{V(I{-4}), V(I{4}), V(I{0})})},
            {"axis", V("x")}, {"teeth", V(I{2})}};
        const auto middle = host.command("P", gear);
        check(accepted(middle), "intermediate coaxial cog");
        const auto middle_id = field<std::string>(middle, "entity");
        const auto collector_id = field<std::string>(collector, "entity");
        O link{{"context", V("water-test")}, {"client", V("P")}, {"request", V("shaft-a")},
            {"action", V("connect_drive")}, {"from", V(id)}, {"to", V(middle_id)}};
        check(field<std::string>(host.command("P", link), "reason") == "individual_shaft_required", "endpoint shaft creation is refused");
        link.at("request") = V("shaft-b"); link.at("from") = V(middle_id); link.at("to") = V(collector_id);
        check(field<std::string>(host.command("P", link), "reason") == "individual_shaft_required", "endpoint shaft creation is refused at the collector");
        O power{{"context", V("water-test")}, {"client", V("P")}, {"request", V("power")},
            {"action", V("set_power")}, {"active", V(true)}};
        const auto refused = host.command("P", power);
        check(!accepted(refused) && field<std::string>(refused, "reason") == "unsupported_action",
              "manual drive switching is unavailable");
        const auto motion = V(field<O>(host.projection(), "motion").at(id));
        check(field<I>(motion, "numerator") == -25 && field<I>(motion, "denominator") == 84, "signed local rate follows the immersed visible radius");
        const auto collector_motion = V(field<O>(host.projection(), "motion").at(collector_id));
        check(field<I>(collector_motion, "numerator") == -25 && field<I>(collector_motion, "denominator") == 84,
              "the connected collector receives the water rate");
        const auto saved = host.checkpoint();
        Host fresh;
        check(accepted(fresh.initialize("fresh", {"P"})) && accepted(fresh.configure_terrain(site(200))), "fresh site");
        check(accepted(fresh.restore_checkpoint(saved)), "same site restore");
        Host different;
        check(accepted(different.initialize("different", {"P"})) && accepted(different.configure_terrain(site(-200))), "reversed site");
        check(!accepted(different.restore_checkpoint(saved)), "changed flow rejects checkpoint");
        auto raised_site = site(200);
        raised_site.at("heights") = V(A(16, V(0.1)));
        Host raised;
        check(accepted(raised.initialize("water-test", {"P"})) && accepted(raised.configure_terrain(raised_site)) &&
              accepted(raised.publish_actor("P", {V(-1.65), V(1.0), V(1.65)}, 1)), "raised terrain site");
        const auto blocked = raised.command("P", place("blocked", -2, 4));
        check(!accepted(blocked) && field<std::string>(blocked, "reason") == "site_occupied",
              "water cannot authorize a wheel intersecting the actual terrain");
        Host raised_restore;
        check(accepted(raised_restore.initialize("fresh", {"P"})) &&
              accepted(raised_restore.configure_terrain(raised_site)) &&
              !accepted(raised_restore.restore_checkpoint(saved)), "checkpoint import repeats terrain clearance");
        Host large;
        check(accepted(large.initialize("water-test", {"P"})) && accepted(large.configure_terrain(site(200))) &&
              accepted(large.publish_actor("P", {V(-1.65), V(3.0), V(1.65)}, 1)), "large wheel site");
        auto big_wire = place("large", -2, 8);
        big_wire.emplace("tiles", V(I{6}));
        const auto big = large.command("P", big_wire);
        check(accepted(big), "six-square wheel immerses at the shared raised level");
        const auto big_id = field<std::string>(big, "entity");
        const auto big_motion = V(field<O>(large.projection(), "motion").at(big_id));
        check(field<I>(big_motion, "numerator") == -25 && field<I>(big_motion, "denominator") == 168,
              "double diameter halves angular rate at the same current");
        check(field<I>(V(field<O>(large.projection(), "entities").at(big_id)), "tiles") == 6,
              "confirmed projection carries the wheel size");
        const auto big_saved = large.checkpoint();
        Host large_restore;
        check(accepted(large_restore.initialize("fresh", {"P"})) && accepted(large_restore.configure_terrain(site(200))) &&
              accepted(large_restore.restore_checkpoint(big_saved)), "wheel dimensions survive checkpoint restore");
        auto broad = site(200);
        broad.at("heights") = V(A(16, V(-1.65)));
        for (const char* axis : {"x", "z"}) for (I tiles = 3; tiles <= 8; ++tiles) {
            const I levels[] = {4, 4, 8, 8, 12, 12};
            const auto level = levels[tiles - 3];
            Host sized;
            check(accepted(sized.initialize("water-test", {"P"})) &&
                  accepted(sized.configure_terrain(broad)) &&
                  accepted(sized.publish_actor("P", {V(-1.65), V(level * 0.4125 + 0.825), V(1.65)}, 1)),
                  "bind a riverbed and actor for every horizontal wheel size");
            auto sized_wire = place("sized", -2, level, axis);
            sized_wire.emplace("tiles", V(tiles));
            const auto placed_sized = sized.command("P", sized_wire);
            if (!accepted(placed_sized)) std::cerr << "sized wheel axis=" << axis << " tiles=" << tiles
                                                   << " reason=" << field<std::string>(placed_sized, "reason") << '\n';
            check(accepted(placed_sized), "both horizontal axes place every supported wheel size over the broad riverbed");
            const auto& sized_supports = field<A>(field<O>(sized.projection(), "entities").at(
                field<std::string>(placed_sized, "entity")), "supports");
            check(sized_supports.size() == 2, "each accepted size projects exactly two fixed pier envelopes");
            for (const auto& support : sized_supports) {
                const auto& center = field<A>(support, "center");
                const auto& half = field<A>(support, "half");
                const auto foot = std::get<double>(center[1].storage()) - std::get<double>(half[1].storage());
                const auto bearing = std::get<double>(center[1].storage()) + std::get<double>(half[1].storage());
                check(std::abs(foot + 1.69) < 0.000001 &&
                      std::abs(bearing - (level * 0.4125 + 0.825 - 0.05)) < 0.000001,
                      "every support seats into the same emitted riverbed and aligns below its axle");
            }
            const auto sized_saved = sized.checkpoint();
            Host sized_fresh;
            check(accepted(sized_fresh.initialize("fresh", {"P"})) &&
                  accepted(sized_fresh.configure_terrain(broad)) &&
                  accepted(sized_fresh.restore_checkpoint(sized_saved)) &&
                  !factory::values::typed_difference(sized_saved, sized_fresh.checkpoint()),
                  "each horizontal size survives a fresh Host rebuild without changing its typed checkpoint");
        }
        Host support_case;
        check(accepted(support_case.initialize("water-test", {"P"})) &&
              accepted(support_case.configure_terrain(site(200))) &&
              accepted(support_case.publish_actor("P", {V(-2.65), V(1.0), V(0.0)}, 1)),
              "the support-only collision case binds its actor beside the rotor box");
        const auto blocked_by_support = support_case.command("P", place("support-actor", -2, 4));
        check(!accepted(blocked_by_support) && field<std::string>(blocked_by_support, "reason") == "actor_occupied",
              "a person standing outside the rotor but inside a fixed bearing pier blocks construction");
        check(accepted(support_case.publish_actor("P", {V(-1.65), V(1.0), V(1.65)}, 2)),
              "moving the actor away creates a newer native observation");
        check(accepted(support_case.command("P", place("supported", -2, 4))),
              "the same wheel is buildable after the bearing pier clears");
        O low_foundation{{"context", V("water-test")}, {"client", V("P")}, {"request", V("under-pier")},
            {"action", V("place_foundation")}, {"cell", V(A{V(I{-2}), V(I{0})})}, {"level", V(I{-2})}};
        const auto buried = support_case.command("P", low_foundation);
        check(!accepted(buried) && field<std::string>(buried, "reason") == "occupied",
              "a low foundation cannot pass through the pier below the rotating rim");
        auto obstructed_site = site(200);
        obstructed_site.at("obstacles") = V(A{V(A{V(A{V(-2.94), V(-0.2), V(-0.1)}),
            V(A{V(-2.76), V(2.0), V(0.1)})})});
        Host obstructed;
        check(accepted(obstructed.initialize("water-test", {"P"})) &&
              accepted(obstructed.configure_terrain(obstructed_site)) &&
              accepted(obstructed.publish_actor("P", {V(-1.65), V(1.0), V(1.65)}, 1)),
              "bind one narrow solid beside the rotor but inside the support footprint");
        const auto blocked_pier = obstructed.command("P", place("blocked-pier", -2, 4));
        check(!accepted(blocked_pier) && field<std::string>(blocked_pier, "reason") == "site_occupied",
              "trusted terrain obstacles refuse a fixed pier even when the rotating disc itself clears them");
        std::cout << "waterwheel host controls passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
