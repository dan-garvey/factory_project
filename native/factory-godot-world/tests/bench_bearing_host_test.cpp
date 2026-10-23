#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

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

template<class T> const T& get(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}

void bench_requires_ground_bearing() {
    Host host;
    auto low_site = factory::godot_world::tests::flat_site();
    low_site["axis"] = V(A{V(-128.0), V(7.0), V(8.0), V(128.0)});
    A heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
    }
    low_site["heights"] = V(heights);
    check(get<bool>(host.initialize_arrival("low-bench-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(low_site), "accepted") &&
          get<bool>(host.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 1), "accepted"),
          "A local low pocket initializes beside an otherwise level pod and finite stock.");
    for (int index = 0; index < 4; ++index) {
        const O cut_wood{{"context", V("low-bench-site")}, {"client", V("P")},
            {"request", V("low-bench-timber-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(host.command("P", cut_wood), "accepted"),
              "P harvests finite timber for the lower-site bearing control.");
    }
    const O shape_bench{{"context", V("low-bench-site")}, {"client", V("P")},
        {"request", V("low-shape-bench")}, {"action", V("field_craft")},
        {"component", V("wooden_workbench")}};
    check(get<bool>(host.command("P", shape_bench), "accepted"),
          "P shapes the same bench component before attempting unsupported placement.");
    const O place_bench{{"context", V("low-bench-site")}, {"client", V("P")},
        {"request", V("low-place-bench")}, {"action", V("place_component")},
        {"component", V("wooden_workbench")},
        {"center", V(A{V(I{20}), V(I{0}), V(I{8})})}};
    const auto outcome = host.command("P", place_bench);
    if (get<bool>(outcome, "accepted"))
        throw std::runtime_error("Ground-level bench floated 1.65 metres above the actual terrain.");
    check(get<std::string>(outcome, "reason") == "support_required" &&
          get<I>(V(get<O>(get<O>(host.projection(), "cargo").at("P"), "components")),
              "wooden_workbench") == 1,
          "A bench needs natural ground or an ordinary foundation under its feet.");
    const O foundation{{"context", V("low-bench-site")}, {"client", V("P")},
        {"request", V("low-bench-foundation")}, {"action", V("place_foundation")},
        {"cell", V(A{V(I{5}), V(I{2})})}, {"level", V(I{4})}};
    check(get<bool>(host.command("P", foundation), "accepted"),
          "P builds one ordinary foundation above the low ground.");
    auto raised_bench = place_bench;
    raised_bench.at("request") = V("raised-bench");
    raised_bench.at("center") = V(A{V(I{20}), V(I{4}), V(I{8})});
    check(get<bool>(host.command("P", raised_bench), "accepted") &&
          get<bool>(host.validate_checkpoint(host.checkpoint()), "accepted"),
          "The same finite bench sits on an aligned elevated foundation and saves.");
    check(get<bool>(host.publish_actor("P", {V(3.3), V(1.0), V(6.6)}, 2), "accepted"),
          "P moves back within reach of the issued pod workshop.");
    const O stow{{"context", V("low-bench-site")}, {"client", V("P")},
        {"request", V("low-stow-pod")}, {"action", V("stow_fabrication_hub")},
        {"entity", V("pod-fabrication-hub")}};
    check(get<bool>(host.command("P", stow), "accepted"),
          "The issued workshop enters P custody before a redeploy attempt.");
    check(get<bool>(host.publish_actor("P", {V(8.25), V(1.0), V(3.3)}, 3), "accepted"),
          "P reaches the lowered candidate workshop site.");
    const O deploy{{"context", V("low-bench-site")}, {"client", V("P")},
        {"request", V("low-deploy-pod")}, {"action", V("deploy_fabrication_hub")},
        {"entity", V("pod-fabrication-hub")},
        {"center", V(A{V(I{24}), V(I{0}), V(I{8})})}};
    const auto refused_deploy = host.command("P", deploy);
    check(!get<bool>(refused_deploy, "accepted") &&
          get<std::string>(refused_deploy, "reason") == "support_required" &&
          get<std::string>(V(get<O>(host.projection(), "fabrication_hub")), "holder") == "P",
          "An unsupported redeploy leaves the unique pod workshop in P custody.");

    Host flat;
    check(get<bool>(flat.initialize_arrival("low-bench-site", {"P", "Q"}), "accepted") &&
          get<bool>(flat.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(flat.publish_actor("P", {V(6.6), V(1.0), V(3.3)}, 1), "accepted"),
          "The comparison Host binds the same arrival to level ground.");
    for (int index = 0; index < 4; ++index) {
        const O cut_wood{{"context", V("low-bench-site")}, {"client", V("P")},
            {"request", V("flat-bench-timber-" + std::to_string(index))},
            {"action", V("harvest_source")}, {"target", V("tree-east-south")}};
        check(get<bool>(flat.command("P", cut_wood), "accepted"),
              "P harvests the finite timber for the exact restore control.");
    }
    auto flat_shape = shape_bench;
    flat_shape.at("request") = V("flat-shape-bench");
    auto flat_place = place_bench;
    flat_place.at("request") = V("flat-place-bench");
    check(get<bool>(flat.command("P", flat_shape), "accepted") &&
          get<bool>(flat.command("P", flat_place), "accepted"),
          "The same wooden bench is valid on level natural ground.");
    const auto saved = flat.checkpoint();
    Host changed_site;
    check(get<bool>(changed_site.initialize_arrival("low-bench-site", {"P", "Q"}), "accepted") &&
          get<bool>(changed_site.configure_terrain(low_site), "accepted"),
          "A fresh Host binds the local low pocket before importing the saved bench.");
    const auto before = changed_site.checkpoint();
    const auto validation = changed_site.validate_checkpoint(saved);
    const auto restoration = changed_site.restore_checkpoint(saved);
    check(!get<bool>(validation, "accepted") &&
          get<std::string>(validation, "reason") == "support_required" &&
          !get<bool>(restoration, "accepted") &&
          get<std::string>(restoration, "reason") == "support_required" &&
          !factory::values::typed_difference(before, changed_site.checkpoint()),
          "Import refuses a bench whose saved feet lost actual terrain support without mutating state.");
}
}  // namespace

int main() {
    try {
        bench_requires_ground_bearing();
        std::cout << "bench_bearing_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "bench_bearing_host_test: " << error.what() << '\n';
        return 1;
    }
}
