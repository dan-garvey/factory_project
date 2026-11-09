#include "native/factory-godot-world/tests/site_fixture.hpp"
#include <iostream>
#include <stdexcept>

// The terrain-bound arrival now uses local excavation. Old whole-deposit
// recipes must not reappear as an alternate unlimited-depth harvesting route.
int main() {
    using V=factory::values::Value; using O=V::Object; using A=V::Array;
    try {
        factory::godot_world::Host host;
        const auto accepted=[](const V& v){return std::get<bool>(std::get<O>(v.storage()).at("accepted").storage());};
        if (!accepted(host.initialize_arrival_advanced_fixture("column-site", {"P"})) ||
            !accepted(host.configure_terrain(factory::godot_world::tests::flat_site())) ||
            !accepted(host.publish_actor("P",{V(0.0),V(1.0),V(0.0)},1)))
            throw std::runtime_error("The real arrival site must bind before checking retired collector aliases.");
        const auto before=host.projection(); const auto& view=std::get<O>(before.storage());
        if (!std::get<A>(view.at("collector_assemblies").storage()).empty() ||
            std::get<O>(view.at("hand_sources").storage()).contains("opening-copper"))
            throw std::runtime_error("Column excavation must not advertise a predefined collector recipe or whole-deposit hand target.");
        const auto result=host.command("P", O{{"context",V("column-site")},{"client",V("P")},
            {"request",V("retired-target")},{"action",V("harvest_source")},{"target",V("opening-copper")}});
        if (accepted(result) || factory::values::typed_difference(view.at("stock"),
            std::get<O>(host.projection().storage()).at("stock")))
            throw std::runtime_error("An obsolete source alias cannot debit any ore.");
        if (!accepted(host.validate_checkpoint(host.checkpoint())))
            throw std::runtime_error("The refusal remains a valid conserved checkpoint.");
        std::cout << "COLUMN-COLLECTOR-BOUNDARY-PASS\n";
    } catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
}
