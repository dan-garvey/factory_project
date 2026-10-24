#include "factory/checkpoint.hpp"
#include "native/factory-world/tests/harvest_fixture.hpp"

#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
namespace w = factory::world;
namespace a = factory::authority;
namespace g = factory::mechanics;
namespace m = factory::materials;
namespace s = factory::stationary;
using V = factory::values::Value;
using O = V::Object;
using I = V::Integer;

int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

V::Array point(I x, I y, I z) { return {V(x), V(y), V(z)}; }

O request(const std::string& actor, const std::string& id, const char* action) {
    return {{"context", V("press-offcut-line")}, {"client", V(actor + "-client")},
        {"request", V(id)}, {"actor", V(actor)}, {"action", V(action)}};
}

struct Site { w::Profile profile; w::State state; };

Site site(bool plate_receiver) {
    Site result;
    auto& [profile, state] = result;
    profile.material = {1, 1, 2};
    profile.material.raw_mass = 4;
    profile.material.plate_mass = 3;
    profile.material.sheet_mass = 12;
    profile.material.hand_carry_capacity = 64;
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.material.timber_sites = {{"tree", {{12, 0, 12}, 8}},
                                     {"tree-branch", {{12, 0, 24}, plate_receiver ? 6 : 4}}};
    profile.initial_units = 10;
    profile.actors = {"P", "Q"};
    profile.foundation_parts = 24;
    profile.starting_foundation_kits = {{"P", 15}, {"Q", 0}};
    profile.landing_pod_center = g::Point{4, 0, 16};
    profile.meters_per_grid_unit = 0.4125;
    profile.anchor_offset = {0, 0.825, 0};
    profile.build_reach = 100;
    profile.waterwheel_rate = {1, 1};
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, plate_receiver ? 2 : 3},
                            {{s::Role::shaft, 0, 2}, plate_receiver ? 3 : 6},
                            {{s::Role::belt, 0, 0}, plate_receiver ? 1 : 2}};
    state.material.initial_units = 10;
    state.material.stock.source = 10;
    state.material.cargo = {{"P", {}}, {"Q", {}}};
    state.material.timber_remaining = {{"tree", 8}, {"tree-branch", plate_receiver ? 6 : 4}};
    state.kits = {{"P", {}}, {"Q", {}}};
    state.foundation_kits = {{"P", 15}, {"Q", 0}};
    state.topology.drive_enabled = true;
    const auto part = [&](const char* id, g::Kind kind, g::Point center, g::Axis axis,
                          s::Role role, I half_span = 0) {
        state.topology.parts.push_back({{id, kind, center, axis, 0, half_span}, 1, role});
        state.issued_entities.emplace(id, 1);
    };
    part("press-wheel", g::Kind::hub, {4, 4, 0}, g::Axis::x, s::Role::waterwheel);
    part("feed-wheel", g::Kind::hub, {20, 0, -8}, g::Axis::z, s::Role::waterwheel);
    if (!plate_receiver)
        part("output-wheel", g::Kind::hub, {-20, 0, -8}, g::Axis::z, s::Role::waterwheel);
    for (const auto& [id, center] :
         {std::pair{"feed-drive", g::Point{20, 0, -4}},
          std::pair{"feed-outside", g::Point{20, 0, 0}},
          std::pair{"feed-mouth", g::Point{4, 0, 0}}})
        part(id, g::Kind::shaft, center, g::Axis::z, s::Role::shaft, 2);
    if (!plate_receiver)
        for (const auto& [id, center] :
             {std::pair{"output-drive", g::Point{-20, 0, -4}},
              std::pair{"output-outside", g::Point{-20, 0, 0}},
              std::pair{"output-mouth", g::Point{-4, 0, 0}}})
            part(id, g::Kind::shaft, center, g::Axis::z, s::Role::shaft, 2);
    state.topology.sources = {{"press-wheel", profile.waterwheel_rate},
                              {"feed-wheel", profile.waterwheel_rate}};
    if (!plate_receiver) state.topology.sources.push_back({"output-wheel", profile.waterwheel_rate});
    state.topology.belt_spans = {{{"input-belt", "feed-outside", "feed-mouth"}, 1}};
    if (!plate_receiver)
        state.topology.belt_spans.push_back({{"output-belt", "output-mouth", "output-outside"}, 1});
    state.material.belt_lanes.emplace("input-belt", m::BeltLane{{{}, {}, {}, {}, {}}, 0});
    if (!plate_receiver)
        state.material.belt_lanes.emplace("output-belt", m::BeltLane{{{}, {}, {}, {}, {}}, 0});
    state.issued_entities.emplace("input-belt", 1);
    if (!plate_receiver) state.issued_entities.emplace("output-belt", 1);
    state.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    state.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    state.freight_beacon = w::FreightBeacon{"first-freight-beacon",
        w::landing_freight_center(*profile.landing_pod_center), 1};
    state.hand_crank = w::HandCrank{"pod-hand-crank", 1, std::nullopt};
    for (const char* id : {"landing-pod", "pod-fabrication-hub", "first-freight-beacon", "pod-hand-crank"})
        state.issued_entities.emplace(id, 1);
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        state.foundations.emplace(id, w::Foundation{deck[index], 1});
        state.issued_entities.emplace(id, 1);
    }
    return result;
}

struct Runner {
    std::unique_ptr<w::World> world;
    a::Point p{1.65, 1, 6.6};
    a::Point q{0.8, 1, 0.8};
    explicit Runner(const Site& source)
        : world(w::World::create("press-offcut-line", source.profile, source.state)) {
        check(world != nullptr, "The finite three-drive site initializes without gifted press parts.");
    }
    O accept(const std::string& actor, const O& intent) {
        const w::ObserveActor observe = [this](const std::string& selected) -> std::optional<a::ActorCut> {
            return a::ActorCut{selected, selected == "P" ? p : q, 1, true, 4};
        };
        const auto result = std::get<std::string>(intent.at("action").storage()) == "harvest_source" ?
            w::tests::complete_manual_cut(*world, {actor, actor + "-client"}, intent, observe) :
            world->command({actor, actor + "-client"}, intent, observe);
        if (!result.completed() || !result.result ||
            !std::get<bool>(result.result->at("accepted").storage()))
            throw std::runtime_error("Request " + std::get<std::string>(intent.at("request").storage()) +
                " refused: " + (result.result ?
                    std::get<std::string>(result.result->at("reason").storage()) : "no result"));
        ++checks;
        return *result.result;
    }
};

void run_line(bool plate_receiver) {
    const auto source = site(plate_receiver);
    Runner run(source);
    run.p = {4.95, 1, 9.9};
    for (int index = 0; index < 5; ++index) {
        auto cut = request("P", "wood-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree"));
        run.accept("P", cut);
    }
    run.p = {0, 1, 1.65};
    for (int index = 0; index < 9; ++index) {
        auto cut = request("P", "ore-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("ore"));
        run.accept("P", cut);
    }
    run.p = {1.65, 1, 6.6};
    for (const char* kind : {"anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog"}) {
        auto craft = request("P", std::string("craft-") + kind, "craft_component");
        craft.emplace("target", V("pod-fabrication-hub"));
        craft.emplace("generation", V(I{1}));
        craft.emplace("component", V(kind));
        run.accept("P", craft);
    }
    for (int index = 0; index < (plate_receiver ? 4 : 2); ++index) {
        auto cut = request("P", "branch-" + std::to_string(index), "harvest_source");
        cut.emplace("target", V("tree-branch"));
        run.p = {4.95, 1, 9.9};
        run.accept("P", cut);
    }
    run.p = {1.65, 1, 6.6};
    auto craft = request("P", "craft-tray", "craft_component");
    craft.emplace("target", V("pod-fabrication-hub"));
    craft.emplace("generation", V(I{1}));
    craft.emplace("component", V("receiver_tray"));
    run.accept("P", craft);
    if (plate_receiver) {
        auto plate_tray = request("P", "craft-plate-tray", "craft_component");
        plate_tray.emplace("target", V("pod-fabrication-hub"));
        plate_tray.emplace("generation", V(I{1}));
        plate_tray.emplace("component", V("receiver_tray"));
        run.accept("P", plate_tray);
    }
    run.p = {2, 1, 0};
    for (const auto& [kind, center] :
         {std::pair{"anvil", g::Point{0, 0, 0}},
          std::pair{"ram_face", g::Point{0, 1, 0}},
          std::pair{"sliding_guide", g::Point{0, 3, 0}},
          std::pair{"wooden_shaft", g::Point{1, 4, 0}},
          std::pair{"wooden_cog", g::Point{2, 4, 0}},
          std::pair{"receiver_tray", g::Point{0, 0, 1}}}) {
        auto place = request("P", std::string("place-") + kind, "place_component");
        place.emplace("component", V(kind));
        place.emplace("center", V(point(center[0], center[1], center[2])));
        run.accept("P", place);
    }
    if (plate_receiver) {
        auto place = request("P", "place-plate-tray", "place_component");
        place.emplace("component", V("receiver_tray"));
        place.emplace("center", V(point(-1, 0, 0)));
        run.accept("P", place);
    }
    check(w::World::restore("press-offcut-line", source.profile, run.world->snapshot()) != nullptr,
          "The actual fitted press, inlet, outlet and tray restore before work begins.");
    for (int slot = 0; slot < 4; ++slot) {
        run.p = {1.65 + (20 - 4 * slot) * 0.4125, 1, 0};
        auto load = request("P", "load-raw-" + std::to_string(slot), "load_belt_slot");
        load.emplace("target", V("input-belt"));
        load.emplace("generation", V(I{1}));
        load.emplace("slot", V(I{slot}));
        load.emplace("item", V("raw"));
        load.emplace("work_id", V(I{0}));
        run.accept("P", load);
    }
    const auto loaded = run.world->snapshot();
    check(w::World::restore("press-offcut-line", source.profile, loaded) != nullptr,
          "Four finite blanks on the physical input belt restore before the unattended run.");
    bool one_plate_checked = false;
    for (int tick = 0; tick < 40; ++tick) {
        check(run.world->tick().error == w::TransactionError::none,
              "The connected three-drive line advances under native power.");
        const auto current = run.world->snapshot();
        if (plate_receiver && !one_plate_checked &&
            current.state.press_output_at_receiver.contains({-1, 0, 0})) {
            const auto& ids = current.state.press_output_at_receiver.at({-1, 0, 0});
            check(ids.size() == 1 && current.state.belt_press_products.contains({-1, 0, 0}) &&
                  current.state.belt_press_products.at({-1, 0, 0}).contains(*ids.begin()) &&
                  current.state.material.dropped_material.at({-1, 0, 0}) == m::Cargo{0, 1, {}},
                  "The first belt-fed plate sits in its real fitted receiver.");
            check(std::holds_alternative<V>(w::encode_checkpoint(source.profile, current)) &&
                  w::World::restore("press-offcut-line", source.profile, current) != nullptr,
                  "A lone belt-fed plate in a receiver can save before the next turn.");
            one_plate_checked = true;
        }
        const auto tray = current.state.material.dropped_material.find({0, 0, 1});
        if (tray != current.state.material.dropped_material.end() && tray->second.offcuts == 4)
            break;
    }
    const auto count_plates = [](const m::State& material) {
        I plates = material.cargo.at("P").products + material.cargo.at("Q").products;
        for (const auto& [point, cargo] : material.dropped_material) {
            (void)point;
            plates += cargo.products;
        }
        for (const auto& [id, lane] : material.belt_lanes) {
            (void)id;
            for (const auto& slot : lane.slots)
                if (slot) plates += slot->products;
        }
        return plates;
    };
    const auto four = run.world->snapshot();
    check(!plate_receiver || one_plate_checked,
          "The fitted plate receiver retained the first belt-fed product.");
    if (plate_receiver) {
        check(four.state.material.dropped_material.at({-1, 0, 0}).products == 4 &&
              four.state.press_output_at_receiver.at({-1, 0, 0}).size() == 4 &&
              four.state.material.dropped_material.at({0, 0, 1}).offcuts == 4 &&
              std::holds_alternative<V>(w::encode_checkpoint(source.profile, four)) &&
              w::World::restore("press-offcut-line", source.profile, four) != nullptr,
              "Four belt-fed plates and offcuts keep separate finite trays across a checkpoint.");
        return;
    }
    check(count_plates(four.state.material) == 4 &&
          four.state.material.dropped_material.at({0, 0, 1}).offcuts == 4 &&
          !four.state.material.dropped_material.contains({0, 0, 0}) &&
          w::validate(source.profile, four),
          "Four powered strokes route all plates and offcuts separately without actor pickup.");
    check(w::World::restore("press-offcut-line", source.profile, four) != nullptr,
          "The complete four-stroke line and its full side receiver restore exactly.");

    run.p = {0, 1, 1.65};
    auto harvest = request("P", "fifth-ore", "harvest_source");
    harvest.emplace("target", V("ore"));
    run.accept("P", harvest);
    run.p = {1.65 + 20 * 0.4125, 1, 0};
    auto load = request("P", "fifth-input", "load_belt_slot");
    load.emplace("target", V("input-belt"));
    load.emplace("generation", V(I{1}));
    load.emplace("slot", V(I{0}));
    load.emplace("item", V("raw"));
    load.emplace("work_id", V(I{0}));
    run.accept("P", load);
    for (int tick = 0; tick < 30; ++tick) {
        check(run.world->tick().error == w::TransactionError::none,
              "A fifth finite blank reaches the full receiver without losing power.");
        const auto current = run.world->snapshot();
        check(w::validate(source.profile, current),
              "Every intermediate belt and ready-work state passes full historical validation.");
        const auto work = current.state.material.dropped_material.find({0, 0, 0});
        if (work != current.state.material.dropped_material.end() &&
            work->second.work_lots.size() == 1 &&
            work->second.work_lots.front().remaining_ticks == 0) break;
    }
    const auto blocked = run.world->snapshot();
    const auto& blocked_material = blocked.state.material;
    check(count_plates(blocked_material) == 4 &&
          blocked_material.dropped_material.at({0, 0, 1}).offcuts == 4 &&
          blocked_material.dropped_material.at({0, 0, 0}).work_lots.size() == 1 &&
          blocked_material.dropped_material.at({0, 0, 0}).work_lots.front().remaining_ticks == 0 &&
          !blocked_material.dropped_material.contains({-1, 0, 0}) &&
          w::validate(source.profile, blocked),
          "The full side tray holds one ready fifth lot without releasing another plate.");
    auto forged = blocked;
    forged.state.belt_press_products[{-1, 0, 0}].insert(
        blocked_material.dropped_material.at({0, 0, 0}).work_lots.front().id);
    check(!w::validate(source.profile, forged) &&
          w::World::restore("press-offcut-line", source.profile, forged) == nullptr,
          "A ready but unreleased belt-fed workpiece cannot claim a finished plate.");
    const auto prior = blocked.state;
    check(run.world->tick().error == w::TransactionError::none &&
          run.world->snapshot().state == prior,
          "More powered ticks cannot duplicate the blocked fifth plate.");
    Runner resumed(source);
    resumed.world = w::World::restore("press-offcut-line", source.profile, blocked);
    check(resumed.world != nullptr, "The full-tray stall restores for a second actor.");
    auto clear = request("Q", "clear-full-tray", "pickup_material");
    clear.emplace("center", V(point(0, 0, 1)));
    clear.emplace("expected", V(O{{"raw", V(I{0})}, {"products", V(I{0})},
        {"work_lots", V(V::Array{})}, {"offcuts", V(I{4})}, {"sheets", V(I{0})}}));
    resumed.accept("Q", clear);
    check(resumed.world->tick().error == w::TransactionError::none,
          "The freed tray lets the same ready fifth lot complete.");
    const auto continued = resumed.world->snapshot();
    check(count_plates(continued.state.material) == 5 &&
          continued.state.material.cargo.at("Q").offcuts == 4 &&
          continued.state.material.dropped_material.at({0, 0, 1}).offcuts == 1 &&
          !continued.state.material.dropped_material.contains({0, 0, 0}) &&
          w::validate(source.profile, continued) &&
          w::World::restore("press-offcut-line", source.profile, continued) != nullptr,
          "Shared continuation releases exactly one fifth plate and one new offcut without mass loss.");
}
} // namespace

int main() {
    try {
        run_line(false);
        run_line(true);
        std::cout << "press_offcut_line_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "press_offcut_line_test: " << error.what() << '\n';
        return 1;
    }
}
