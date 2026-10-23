#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <array>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using Host = factory::godot_world::Host;
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& get(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}

O request(const std::string& id, const char* action) {
    return {{"context", V("broad-site")}, {"client", V("P")},
        {"request", V(id)}, {"action", V(action)}};
}

V accepted(Host& host, const O& wire) {
    const auto reply = host.command("P", wire);
    if (!get<bool>(reply, "accepted"))
        throw std::runtime_error("Request " + get<std::string>(V(wire), "request") +
            " refused: " + get<std::string>(reply, "reason"));
    ++checks;
    return reply;
}

void pose(Host& host, double x, double z, I epoch) {
    check(get<bool>(host.publish_actor("P", {V(x), V(1.0), V(z)}, epoch), "accepted"),
        "The trusted Host fixture accepts a nearby actor sample.");
}

void harvest(Host& host, const char* target, int count, const char* prefix) {
    for (int index = 0; index < count; ++index) {
        auto wire = request(std::string(prefix) + std::to_string(index), "harvest_source");
        wire.emplace("target", V(target));
        accepted(host, wire);
    }
}

void craft(Host& host, const char* kind, int count) {
    for (int index = 0; index < count; ++index) {
        auto wire = request(std::string("broad-craft-") + kind + std::to_string(index), "craft_component");
        wire.emplace("entity", V("pod-fabrication-hub"));
        wire.emplace("component", V(kind));
        accepted(host, wire);
    }
}

void place(Host& host, const char* kind, I x, I y, I z, int index, I& epoch) {
    pose(host, static_cast<double>(x) * 0.4125, static_cast<double>(z) * 0.4125 + 1.65,
        ++epoch);
    auto wire = request(std::string("broad-place-") + kind + std::to_string(index), "place_component");
    wire.emplace("component", V(kind));
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    accepted(host, wire);
}

void broad_projection() {
    Host host;
    check(get<bool>(host.initialize_arrival("broad-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<A>(host.projection(), "broad_press_assemblies").empty(),
        "The finite arrival starts without a gifted broad press.");
    I epoch = 0;
    pose(host, 0.0, 1.65, ++epoch);
    harvest(host, "opening-softmetal", 16, "broad-ore-");
    pose(host, 1.65, 6.6, ++epoch);
    craft(host, "anvil", 4);
    craft(host, "ram_face", 4);
    pose(host, 3.3, 4.95, ++epoch);
    harvest(host, "tree-east-south", 8, "broad-wood-south-");
    pose(host, 3.3, 11.55, ++epoch);
    harvest(host, "tree-east-north", 8, "broad-wood-north-");
    pose(host, 1.65, 6.6, ++epoch);
    craft(host, "sliding_guide", 4);
    craft(host, "wooden_shaft", 4);
    craft(host, "wooden_cog", 4);

    constexpr I origin_x = 12;
    for (int index = 0; index < 4; ++index) {
        const I x = origin_x + (index % 2) * 4;
        const I z = (index / 2) * 4;
        place(host, "anvil", x, 0, z, index, epoch);
    }
    const auto support = get<A>(host.projection(), "broad_press_assemblies");
    check(support.size() == 1 &&
          get<std::string>(support.front(), "geometry_status") == "missing_ram",
        "Four separate anvils expose one incomplete 2x2 candidate.");
    for (int index = 0; index < 4; ++index) {
        const I x = origin_x + (index % 2) * 4;
        const I z = (index / 2) * 4;
        place(host, "ram_face", x, 1, z, index, epoch);
        place(host, "sliding_guide", x, 3, z, index, epoch);
    }
    for (int index = 0; index < 4; ++index) {
        const I x = origin_x + (index % 2) * 4;
        const I z = (index / 2) * 4;
        const I outward = index % 2 == 0 ? -1 : 1;
        place(host, "wooden_shaft", x + outward, 4, z, index, epoch);
        place(host, "wooden_cog", x + outward * 2, 4, z, index, epoch);
    }
    const auto state = host.projection();
    const auto broad = get<A>(state, "broad_press_assemblies");
    check(broad.size() == 1 && get<std::string>(broad.front(), "geometry_status") == "ready" &&
          get<std::string>(broad.front(), "status") == "unpowered" &&
          get<A>(broad.front(), "work_centers").size() == 4 &&
          get<A>(V(get<O>(broad.front(), "parts")), "shafts").size() == 4,
        "Host projects one real four-pad area but refuses readiness without four live drives.");
    check(get<I>(V(get<O>(state, "material_mass")), "accounted_mass") == 64 &&
          get<I>(V(get<O>(state, "cargo").at("P")), "raw") == 0,
        "Constructing the broad area keeps every finite copper unit in custody.");
    auto stage = request("broad-no-sheet-stage", "place_sheet");
    stage.emplace("center", V(A{V(I{12}), V(I{0}), V(I{0})}));
    stage.emplace("sheet_id", V(I{1}));
    pose(host, 4.95, 0.0, ++epoch);
    const auto stage_refusal = host.command("P", stage);
    check(!get<bool>(stage_refusal, "accepted") &&
          get<std::string>(stage_refusal, "reason") == "unavailable_input" &&
          get<A>(host.projection(), "dropped_material").empty(),
        "Host accepts the staging wire but cannot invent a sheet absent from finite arrival cargo.");
    auto feed = request("broad-no-stock-feed", "feed_broad_press");
    feed.emplace("entity", get<A>(V(get<O>(broad.front(), "parts")), "anvils").front());
    pose(host, 4.95, 0.0, ++epoch);
    const auto refused = host.command("P", feed);
    if (get<std::string>(refused, "reason") != "unavailable_input")
        throw std::runtime_error("Broad feed refusal: " + get<std::string>(refused, "reason"));
    check(!get<bool>(refused, "accepted") &&
          get<std::string>(refused, "reason") == "unavailable_input" &&
          get<I>(V(get<O>(host.projection(), "cargo").at("P")), "raw") == 0,
        "Host admits the real broad-feed wire but cannot gift three absent stock chunks.");
    const auto saved = host.checkpoint();
    Host fresh;
    check(get<bool>(fresh.initialize_arrival("broad-site", {"P", "Q"}), "accepted") &&
          get<bool>(fresh.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(fresh.restore_checkpoint(saved), "accepted") &&
          get<std::string>(get<A>(fresh.projection(), "broad_press_assemblies").front(),
              "status") == "unpowered",
        "Fresh Host restore keeps all four placed identities and the unpowered refusal.");
}
}  // namespace

int main() {
    try {
        broad_projection();
        std::cout << "broad_press_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "broad_press_host_test: " << error.what() << '\n';
        return 1;
    }
}
