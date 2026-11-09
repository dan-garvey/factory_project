#include "factory/godot_world.hpp"
#include "site_fixture.hpp"

#include <iostream>
#include <stdexcept>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};
template<class T> T get(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}
void check(bool okay, const char* why) {
    ++checks;
    if (!okay) throw std::runtime_error(why);
}
struct Fixture {
    Host host;
    I request{}, epoch{};
    Fixture() {
        check(get<bool>(host.initialize_arrival_advanced_fixture("surface-drill", {"P"}), "accepted"), "Initialize arrival.");
        check(get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"), "Bind real finite columns.");
    }
    void move(double x, double y, double z) {
        check(get<bool>(host.publish_actor("P", {V(x), V(y), V(z)}, ++epoch), "accepted"), "Publish observed actor.");
    }
    V command(const char* action, O args = {}) {
        args.emplace("context", V("surface-drill")); args.emplace("client", V("P"));
        args.emplace("request", V(std::to_string(++request))); args.emplace("action", V(action));
        return host.command("P", args);
    }
    V accepted(const char* action, O args = {}) {
        auto result = command(action, args);
        if (!get<bool>(result, "accepted"))
            throw std::runtime_error(std::string(action) + ": " + get<std::string>(result, "reason"));
        ++checks; return result;
    }
    void stock() {
        move(6.6, 1, 3.3);
        accepted("set_developer_conveniences", {{"enabled", V(true)}});
        for (int n=0; n<8; ++n) accepted("harvest_source", {{"target", V("tree-east-south")}});
        move(6.6, 1, 11.55);
        for (int n=0; n<4; ++n) accepted("harvest_source", {{"target", V("tree-east-north")}});
        move(-1.2375, 1, 0);
        for (int n=0; n<5; ++n)
            accepted("harvest_source", {{"target", V(factory::godot_world::tests::reachable_ore(host,"P"))}});
        move(3.3, 1, 4.8);
        for (const auto kind : {"stationary_mount", "drill_head", "hand_crank"})
            accepted("craft_component", {{"entity", V("pod-fabrication-hub")}, {"component", V(kind)}});
        accepted("craft_part", {{"entity", V("pod-fabrication-hub")}, {"role", V("vertical_gearbox")},
            {"half_span", V(I{0})}});
        accepted("set_developer_conveniences", {{"enabled", V(false)}});
    }
};
}
int main() {
    try {
        Fixture f;
        f.stock();
        f.move(6.6, 1, -4.95);
        const A mount{V(I{24}), V(I{0}), V(I{-24})};
        const A head{V(I{24}), V(I{1}), V(I{-24})};
        check(!get<bool>(f.command("place_component", {{"component", V("drill_head")}, {"center", V(head)}}), "accepted"),
            "A shaft or empty air cannot support a reusable tool head.");
        const auto support=f.accepted("place_component", {{"component", V("stationary_mount")}, {"center", V(mount)}});
        const auto tool=f.accepted("place_component", {{"component", V("drill_head")}, {"center", V(head)}});
        f.accepted("place_relay", {{"kind", V("vertical_gearbox")},
            {"center", V(A{V(I{24}), V(I{5}), V(I{-24})})}, {"axis", V("z")}});
        const auto components=get<O>(f.host.projection(), "placed_components");
        const auto ports=get<O>(f.host.projection(), "rotary_ports");
        const auto tool_id=get<std::string>(tool,"entity");
        for (const auto& value : get<A>(ports.at(tool_id), "ports"))
            check(!get<bool>(value,"hand_crank"), "A vertical drill port refuses a direct hand crank.");
        const auto transmission=get<O>(f.host.projection(), "transmission_parts");
        const auto gearbox=transmission.begin()->first;
        const auto cranks=get<O>(f.host.projection(), "crank_items");
        const auto crank=cranks.begin()->first;
        check(!get<bool>(f.command("attach_hand_crank", {{"entity",V(tool_id)}, {"crank",V(crank)},
            {"port",V(A{V(I{24}),V(I{3}),V(I{-24})})},
            {"face",V(A{V(I{0}),V(I{1}),V(I{0})})}}), "accepted"),
            "The real attach command refuses a vertical hand crank.");
        check(!get<bool>(f.command("reclaim_component", {{"entity",V(get<std::string>(support,"entity"))}}), "accepted"),
            "The mounted head prevents removal of its only structural support.");
        f.accepted("attach_hand_crank", {{"entity",V(gearbox)}, {"crank",V(crank)},
            {"port",V(A{V(I{26}),V(I{5}),V(I{-24})})}, {"face",V(A{V(I{1}),V(I{0}),V(I{0})})}});
        const auto before=get<I>(V(get<O>(f.host.projection(), "stock")),"source");
        check(std::get<O>(f.host.advance().storage()).contains("revision"), "Idle native tick completes.");
        check(get<I>(V(get<O>(f.host.projection(),"stock")),"source")==before,
            "An attached idle crank does not mine automatically.");
        for (int tick=0; tick<64; ++tick) {
            f.accepted("operate_hand_crank", {{"entity",V(crank)}});
            check(std::get<O>(f.host.advance().storage()).contains("revision"), "Crank tick settles without a second source.");
            if (tick==2) {
                check(get<I>(V(get<O>(f.host.projection(),"stock")),"source")==before,
                    "Three work ticks retain progress without issuing ore early.");
                const auto partial=f.host.checkpoint();
                check(get<bool>(f.host.validate_checkpoint(partial),"accepted"),
                    "A partly cranked local cut validates before any payout.");
                Host rejoined;
                check(get<bool>(rejoined.initialize_arrival_advanced_fixture("surface-drill", {"P"}),"accepted") &&
                    get<bool>(rejoined.configure_terrain(factory::godot_world::tests::flat_site()),"accepted") &&
                    get<bool>(rejoined.restore_checkpoint(partial),"accepted") &&
                    !factory::values::typed_difference(partial,rejoined.checkpoint()),
                    "Fresh Host restore preserves exact partial cut work and assembly custody.");
            }
        }
        const auto after=f.host.projection();
        const auto remaining=get<I>(V(get<O>(after,"stock")),"source");
        check(remaining < before, "Real horizontal crank power excavates local finite ore.");
        I loose=0;
        for (const auto& drop : get<A>(after,"dropped_material")) loose+=get<I>(drop,"raw");
        check(loose==before-remaining, "Every excavated unit appears in canonical loose ground custody.");
        check(get<bool>(f.host.validate_checkpoint(f.host.checkpoint()),"accepted"), "Partial work, field and material restore together.");
        for (int tick=0;tick<20;++tick) {
            f.accepted("operate_hand_crank", {{"entity",V(crank)}});
            check(std::get<O>(f.host.advance().storage()).contains("revision"), "Out-of-contact native tick completes.");
        }
        check(get<I>(V(get<O>(f.host.projection(),"stock")),"source")==remaining,
            "A fixed head stops cutting when its local floor drops beyond tooth reach.");
        const auto carried=get<I>(get<O>(after,"cargo").at("P"),"raw");
        for (const auto& drop:get<A>(after,"dropped_material")) {
            auto expected=std::get<O>(drop.storage());
            const auto point=expected.at("center");
            expected.erase("center");expected.erase("ground_position");
            f.accepted("pickup_material", {{"center",point},{"expected",V(expected)}});
            check(!get<bool>(f.command("pickup_material", {{"center",point},{"expected",V(expected)}}),"accepted"),
                "A second pickup cannot duplicate the loose copper.");
        }
        check(get<A>(f.host.projection(),"dropped_material").empty() &&
            get<I>(get<O>(f.host.projection(),"cargo").at("P"),"raw")==carried+loose &&
            get<bool>(f.host.validate_checkpoint(f.host.checkpoint()),"accepted"),
            "Reachable pickup transfers exact ground custody to the actor and remains saveable.");
        std::cout << "SURFACE-DRILL-HOST-PASS " << checks << " checks; " << loose << " loose copper\n";
    } catch (const std::exception& e) { std::cerr << "After " << checks << ": " << e.what() << '\n'; return 1; }
}
