#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <stdexcept>

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

O cut(const char* client, const char* request, const char* target) {
    return {{"context", V("harvest-site")}, {"client", V(client)}, {"request", V(request)},
        {"action", V("harvest_source")}, {"target", V(target)}};
}

void shared_harvest() {
    Host host;
    check(get<bool>(host.initialize_arrival("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted"),
          "The trusted arrival site initializes one native source roster.");
    const auto initial = host.projection();
    const auto sources = get<O>(initial, "hand_sources");
    check(sources.size() == 4 && get<I>(sources.at("tree-east-south"), "remaining") == 8 &&
          get<I>(sources.at("opening-softmetal"), "remaining") == 16,
          "Three finite trees and one shared ore reserve are visible to both actors.");
    check(get<bool>(host.publish_actor("P", {V(1.65), V(1.0), V(6.6)}, 1), "accepted") &&
          get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(8.25)}, 1), "accepted"),
          "Physical actors become ready on the same deployed deck.");
    const auto p_cut = cut("P", "tree-first", "tree-east-south");
    check(get<bool>(host.command("P", p_cut), "accepted") &&
          get<I>(get<O>(host.projection(), "hand_sources").at("tree-east-south"), "remaining") == 7 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "timber") == 1,
          "The first tool action moves exactly one timber into P's native cargo.");
    const auto after_first = host.checkpoint();
    check(get<bool>(host.command("P", p_cut), "duplicate") &&
          !factory::values::typed_difference(after_first, host.checkpoint()),
          "Repeating the exact wire request cannot debit the tree twice.");
    const auto far = host.command("Q", cut("Q", "far-tree", "tree-east-south"));
    check(!get<bool>(far, "accepted") && get<std::string>(far, "reason") == "out_of_reach" &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "timber") == 0,
          "A second actor cannot cut a tree outside physical reach.");
    check(get<bool>(host.publish_actor("Q", {V(1.65), V(1.0), V(1.65)}, 2), "accepted"),
          "Q can reach the ore side of the site with a new physical observation.");
    check(get<bool>(host.command("Q", cut("Q", "ore-first", "opening-softmetal")), "accepted") &&
          get<I>(get<O>(host.projection(), "hand_sources").at("opening-softmetal"), "remaining") == 15 &&
          get<I>(get<O>(host.projection(), "cargo").at("Q"), "raw") == 1,
          "Manual ore mining debits the same source that feeds a future collector.");
    const auto saved = host.checkpoint();
    check(get<bool>(host.validate_checkpoint(saved), "accepted"),
          "The real Host checkpoint validates tree and ore custody.");
    Host restored;
    check(get<bool>(restored.initialize_arrival("harvest-site", {"P", "Q"}), "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
          "A fresh Host restores both actors and all finite source balances.");
}
}  // namespace

int main() {
    try {
        shared_harvest();
        std::cout << "harvest_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "harvest_host_test: " << error.what() << '\n';
        return 1;
    }
}
