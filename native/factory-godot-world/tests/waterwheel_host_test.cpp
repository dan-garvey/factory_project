#include "native/factory-godot-world/tests/site_fixture.hpp"

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
        const auto dry = host.command("P", place("dry", -1));
        check(!accepted(dry) && field<std::string>(dry, "reason") == "not_at_stream", "dry placement");
        const auto high = host.command("P", place("high", -2, 2));
        check(!accepted(high) && field<std::string>(high, "reason") == "not_at_stream", "above water");
        const auto vertical = host.command("P", place("vertical", -2, 0, "y"));
        check(!accepted(vertical), "vertical axle refusal");
        const auto wheel = host.command("P", place("wet", -2));
        check(accepted(wheel), "immersed placement");
        const auto id = field<std::string>(wheel, "entity");
        auto collector_wire = place("collector", 0);
        collector_wire.at("kind") = V("collector");
        const auto collector = host.command("P", collector_wire);
        check(accepted(collector), "ground collector");
        O gear{{"context", V("water-test")}, {"client", V("P")}, {"request", V("gear")},
            {"action", V("place_gear")}, {"center", V(A{V(I{-4}), V(I{0}), V(I{0})})},
            {"axis", V("x")}, {"teeth", V(I{2})}};
        const auto middle = host.command("P", gear);
        check(accepted(middle), "intermediate coaxial cog");
        const auto middle_id = field<std::string>(middle, "entity");
        const auto collector_id = field<std::string>(collector, "entity");
        O link{{"context", V("water-test")}, {"client", V("P")}, {"request", V("shaft-a")},
            {"action", V("connect_drive")}, {"from", V(id)}, {"to", V(middle_id)}};
        check(field<std::string>(host.command("P", link), "reason") == "axles_already_touch", "wheel touches cog");
        link.at("request") = V("shaft-b"); link.at("from") = V(middle_id); link.at("to") = V(collector_id);
        check(field<std::string>(host.command("P", link), "reason") == "axles_already_touch", "cog touches collector");
        O power{{"context", V("water-test")}, {"client", V("P")}, {"request", V("power")},
            {"action", V("set_power")}, {"active", V(true)}};
        check(accepted(host.command("P", power)), "enable wheel drive");
        const auto motion = V(field<O>(host.projection(), "motion").at(id));
        check(field<I>(motion, "numerator") == -1 && field<I>(motion, "denominator") == 1, "signed local rate");
        const auto collector_motion = V(field<O>(host.projection(), "motion").at(collector_id));
        check(field<I>(collector_motion, "numerator") == -1 && field<I>(collector_motion, "denominator") == 1,
              "the connected collector receives the water rate");
        const auto saved = host.checkpoint();
        Host fresh;
        check(accepted(fresh.initialize("fresh", {"P"})) && accepted(fresh.configure_terrain(site(200))), "fresh site");
        check(accepted(fresh.restore_checkpoint(saved)), "same site restore");
        Host different;
        check(accepted(different.initialize("different", {"P"})) && accepted(different.configure_terrain(site(-200))), "reversed site");
        check(!accepted(different.restore_checkpoint(saved)), "changed flow rejects checkpoint");
        auto raised_site = site(200);
        raised_site.at("heights") = V(A(16, V(-0.02)));
        Host raised;
        check(accepted(raised.initialize("water-test", {"P"})) && accepted(raised.configure_terrain(raised_site)) &&
              accepted(raised.publish_actor("P", {V(-1.65), V(1.0), V(1.65)}, 1)), "raised terrain site");
        const auto blocked = raised.command("P", place("blocked", -2));
        check(!accepted(blocked) && field<std::string>(blocked, "reason") == "site_occupied",
              "water cannot authorize a wheel intersecting the actual terrain");
        Host raised_restore;
        check(accepted(raised_restore.initialize("fresh", {"P"})) &&
              accepted(raised_restore.configure_terrain(raised_site)) &&
              !accepted(raised_restore.restore_checkpoint(saved)), "checkpoint import repeats terrain clearance");
        Host large;
        check(accepted(large.initialize("water-test", {"P"})) && accepted(large.configure_terrain(site(200))) &&
              accepted(large.publish_actor("P", {V(-1.65), V(1.0), V(1.65)}, 1)), "large wheel site");
        auto big_wire = place("large", -2, 2);
        big_wire.emplace("tiles", V(I{2}));
        const auto big = large.command("P", big_wire);
        check(accepted(big), "two-square wheel immerses at the shared raised level");
        check(accepted(large.command("P", power)), "enable large wheel");
        const auto big_id = field<std::string>(big, "entity");
        const auto big_motion = V(field<O>(large.projection(), "motion").at(big_id));
        check(field<I>(big_motion, "numerator") == -1 && field<I>(big_motion, "denominator") == 2,
              "double diameter halves angular rate at the same current");
        check(field<I>(V(field<O>(large.projection(), "entities").at(big_id)), "tiles") == 2,
              "confirmed projection carries the wheel size");
        const auto big_saved = large.checkpoint();
        Host large_restore;
        check(accepted(large_restore.initialize("fresh", {"P"})) && accepted(large_restore.configure_terrain(site(200))) &&
              accepted(large_restore.restore_checkpoint(big_saved)), "wheel dimensions survive checkpoint restore");
        std::cout << "waterwheel host controls passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
