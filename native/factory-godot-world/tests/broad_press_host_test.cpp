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
    const auto reply = get<std::string>(V(wire), "action") == "harvest_source" ?
        factory::godot_world::tests::complete_manual_cut(host, "P", wire) : host.command("P", wire);
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
    const bool broad_channel = std::string(kind).starts_with("channel_broad_");
    pose(host, static_cast<double>(x) * 0.4125 - (broad_channel ? 1.65 : 0.0),
        static_cast<double>(z) * 0.4125 + 1.65, ++epoch);
    auto wire = request(std::string("broad-place-") + kind + std::to_string(index), "place_component");
    wire.emplace("component", V(kind));
    wire.emplace("center", V(A{V(x), V(y), V(z)}));
    accepted(host, wire);
}

void broad_projection() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("broad-site", {"P", "Q"}), "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<A>(host.projection(), "broad_press_assemblies").empty(),
        "The finite arrival starts without a gifted broad press.");
    I epoch = 0;
    pose(host, -0.5, 0.0, ++epoch);
    harvest(host, "opening-copper", 16, "broad-ore-");
    pose(host, 1.65, 6.6, ++epoch);
    craft(host, "anvil", 4);
    craft(host, "ram_face", 4);
    pose(host, 5.8, 3.3, ++epoch);
    harvest(host, "tree-east-south", 8, "broad-wood-south-");
    pose(host, 5.8, 11.55, ++epoch);
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
    const auto shear = get<A>(state, "broad_shear_assemblies");
    check(shear.size() == 1 &&
          get<std::string>(shear.front(), "geometry_status") == "missing_blade",
        "The Host distinguishes a forming ram from a sheet-cutting blade.");
    auto cut = request("broad-wrong-head-cut", "stroke_broad_shear");
    cut.emplace("entity", get<A>(V(get<O>(broad.front(), "parts")), "anvils").front());
    cut.emplace("sheet_id", V(I{1}));
    const auto cut_refusal = host.command("P", cut);
    check(!get<bool>(cut_refusal, "accepted") &&
          get<std::string>(cut_refusal, "reason") == "incomplete_shear",
        "A valid Host cutting wire cannot treat four forming rams as blades.");
    check(get<I>(V(get<O>(state, "material_mass")), "accounted_mass") == 4096 * 4 &&
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
    check(get<bool>(fresh.initialize_arrival_advanced_fixture("broad-site", {"P", "Q"}), "accepted") &&
          get<bool>(fresh.configure_terrain(factory::godot_world::tests::flat_site()), "accepted") &&
          get<bool>(fresh.restore_checkpoint(saved), "accepted") &&
          get<std::string>(get<A>(fresh.projection(), "broad_press_assemblies").front(),
              "status") == "unpowered",
        "Fresh Host restore keeps all four placed identities and the unpowered refusal.");
}

void sized_workbed_custody() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("broad-site", {"P"}),
              "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()),
              "accepted"), "The broad-size fixture starts with finite native material.");
    I epoch = 0;
    pose(host, -0.5, 0.0, ++epoch);
    harvest(host, "opening-copper", 31, "size-ore-");
    pose(host, 1.65, 6.6, ++epoch);
    craft(host, "anvil", 4);
    craft(host, "flat_head", 4);
    craft(host, "copper_slide", 4);
    const auto before = host.projection();
    auto no_recipe = request("size-no-recipe", "craft_component");
    no_recipe.emplace("entity", V("pod-fabrication-hub"));
    no_recipe.emplace("component", V("broad_anvil"));
    const auto rejected = host.command("P", no_recipe);
    check(!get<bool>(rejected, "accepted"),
        "The 2x2 workbed has no separate crafting recipe.");
    check(get<std::string>(rejected, "reason") == "unavailable_recipe",
        "The broad workbed craft refusal names its unavailable recipe.");
    check(!factory::values::typed_difference(
              V(get<O>(before, "cargo")), V(get<O>(host.projection(), "cargo"))) &&
          !factory::values::typed_difference(
              V(get<O>(before, "placed_components")),
              V(get<O>(host.projection(), "placed_components"))),
        "The craft refusal leaves finite material and world state intact.");
    pose(host, 3.3, 1.65, ++epoch);
    auto unsupported_housing = request("size-slide-without-bed", "place_component");
    unsupported_housing.emplace("component", V("broad_copper_slide"));
    unsupported_housing.emplace("center", V(A{V(I{12}), V(I{4}), V(I{0})}));
    const auto before_housing = host.projection();
    const auto housing_refusal = host.command("P", unsupported_housing);
    check(!get<bool>(housing_refusal, "accepted") &&
          get<std::string>(housing_refusal, "reason") == "missing_support" &&
          !factory::values::typed_difference(V(get<O>(before_housing, "cargo")),
              V(get<O>(host.projection(), "cargo"))),
        "The four-tile slide housing cannot float without its broad workbed or spend its parts.");
    auto bed = request("size-place-bed", "place_component");
    bed.emplace("component", V("broad_anvil"));
    bed.emplace("center", V(A{V(I{12}), V(I{0}), V(I{0})}));
    const auto installed_bed = accepted(host, bed);
    const auto bed_id = get<std::string>(installed_bed, "entity");
    auto head = request("size-place-head", "place_component");
    head.emplace("component", V("broad_flat_head"));
    head.emplace("center", V(A{V(I{12}), V(I{1}), V(I{0})}));
    const auto installed_head = accepted(host, head);
    const auto head_id = get<std::string>(installed_head, "entity");
    auto slide = request("size-place-slide", "place_component");
    slide.emplace("component", V("broad_copper_slide"));
    slide.emplace("center", V(A{V(I{12}), V(I{4}), V(I{0})}));
    const auto installed_slide = accepted(host, slide);
    const auto slide_id = get<std::string>(installed_slide, "entity");
    const auto placed = get<O>(host.projection(), "placed_components");
    const auto bed_box = get<O>(placed.at(bed_id), "occupied");
    const auto bed_half = get<A>(V(bed_box), "half");
    const auto slide_ports = get<A>(placed.at(slide_id), "input_ports");
    const auto sized = get<A>(host.projection(), "broad_press_assemblies");
    check(placed.size() == 3 && sized.size() == 1 &&
          get<std::string>(sized.front(), "geometry_status") == "ready" &&
          get<std::string>(sized.front(), "status") == "unpowered" &&
          std::get<double>(bed_half[0].storage()) == 1.65 &&
          std::get<double>(bed_half[2].storage()) == 1.65 &&
          slide_ports.size() == 4 &&
          get<O>(get<O>(host.projection(), "cargo").at("P"), "components").empty(),
        "One broad face and one sized head meet a single unpowered slide without extra local shafts.");
    auto feed = request("size-feed", "feed_broad_press");
    feed.emplace("entity", V(bed_id));
    accepted(host, feed);
    const auto fed = get<A>(host.projection(), "dropped_material");
    check(fed.size() == 1 && get<A>(fed.front(), "work_lots").size() == 1 &&
          get<I>(get<O>(host.projection(), "cargo").at("P"), "raw") == 0,
        "Three finite stock units enter one broad lot on the sized workbed.");
    const auto saved = host.checkpoint();
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("broad-site", {"P"}),
              "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()),
              "accepted") &&
          get<bool>(restored.restore_checkpoint(saved), "accepted") &&
          !factory::values::typed_difference(saved, restored.checkpoint()),
        "Fresh restore verifies sized identities, slide coupling and the finite four-part debit.");
    pose(restored, 3.3, 1.65, ++epoch);
    const auto held = std::get<O>(get<A>(restored.projection(),
        "dropped_material").front().storage());
    auto recover = request("size-recover-work", "pickup_material");
    recover.emplace("center", held.at("center"));
    recover.emplace("expected", V(O{{"raw", held.at("raw")},
        {"products", held.at("products")}, {"work_lots", held.at("work_lots")},
        {"offcuts", held.at("offcuts")}, {"sheets", held.at("sheets")}}));
    accepted(restored, recover);
    auto reclaim_slide = request("size-reclaim-slide", "reclaim_component");
    reclaim_slide.emplace("entity", V(slide_id));
    accepted(restored, reclaim_slide);
    auto reclaim_head = request("size-reclaim-head", "reclaim_component");
    reclaim_head.emplace("entity", V(head_id));
    accepted(restored, reclaim_head);
    auto reclaim_bed = request("size-reclaim-bed", "reclaim_component");
    reclaim_bed.emplace("entity", V(bed_id));
    accepted(restored, reclaim_bed);
    check(get<O>(restored.projection(), "placed_components").empty() &&
          get<I>(V(get<O>(get<O>(restored.projection(), "cargo").at("P"),
              "components")), "anvil") == 4 &&
          get<I>(V(get<O>(get<O>(restored.projection(), "cargo").at("P"),
              "components")), "flat_head") == 4 &&
          get<I>(V(get<O>(get<O>(restored.projection(), "cargo").at("P"),
              "components")), "copper_slide") == 4,
        "Reclaim restores four carried parts of each broad kind after a fresh-process reopen.");
    auto raised = bed;
    raised.at("request") = V("size-raised-before-support");
    raised.at("center") = V(A{V(I{12}), V(I{4}), V(I{0})});
    const auto before_support = restored.projection();
    const auto unsupported = restored.command("P", raised);
    check(!get<bool>(unsupported, "accepted") &&
          get<std::string>(unsupported, "reason") == "support_required" &&
          !factory::values::typed_difference(V(get<O>(before_support, "cargo")),
              V(get<O>(restored.projection(), "cargo"))),
        "The raised broad workbed refuses to spend four anvils until every cell is supported.");
    for (int index = 0; index < 4; ++index) {
        auto floor = request("size-raised-floor-" + std::to_string(index), "place_foundation");
        floor.emplace("cell", V(A{V(I{3 + index % 2}), V(I{index / 2})}));
        floor.emplace("level", V(I{4}));
        accepted(restored, floor);
    }
    raised.at("request") = V("size-raised-supported");
    accepted(restored, raised);
    auto raised_head = head;
    raised_head.at("request") = V("size-raised-head");
    raised_head.at("center") = V(A{V(I{12}), V(I{5}), V(I{0})});
    accepted(restored, raised_head);
    auto raised_slide = slide;
    raised_slide.at("request") = V("size-raised-slide");
    raised_slide.at("center") = V(A{V(I{12}), V(I{8}), V(I{0})});
    accepted(restored, raised_slide);
    const auto upper = get<A>(restored.projection(), "broad_press_assemblies");
    check(upper.size() == 1 && get<std::string>(upper.front(), "geometry_status") == "ready" &&
          get<A>(upper.front(), "work_centers").size() == 4 &&
          get<bool>(restored.validate_checkpoint(restored.checkpoint()), "accepted"),
        "Four raised foundations carry one contiguous workbed, fitted head and single slide after restore.");
}

void channel_projection_and_wire() {
    Host host;
    check(get<bool>(host.initialize_arrival_advanced_fixture("broad-site", {"P", "Q"}),
            "accepted") &&
          get<bool>(host.configure_terrain(factory::godot_world::tests::flat_site()),
            "accepted"), "The channel consumer starts from a finite native arrival.");
    I epoch = 0;
    pose(host, 5.8, 3.3, ++epoch);
    harvest(host, "tree-east-south", 6, "channel-wood-");
    pose(host, 1.65, 6.6, ++epoch);
    craft(host, "channel_narrow_x", 1);
    craft(host, "channel_broad_x", 1);
    place(host, "channel_narrow_x", 28, 0, 0, 0, epoch);
    place(host, "channel_broad_x", 20, 0, 0, 0, epoch);
    const auto placed = get<O>(host.projection(), "placed_components");
    bool broad_found = false;
    bool narrow_found = false;
    for (const auto& [id, value] : placed) {
        (void)id;
        const auto kind = get<std::string>(value, "component");
        const auto& occupied = get<O>(value, "occupied");
        const auto& half = std::get<A>(occupied.at("half").storage());
        if (kind == "channel_broad_x") {
            broad_found = true;
            check(std::get<double>(half[2].storage()) >
                    std::get<double>(half[0].storage()),
                "Host projects the broad X channel as two workcells across Z.");
        } else if (kind == "channel_narrow_x") {
            narrow_found = true;
            check(std::get<double>(half[2].storage()) ==
                    std::get<double>(half[0].storage()),
                "Host projects a one-workcell X channel without broadening it.");
        }
    }
    check(broad_found && narrow_found,
        "Both channel widths retain their selected component identity in projection.");
    pose(host, 8.25, 1.65, ++epoch);
    auto push = request("channel-no-sheet", "push_channel_sheet");
    push.emplace("from", V(A{V(I{20}), V(I{0}), V(I{0})}));
    push.emplace("to", V(A{V(I{24}), V(I{0}), V(I{0})}));
    push.emplace("sheet_id", V(I{1}));
    const auto absent = host.command("P", push);
    check(!get<bool>(absent, "accepted") &&
          get<std::string>(absent, "reason") == "unavailable_input",
        "The ordinary wire reaches native custody and refuses an absent sheet.");
    push["sheet_id"] = V(1.0);
    const auto malformed = host.command("P", push);
    check(!get<bool>(malformed, "accepted") &&
          get<std::string>(malformed, "reason") != "unavailable_input" &&
          get<A>(host.projection(), "dropped_material").empty(),
        "The Host does not coerce a floating sheet identity or change custody.");
    auto small = request("channel-no-raw", "push_channel_small");
    small.emplace("from", V(A{V(I{28}), V(I{0}), V(I{0})}));
    small.emplace("to", V(A{V(I{32}), V(I{0}), V(I{0})}));
    small.emplace("form", V("raw"));
    const auto absent_raw = host.command("P", small);
    check(!get<bool>(absent_raw, "accepted") &&
          get<std::string>(absent_raw, "reason") == "unavailable_input",
        "The typed small-stock wire reaches native custody and refuses absent raw material.");
    small.at("request") = V("channel-float-small");
    small.at("from") = V(A{V(28.0), V(I{0}), V(I{0})});
    const auto malformed_small = host.command("P", small);
    check(!get<bool>(malformed_small, "accepted") &&
          get<std::string>(malformed_small, "reason") == "invalid_center" &&
          get<A>(host.projection(), "dropped_material").empty(),
        "The Host refuses a floating small-stock coordinate without changing custody.");
    const auto before_bad_shapes = host.projection();
    auto bad_pickup = request("bad-pickup-shape", "pickup_material");
    bad_pickup.emplace("center", V(A{V(I{20}), V(I{0}), V(I{0})}));
    bad_pickup.emplace("expected", V(I{0}));
    auto bad_stage = request("bad-stage-shape", "place_sheet");
    bad_stage.emplace("center", V(A{V(I{20}), V(I{0}), V(I{0})}));
    bad_stage.emplace("sheet_id", V(I{1}));
    bad_stage.emplace("unexpected", V(true));
    auto bad_sheet_move = request("bad-sheet-move-shape", "push_channel_sheet");
    bad_sheet_move.emplace("from", V(A{V(I{20}), V(I{0}), V(I{0})}));
    bad_sheet_move.emplace("to", V(A{V(I{24}), V(I{0}), V(I{0})}));
    bad_sheet_move.emplace("sheet_id", V(1.0));
    auto bad_small_move = request("bad-small-move-shape", "push_channel_small");
    bad_small_move.emplace("from", V(A{V(I{28}), V(I{0}), V(I{0})}));
    bad_small_move.emplace("to", V(A{V(I{32}), V(I{0}), V(I{0})}));
    bad_small_move.emplace("form", V(I{0}));
    for (const auto& wire : {bad_pickup, bad_stage, bad_sheet_move, bad_small_move}) {
        const auto refused = host.command("P", wire);
        check(!get<bool>(refused, "accepted") &&
              get<std::string>(refused, "reason") == "invalid_command",
              "Malformed material movement fields refuse through the production Host.");
    }
    const auto after_bad_shapes = host.projection();
    check(get<I>(before_bad_shapes, "revision") == get<I>(after_bad_shapes, "revision") &&
          !factory::values::typed_difference(
              V(get<O>(before_bad_shapes, "cargo")), V(get<O>(after_bad_shapes, "cargo"))) &&
          !factory::values::typed_difference(
              V(get<A>(before_bad_shapes, "dropped_material")),
              V(get<A>(after_bad_shapes, "dropped_material"))),
          "Malformed material commands leave native revision, cargo and loose material unchanged.");
    Host restored;
    check(get<bool>(restored.initialize_arrival_advanced_fixture("broad-site", {"P", "Q"}),
            "accepted") &&
          get<bool>(restored.configure_terrain(factory::godot_world::tests::flat_site()),
            "accepted") &&
          get<bool>(restored.restore_checkpoint(host.checkpoint()), "accepted") &&
          get<O>(restored.projection(), "placed_components").size() == 2,
        "A fresh Host restores both placed channel identities after refusals.");
}
}  // namespace

int main() {
    try {
        broad_projection();
        sized_workbed_custody();
        channel_projection_and_wire();
        std::cout << "broad_press_host_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "broad_press_host_test: " << error.what() << '\n';
        return 1;
    }
}
