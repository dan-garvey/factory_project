#include "factory/opening_engineering.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
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

void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}

bool accepted(const V& value) { return field<bool>(value, "accepted"); }
bool same(const V& first, const V& second) { return !factory::values::typed_difference(first, second); }

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

void live_half_u_boundary() {
    Host host;
    check(e::inspect(host, "P").phase == e::Phase::unavailable,
          "An uninitialized Host has no challenge state.");
    check(accepted(host.initialize("upstream-drive", {"P", "Q"})),
          "The finite native Host initializes for both actors.");
    check(accepted(host.configure_terrain(ground_channel_site())),
          "The test binds an explicit ground stream instead of assuming a game site.");
    check(e::inspect(host, "missing").phase == e::Phase::unavailable &&
          e::inspect(host, "P").phase == e::Phase::first_shift,
          "Unknown actors stay unavailable and the first shift begins without products.");
    check(accepted(host.publish_actor("P", {V(18.5), V(1.0), V(16.5)}, 1)),
          "The synthetic actor observes an off-stream construction area.");
    O off_stream_wheel{{"context", V("upstream-drive")}, {"client", V("P")},
        {"request", V("off-stream-wheel")}, {"action", V("place")},
        {"kind", V("wheel")}, {"cell", V(A{V(I{20}), V(I{20})})},
        {"axis", V("x")}, {"level", V(I{4})}};
    const auto before = host.checkpoint();
    const auto refused = host.command("P", off_stream_wheel);
    const auto world_before = field<O>(V(field<O>(before, "world")), "state");
    const auto world_after = field<O>(V(field<O>(host.checkpoint(), "world")), "state");
    check(!accepted(refused) && field<std::string>(refused, "reason") == "not_at_stream" &&
          same(V(world_before), V(world_after)),
          "An off-stream wheel refuses without changing material or parts: " +
              field<std::string>(refused, "reason"));

    check(accepted(host.publish_actor("P", {V(-3.3), V(1.0), V(3.3)}, 2)),
          "The actor reaches the legal ground wheel area.");
    auto ground_wheel = off_stream_wheel;
    ground_wheel.at("request") = V("ground-wheel");
    ground_wheel.at("cell") = V(A{V(I{-6}), V(I{2})});
    ground_wheel.at("axis") = V("z");
    ground_wheel.at("level") = V(I{0});
    ground_wheel.emplace("tiles", V(I{3}));
    check(accepted(host.command("P", ground_wheel)),
          "The unchanged-size waterwheel occupies a legal ground stream cell.");
    const auto progress = e::inspect(host, "P");
    check(progress.phase == e::Phase::first_shift && progress.products == 0 &&
          !progress.belt_forward && !progress.source_at_target,
          "A legal wheel alone cannot claim a completed collector-to-press challenge route.");
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "The finite route checkpoint validates.");
    Host restored;
    check(accepted(restored.initialize("upstream-drive", {"P", "Q"})) &&
          accepted(restored.configure_terrain(ground_channel_site())) &&
          accepted(restored.restore_checkpoint(saved)),
          "A fresh Host restores the real ground wheel without a compatibility adapter.");
    check(same(saved, restored.checkpoint()) &&
          e::inspect(restored, "P").phase == progress.phase &&
          e::inspect(restored, "Q").phase == e::Phase::first_shift,
          "Restore preserves the exact finite state and per-actor progress.");
    const auto read_only = restored.checkpoint();
    (void)e::inspect(restored, "P");
    check(same(read_only, restored.checkpoint()),
          "Challenge inspection never mutates the native World.");
}

// This is an inspector-only projection fixture. The physically occupied
// collector outlet is not claimed as a placeable Host route until its redesign.
V route_projection(const V& native_projection, I products) {
    auto report = std::get<O>(native_projection.storage());
    auto inventories = field<O>(native_projection, "inventories");
    inventories.at("P") = V(products);
    report.at("inventories") = V(std::move(inventories));
    report.at("entities") = V(O{
        {"wheel", V(O{{"kind", V("wheel")}, {"cell", V(A{V(I{-2}), V(I{0})})}})},
        {"collector", V(O{{"kind", V("collector")},
            {"center", V(A{V(I{0}), V(I{0}), V(I{0})})}, {"rotation", V(I{0})}})},
        {"processor", V(O{{"kind", V("processor")},
            {"center", V(A{V(I{12}), V(I{0}), V(I{0})})}, {"rotation", V(I{0})}})}
    });
    report.at("transmission_parts") = V(O{
        {"first", V(O{{"kind", V("shaft")}, {"axis", V(I{2})},
            {"half_span", V(I{2})}, {"center", V(A{V(I{4}), V(I{0}), V(I{0})})}})},
        {"last", V(O{{"kind", V("shaft")}, {"axis", V(I{2})},
            {"half_span", V(I{2})}, {"center", V(A{V(I{8}), V(I{0}), V(I{0})})}})}
    });
    report.at("motion") = V(O{
        {"collector", V(O{{"state", V("rotating")}})},
        {"processor", V(O{{"state", V("rotating")}})},
        {"first", V(O{{"state", V("rotating")},
            {"numerator", V(I{-1})}, {"denominator", V(I{1})}})}
    });
    report.at("belt_spans") = V(O{
        {"span", V(O{{"from", V("first")}, {"to", V("last")}, {"order", V(I{0})}})}
    });
    report.at("dropped_material") = V(A{});
    return V(std::move(report));
}

void inspector_route_decisions() {
    Host host;
    check(accepted(host.initialize("inspector-projection", {"P", "Q"})),
          "The inspector test starts from a native projection with real actor identities.");
    const auto native_projection = host.projection();
    const auto candidate = route_projection(native_projection, 0);
    const auto first = e::inspect(candidate, "P");
    check(first.phase == e::Phase::first_shift && first.source_at_target &&
          first.machines_running && first.belt_forward && first.placed_shafts == 2,
          "The inspector recognizes the geometry and signed forward route before inventory qualifies.");
    const auto four = route_projection(native_projection, 4);
    check(e::inspect(four, "P").phase == e::Phase::deliver_more &&
          e::inspect(four, "Q").phase == e::Phase::first_shift,
          "Four projected products advance only the owning actor's challenge phase.");
    const auto eight = route_projection(native_projection, 8);
    check(e::inspect(eight, "P").phase == e::Phase::ready,
          "The inspector's complete predicate still requires eight products and a forward route.");

    auto no_source = std::get<O>(four.storage());
    auto entities = field<O>(four, "entities");
    auto wheel = std::get<O>(entities.at("wheel").storage());
    wheel.at("cell") = V(A{V(I{-6}), V(I{2})});
    entities.at("wheel") = V(std::move(wheel));
    no_source.at("entities") = V(std::move(entities));
    check(e::inspect(V(no_source), "P").phase == e::Phase::move_source,
          "The target check responds to the actual wheel cell, even with four products.");

    auto disconnected = std::get<O>(eight.storage());
    disconnected.at("belt_spans") = V(O{});
    check(!e::inspect(V(disconnected), "P").belt_forward &&
          e::inspect(V(disconnected), "P").phase == e::Phase::restore_drive,
          "A powered but disconnected machine pair cannot satisfy readiness.");

    auto backwards = std::get<O>(eight.storage());
    auto motion = field<O>(eight, "motion");
    auto shaft = std::get<O>(motion.at("first").storage());
    shaft.at("numerator") = V(I{1});
    motion.at("first") = V(std::move(shaft));
    backwards.at("motion") = V(std::move(motion));
    check(!e::inspect(V(backwards), "P").belt_forward &&
          e::inspect(V(backwards), "P").phase == e::Phase::restore_drive,
          "Opposite shaft rotation cannot claim forward belt transport.");

    auto turned = std::get<O>(eight.storage());
    entities = field<O>(eight, "entities");
    auto collector = std::get<O>(entities.at("collector").storage());
    collector.at("rotation") = V(I{1});
    entities.at("collector") = V(std::move(collector));
    turned.at("entities") = V(std::move(entities));
    check(!e::inspect(V(turned), "P").belt_forward,
          "A belt outside the collector's output port cannot claim forward transport.");
    check(same(native_projection, host.projection()),
          "Inspector-only projection variants never change native stock or construction kits.");
}
}  // namespace

int main() {
    try {
        live_half_u_boundary();
        inspector_route_decisions();
        std::cout << checks << " native opening-engineering boundary and inspector checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
