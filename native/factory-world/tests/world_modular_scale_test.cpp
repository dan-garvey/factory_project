#include "factory/checkpoint.hpp"
#include "factory/world.hpp"
#include "native/factory-world/tests/harvest_fixture.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace w = factory::world;
namespace a = factory::assembly;
namespace g = factory::mechanics;
namespace m = factory::materials;
namespace s = factory::stationary;
using V = factory::values::Value;

struct ProductiveSite {
    w::Profile profile;
    w::Snapshot snapshot;
    std::vector<double> command_ms;
};

ProductiveSite productive_site(g::Integer cycle_ticks = 2, int line_count = 2,
                              bool audit_commands = false) {
    if (line_count < 2 || line_count > 80)
        throw std::runtime_error("The productive scale count is outside the bounded fixture.");
    w::Profile profile;
    profile.material = {1, 2, cycle_ticks};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    const g::Integer timber_units = std::max<g::Integer>(40, line_count * 17);
    profile.material.timber_sites = {{"tree", {{12, 0, 12}, timber_units}}};
    profile.material.hand_carry_capacity = std::max<g::Integer>(100, line_count * 20 + 10);
    profile.initial_units = std::max<g::Integer>(100, line_count * 32);
    profile.actors = {"P"};
    profile.foundation_parts = 9;
    profile.starting_foundation_kits = {{"P", 0}};
    profile.landing_pod_center = g::Point{0, 0, 1000};
    profile.build_reach = 10000;
    profile.finite_parts = {{{s::Role::waterwheel, 0, 0}, line_count * 2}};
    w::State seed;
    seed.material.initial_units = profile.initial_units;
    seed.material.stock.source = profile.initial_units;
    seed.material.timber_remaining = {{"tree", timber_units}};
    seed.material.cargo.emplace("P", m::Cargo{});
    seed.kits.emplace("P", s::Kit{});
    seed.foundation_kits.emplace("P", 0);
    seed.topology.drive_enabled = true;
    seed.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    seed.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    seed.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1}};
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        seed.foundations.emplace(id, w::Foundation{deck[index], 1});
        seed.issued_entities.emplace(id, 1);
    }
    for (int line = 0; line < line_count; ++line) {
        const g::Integer base = 800 + line * 40;
        profile.collector_faces.push_back({{base, 0, 0}, {-1, 0, 0}});
        for (const auto& [suffix, height, z] : {
                std::tuple{"collector-wheel", g::Integer{0}, g::Integer{0}},
                std::tuple{"press-wheel", g::Integer{4}, g::Integer{16}}}) {
            const auto id = std::to_string(base) + suffix;
            const factory::waterwheel::Sample sample{0, -1000, 0, -600};
            profile.water.emplace(std::array<g::Integer, 2>{base + 4, z}, sample);
            const auto rate = factory::waterwheel::rate(height * 100 + 121, 600,
                g::Axis::x, sample);
            if (!rate || rate->numerator == 0)
                throw std::runtime_error("A modular source wheel did not turn.");
            seed.topology.parts.push_back({{id, g::Kind::hub, {base + 4, height, z},
                g::Axis::x, 0, 0}, 1, s::Role::waterwheel});
            seed.topology.sources.push_back({id, *rate});
            seed.issued_entities.emplace(id, 1);
        }
    }
    auto world = w::World::create("mixed-scale", profile, seed);
    if (!world) throw std::runtime_error("The many-source modular startup was rejected.");
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<factory::authority::ActorCut> {
        return factory::authority::ActorCut{actor, {0, 0, 0}, 1, true, 10000};
    };
    int request = 0;
    std::vector<double> command_ms;
    const auto issue = [&](const char* action, V::Object fields) -> V::Object {
        fields.emplace("context", V("mixed-scale"));
        fields.emplace("client", V("P-client"));
        fields.emplace("request", V("scale-setup-" + std::to_string(++request)));
        fields.emplace("actor", V("P"));
        fields.emplace("action", V(action));
        const auto started = std::chrono::steady_clock::now();
        const auto result = std::string(action) == "harvest_source" ?
            w::tests::complete_manual_cut(*world, {"P", "P-client"}, fields, nearby) :
            world->command({"P", "P-client"}, fields, nearby);
        if (std::string(action) != "harvest_source")
            command_ms.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - started).count());
        if (!result.completed() || !result.result ||
            !std::get<bool>(result.result->at("accepted").storage()))
            throw std::runtime_error(std::string("Mixed site setup refused ") + action + ": " +
                (result.result ? std::get<std::string>(result.result->at("reason").storage()) :
                    "no result at request " + std::to_string(request) + " (transaction " +
                    std::to_string(static_cast<int>(result.error)) + ", history " +
                    std::to_string(static_cast<int>(result.history_error)) + ")"));
        if (audit_commands && !w::validate(profile, world->snapshot()))
            throw std::runtime_error("A trusted native command failed full independent history validation at request " +
                std::to_string(request));
        return *result.result;
    };
    for (int index = 0; index < line_count * 17; ++index)
        issue("harvest_source", {{"target", V("tree")}});
    for (int index = 0; index < line_count * 5; ++index)
        issue("harvest_source", {{"target", V("ore")}});
    const auto place = [&](const char* component, g::Point center) -> V::Object {
        issue("craft_component", {{"target", V("pod-fabrication-hub")},
            {"generation", V(g::Integer{1})}, {"component", V(component)}});
        return issue("place_component", {{"component", V(component)},
            {"center", V(V::Array{V(center[0]), V(center[1]), V(center[2])})}});
    };
    std::vector<std::pair<std::string, g::Integer>> presses;
    std::vector<std::pair<std::string, g::Integer>> press_mounts;
    std::vector<std::string> driven_shafts;
    for (int line = 0; line < line_count; ++line) {
        const g::Integer base = 800 + line * 40;
        place("wooden_frame", {base, 0, 0});
        place("tool_mount", {base - 1, 0, 0});
        place("cutting_edge", {base - 2, 0, 0});
        place("receiver_tray", {base, 0, 1});
        driven_shafts.push_back(std::get<std::string>(
            place("wooden_shaft", {base + 1, 0, 0}).at("entity").storage()));
        const auto frame = place("wooden_frame", {base, 0, 16});
        presses.emplace_back(std::get<std::string>(frame.at("entity").storage()),
            std::get<g::Integer>(frame.at("generation").storage()));
        place("anvil", {base, 1, 16});
        place("ram_face", {base, 2, 16});
        place("sliding_guide", {base, 3, 16});
        const auto mount = place("tool_mount", {base, 4, 16});
        press_mounts.emplace_back(std::get<std::string>(mount.at("entity").storage()),
            std::get<g::Integer>(mount.at("generation").storage()));
        driven_shafts.push_back(std::get<std::string>(
            place("wooden_shaft", {base + 1, 4, 16}).at("entity").storage()));
        place("wooden_cog", {base + 2, 4, 16});
    }
    const auto power = w::drive_power(profile, world->snapshot().state);
    if (!power.mechanical.accepted()) throw std::runtime_error("The modular startup graph was rejected.");
    for (const auto& id : driven_shafts)
        if (!power.mechanical.motion.contains(id) ||
            power.mechanical.motion.at(id).state != g::MotionState::rotating) {
            if (power.load.contains(id))
                std::cerr << "STOP " << id << " load=" << power.load.at(id).impact
                          << " limit=" << power.load.at(id).capacity
                          << " by=" << power.load.at(id).limiting_part << '\n';
            throw std::runtime_error("A modular machine shaft stopped: " + id);
        }
    const auto before = world->snapshot();
    if (world->tick().error != w::TransactionError::none ||
        world->snapshot().state.material.stock.source != before.state.material.stock.source - line_count)
        throw std::runtime_error("Every modular collector did not produce independently.");
    for (std::size_t index = 0; index < presses.size(); ++index) {
        const g::Integer base = 800 + static_cast<g::Integer>(index) * 40;
        if (line_count == 10 && index == 1) {
            // A later build invalidates the historical press layout after the
            // first feed; the second feed must inspect the new exact prefix.
            issue("reclaim_component", {{"target", V(press_mounts[index].first)},
                {"generation", V(press_mounts[index].second)}});
            issue("place_component", {{"component", V("tool_mount")},
                {"center", V(V::Array{V(base), V(g::Integer{4}), V(g::Integer{16})})}});
        }
        issue("pickup_material", {{"center", V(V::Array{V(base), V(g::Integer{0}), V(g::Integer{1})})},
            {"expected", V(V::Object{{"raw", V(g::Integer{1})}, {"products", V(g::Integer{0})},
                {"work_lots", V(V::Array{})}})}});
        issue("feed_press", {{"target", V(presses[index].first)},
            {"generation", V(presses[index].second)},
            {"entry", V(V::Array{V(base + 1), V(g::Integer{1}), V(g::Integer{16})})}});
    }
    const auto constructed = world->snapshot();
    if (line_count == 10) {
        // This owner already warmed its layout before the later press fitting
        // was reclaimed and replaced. Its next tick must inspect the new
        // component identities exactly like an uncached restored owner.
        auto fresh = w::World::restore("mixed-scale", profile, constructed);
        if (!fresh || world->tick().error != w::TransactionError::none ||
            fresh->tick().error != w::TransactionError::none ||
            world->snapshot().state != fresh->snapshot().state ||
            world->snapshot().revision != fresh->snapshot().revision ||
            !w::validate(profile, world->snapshot()))
            throw std::runtime_error("A changed press layout reused stale tick geometry.");
    }
    return {std::move(profile), constructed, std::move(command_ms)};
}

void powered_cog_world(bool benchmark, int cog_count = 400, bool sustained = false) {
    auto site = productive_site(sustained ? 200 : 2);
    auto& profile = site.profile;
    auto& seed = site.snapshot.state;
    for (int index = 0; index < cog_count; ++index) {
        ++profile.finite_parts[{s::Role::waterwheel, 0, 0}];
        ++profile.finite_parts[{s::Role::shaft, 0, 2}];
        ++profile.finite_parts[{s::Role::gear, 2, 0}];
        const g::Integer x = (index % 20) * 32;
        const g::Integer z = (index / 20) * 32;
        const auto prefix = "scale-cog-" + std::to_string(index);
        const auto wheel = prefix + "-wheel";
        const auto shaft = prefix + "-shaft";
        const auto cog = prefix + "-gear";
        const factory::waterwheel::Sample sample{0, -1000, 200, 0};
        const auto rate = factory::waterwheel::rate(121, 600, g::Axis::z, sample);
        if (!rate || rate->numerator == 0)
            throw std::runtime_error("The trusted water sample did not rotate a cog source.");
        profile.water.emplace(std::array<g::Integer, 2>{x, z}, sample);
        seed.topology.parts.push_back({{wheel, g::Kind::hub, {x, 0, z},
            g::Axis::z, 0, 0}, 1, s::Role::waterwheel});
        seed.topology.parts.push_back({{shaft, g::Kind::shaft, {x, 0, z + 4},
            g::Axis::z, 0, 2}, 1, s::Role::shaft});
        seed.topology.parts.push_back({{cog, g::Kind::gear, {x, 0, z + 8},
            g::Axis::z, 2, 0}, 1, s::Role::gear});
        seed.topology.sources.push_back({wheel, *rate});
        for (const auto& id : {wheel, shaft, cog}) seed.issued_entities.emplace(id, 1);
    }
    auto world = w::World::restore("mixed-scale", profile, site.snapshot);
    if (!world) throw std::runtime_error("The World rejected the mixed modular and cog site.");
    const auto initial = world->snapshot();
    const auto power = w::drive_power(profile, initial.state);
    if (!power.mechanical.accepted() || power.mechanical.motion.size() < static_cast<std::size_t>(cog_count) * 3)
        throw std::runtime_error("The World lost a cog, axle, or source identity.");
    for (int index = 0; index < cog_count; ++index) {
        const auto id = "scale-cog-" + std::to_string(index) + "-gear";
        const auto found = power.mechanical.motion.find(id);
        if (found == power.mechanical.motion.end() || found->second.state != g::MotionState::rotating)
            throw std::runtime_error("A native scale cog did not rotate: " + id);
    }
    const auto encoded = w::encode_checkpoint(profile, initial);
    if (!std::holds_alternative<factory::values::Value>(encoded))
        throw std::runtime_error("The powered cog checkpoint could not encode.");
    const auto decoded = w::decode_checkpoint(profile, "mixed-scale",
        std::get<factory::values::Value>(encoded));
    if (!std::holds_alternative<w::Snapshot>(decoded) ||
        std::get<w::Snapshot>(decoded).state != initial.state)
        throw std::runtime_error("The powered cog checkpoint lost an identity.");
    auto restored = w::World::restore("mixed-scale", profile, std::get<w::Snapshot>(decoded));
    if (!restored)
        throw std::runtime_error("The restored mixed World rejected its checkpoint.");
    if (world->tick().error != w::TransactionError::none ||
        !w::validate(profile, world->snapshot()))
        throw std::runtime_error("A mixed World tick lost finite custody.");
    const auto advanced = world->snapshot();
    for (const auto base : {g::Integer{800}, g::Integer{840}}) {
        const auto work = advanced.state.material.dropped_material.find({base, 1, 16});
        if (work == advanced.state.material.dropped_material.end() ||
            work->second.work_lots.size() != 1)
            throw std::runtime_error("A modular press did not start its own real work lot.");
    }
    if (benchmark) {
        const auto measure = [&](const char* stage, auto&& operation) {
            std::vector<double> samples;
            samples.reserve(100);
            for (int sample = 0; sample < 100; ++sample) {
                const auto start = std::chrono::steady_clock::now();
                operation();
                samples.push_back(std::chrono::duration<double, std::milli>(
                    std::chrono::steady_clock::now() - start).count());
            }
            std::sort(samples.begin(), samples.end());
            std::cout << "WORLD_COG_STAGE name=" << stage << " cogs=" << cog_count
                      << " samples=" << samples.size() << " median_ms=" << samples[50]
                      << " p95_ms=" << samples[94] << '\n';
        };
        measure("drive_power", [&] {
            if (!w::drive_power(profile, initial.state).mechanical.accepted())
                throw std::runtime_error("The measured cog drive was rejected.");
        });
        measure("validate", [&] {
            if (!w::validate(profile, initial))
                throw std::runtime_error("The measured cog World was rejected.");
        });
        std::vector<double> ticks;
        ticks.reserve(100);
        for (int sample = 0; sample < 100; ++sample) {
            auto fresh = w::World::restore("mixed-scale", profile, initial);
            if (!fresh) throw std::runtime_error("A measured mixed World did not restore.");
            const auto start = std::chrono::steady_clock::now();
            if (fresh->tick().error != w::TransactionError::none)
                throw std::runtime_error("The measured cog tick failed.");
            ticks.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(ticks.begin(), ticks.end());
        std::cout << "WORLD_COG_STAGE name=tick cogs=" << cog_count
                  << " samples=" << ticks.size() << " median_ms=" << ticks[50]
                  << " p95_ms=" << ticks[94] << '\n';
        if (sustained) {
            auto running = w::World::restore("mixed-scale", profile, initial);
            if (!running) throw std::runtime_error("The sustained World did not restore.");
            const auto start = std::chrono::steady_clock::now();
            if (running->tick().error != w::TransactionError::none)
                throw std::runtime_error("The first sustained cog tick failed.");
            const double first_ms = std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count();
            const auto first = running->snapshot();
            std::vector<double> repeated;
            repeated.reserve(100);
            for (int sample = 0; sample < 100; ++sample) {
                const auto before = std::chrono::steady_clock::now();
                if (running->tick().error != w::TransactionError::none)
                    throw std::runtime_error("A sustained cog tick failed.");
                repeated.push_back(std::chrono::duration<double, std::milli>(
                    std::chrono::steady_clock::now() - before).count());
            }
            const auto end = running->snapshot();
            if (!w::validate(profile, end) || end.revision - initial.revision != 101 ||
                end.state.material.stock.source >= initial.state.material.stock.source)
                throw std::runtime_error("Sustained productive cog work lost finite custody.");
            for (const auto base : {g::Integer{800}, g::Integer{840}}) {
                const g::Point work{base, 1, 16};
                const auto before = first.state.material.dropped_material.find(work);
                const auto after = end.state.material.dropped_material.find(work);
                if (before == first.state.material.dropped_material.end() ||
                    after == end.state.material.dropped_material.end() ||
                    before->second.work_lots.size() != 1 || after->second.work_lots.size() != 1 ||
                    after->second.work_lots.front() == before->second.work_lots.front())
                    throw std::runtime_error("Sustained modular press work did not advance.");
            }
            std::sort(repeated.begin(), repeated.end());
            std::cout << "WORLD_COG_STAGE name=tick_sustained cogs=" << cog_count
                      << " samples=" << repeated.size() << " first_ms=" << first_ms
                      << " median_ms=" << repeated[50] << " p95_ms=" << repeated[94]
                      << " changed_revisions=" << end.revision - initial.revision
                      << " remaining_source=" << end.state.material.stock.source << '\n';
        }
    }
    if (restored->tick().error != w::TransactionError::none ||
        restored->snapshot().state != advanced.state ||
        restored->snapshot().revision != advanced.revision)
        throw std::runtime_error("The restored mixed World diverged on its first tick.");
    auto switched = w::World::restore("mixed-scale", profile, advanced);
    if (!switched || switched->tick().error != w::TransactionError::none)
        throw std::runtime_error("The drive-switch World did not warm its graph.");
    const w::ObserveActor nearby = [](const std::string& actor) -> std::optional<factory::authority::ActorCut> {
        return factory::authority::ActorCut{actor, {0, 0, 0}, 1, true, 10000};
    };
    const auto set_drive = [&](bool enabled, const char* request) {
        const V::Object intent{{"context", V("mixed-scale")}, {"client", V("P-client")},
            {"request", V(request)}, {"actor", V("P")}, {"action", V("set_drive")},
            {"target", V("scale-cog-0-wheel")}, {"generation", V(g::Integer{1})},
            {"enabled", V(enabled)}};
        const auto result = switched->command({"P", "P-client"}, intent, nearby);
        if (!result.completed() || !result.result ||
            !std::get<bool>(result.result->at("accepted").storage()))
            throw std::runtime_error("The drive switch was refused.");
    };
    const auto compare_next_tick = [&] {
        auto fresh = w::World::restore("mixed-scale", profile, switched->snapshot());
        if (!fresh || switched->tick().error != w::TransactionError::none ||
            fresh->tick().error != w::TransactionError::none ||
            switched->snapshot().state != fresh->snapshot().state ||
            switched->snapshot().revision != fresh->snapshot().revision)
            throw std::runtime_error("A cached drive diverged from a newly restored World.");
    };
    set_drive(false, "scale-drive-off");
    if (w::drive_power(profile, switched->snapshot().state).mechanical.motion.at("scale-cog-0-gear").state !=
            g::MotionState::stopped)
        throw std::runtime_error("Disabling the drive left a scale cog rotating.");
    compare_next_tick();
    set_drive(true, "scale-drive-on");
    if (w::drive_power(profile, switched->snapshot().state).mechanical.motion.at("scale-cog-0-gear").state !=
            g::MotionState::rotating)
        throw std::runtime_error("Reenabling the drive did not rotate a scale cog.");
    compare_next_tick();
    for (int step = 0; step < 2; ++step)
        if (world->tick().error != w::TransactionError::none ||
            restored->tick().error != w::TransactionError::none ||
            restored->snapshot().state != world->snapshot().state ||
            restored->snapshot().revision != world->snapshot().revision)
            throw std::runtime_error("Restored mixed press work diverged during production.");
    const auto finished = world->snapshot();
    if (!w::validate(profile, finished))
        throw std::runtime_error("Finished mixed work lost finite custody.");
    std::set<m::WorkId> produced_ids;
    if (!sustained) {
        for (const auto base : {g::Integer{800}, g::Integer{840}}) {
            const g::Point work{base, 1, 16};
            const g::Point exit{base - 1, 1, 16};
            const auto product = finished.state.material.dropped_material.find(work);
            const auto witness = finished.state.press_output_on_work.find(work);
            if (product == finished.state.material.dropped_material.end() ||
                product->second.products != 1 || witness == finished.state.press_output_on_work.end() ||
                witness->second.selected_exit != exit ||
                !produced_ids.insert(witness->second.id).second)
                throw std::runtime_error("One modular workbed failed to retain its finished plate.");
        }
    }
    std::cout << "WORLD_COG_SCALE_CHECK rotating=" << cog_count
              << " collectors=2 presses=2 passed\n";
}

void productive_line_scale(int line_count, bool audit_commands = false) {
    const auto build_started = std::chrono::steady_clock::now();
    auto site = productive_site(200, line_count, audit_commands);
    const double build_ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - build_started).count();
    std::vector<double> tail_commands(site.command_ms.end() - std::min<std::size_t>(100, site.command_ms.size()),
        site.command_ms.end());
    std::sort(tail_commands.begin(), tail_commands.end());
    if (site.snapshot.state.placed_components.size() != static_cast<std::size_t>(line_count) * 12 ||
        site.snapshot.state.topology.parts.size() != static_cast<std::size_t>(line_count) * 2 ||
        site.profile.collector_faces.size() != static_cast<std::size_t>(line_count))
        throw std::runtime_error("A productive line lost a constructed component or source.");
    const auto saved = w::encode_checkpoint(site.profile, site.snapshot);
    if (!std::holds_alternative<V>(saved))
        throw std::runtime_error("The multiline World checkpoint could not encode: reason " +
            std::to_string(static_cast<int>(std::get<w::CheckpointRefusal>(saved).reason)) +
            " at " + std::get<w::CheckpointRefusal>(saved).path);
    const auto decoded = w::decode_checkpoint(site.profile, "mixed-scale", std::get<V>(saved));
    if (!std::holds_alternative<w::Snapshot>(decoded) ||
        std::get<w::Snapshot>(decoded).state != site.snapshot.state)
        throw std::runtime_error("The multiline checkpoint did not conserve its construction.");
    auto live = w::World::restore("mixed-scale", site.profile, site.snapshot);
    auto fresh = w::World::restore("mixed-scale", site.profile, std::get<w::Snapshot>(decoded));
    if (!live || !fresh)
        throw std::runtime_error("The productive multiline World did not restore.");
    const auto first_started = std::chrono::steady_clock::now();
    const auto first_tick = live->tick();
    const double first_tick_ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - first_started).count();
    if (first_tick.error != w::TransactionError::none ||
        fresh->tick().error != w::TransactionError::none ||
        live->snapshot().state != fresh->snapshot().state ||
        live->snapshot().revision != fresh->snapshot().revision)
        throw std::runtime_error("Two restored productive multiline Worlds diverged.");
    const auto& state = live->snapshot().state;
    std::set<m::WorkId> work_ids;
    for (int line = 0; line < line_count; ++line) {
        const g::Integer base = 800 + line * 40;
        const auto receiver = state.material.dropped_material.find({base, 0, 1});
        const auto work = state.material.dropped_material.find({base, 1, 16});
        if (receiver == state.material.dropped_material.end() || receiver->second.raw_units != 1 ||
            work == state.material.dropped_material.end() || work->second.work_lots.size() != 1 ||
            !work_ids.insert(work->second.work_lots.front().id).second)
            throw std::runtime_error("A productive line lost unique received ore or press work.");
    }
    const auto stage_snapshot = live->snapshot();
    const auto measure_stage = [&](const char* name, auto&& operation) {
        std::vector<double> samples;
        samples.reserve(20);
        for (int sample = 0; sample < 20; ++sample) {
            const auto start = std::chrono::steady_clock::now();
            operation();
            samples.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(samples.begin(), samples.end());
        std::cout << "WORLD_PRODUCTIVE_STAGE name=" << name << " count=" << line_count
                  << " median_ms=" << samples[10] << " p95_ms=" << samples[18] << '\n';
    };
    measure_stage("drive_power", [&] {
        if (!w::drive_power(site.profile, stage_snapshot.state).mechanical.accepted())
            throw std::runtime_error("The measured multiline drive failed.");
    });
    measure_stage("validate", [&] {
        if (!w::validate(site.profile, stage_snapshot))
            throw std::runtime_error("The measured multiline World failed validation.");
    });
    measure_stage("generic_history", [&] {
        if (factory::authority::validate_history(stage_snapshot.history, stage_snapshot.revision) !=
                factory::authority::Error::none)
            throw std::runtime_error("The measured request history failed validation.");
    });
    measure_stage("history_copy", [&] {
        const auto copied = stage_snapshot.history;
        if (copied.records.size() != stage_snapshot.history.records.size())
            throw std::runtime_error("The measured request history was not copied.");
    });
    measure_stage("state_copy", [&] {
        const auto copied = stage_snapshot.state;
        if (copied.placed_components.size() != stage_snapshot.state.placed_components.size())
            throw std::runtime_error("The measured World state was not copied.");
    });
    measure_stage("assembly_layout", [&] {
        std::vector<a::Part> placed;
        placed.reserve(stage_snapshot.state.placed_components.size());
        for (const auto& [id, component] : stage_snapshot.state.placed_components)
            placed.push_back({id, component.kind, component.center, component.generation});
        const a::Layout layout(placed);
        if (layout.inspect_collector(site.profile.collector_faces.front()).status != a::Status::ready)
            throw std::runtime_error("The measured assembly layout lost a ready collector.");
    });
    std::vector<a::Part> inspected_parts;
    inspected_parts.reserve(stage_snapshot.state.placed_components.size());
    for (const auto& [id, component] : stage_snapshot.state.placed_components)
        inspected_parts.push_back({id, component.kind, component.center, component.generation});
    const a::Layout inspected_layout(inspected_parts);
    measure_stage("assembly_inspection", [&] {
        std::size_t collectors = 0, presses = 0;
        for (const auto& face : site.profile.collector_faces)
            collectors += inspected_layout.inspect_collector(face).collector.has_value();
        for (const auto& part : inspected_parts)
            if (part.kind == m::Component::wooden_frame)
                presses += inspected_layout.inspect_press(part.center).press.has_value();
        if (collectors != static_cast<std::size_t>(line_count) ||
            presses != static_cast<std::size_t>(line_count))
            throw std::runtime_error("Measured assembly inspections lost a productive machine.");
    });
    std::vector<double> ticks;
    ticks.reserve(20);
    for (int sample = 0; sample < 20; ++sample) {
        const auto start = std::chrono::steady_clock::now();
        if (live->tick().error != w::TransactionError::none)
            throw std::runtime_error("The sustained multiline tick failed.");
        ticks.push_back(std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - start).count());
    }
    std::sort(ticks.begin(), ticks.end());
    if (!w::validate(site.profile, live->snapshot()) ||
        live->snapshot().state.press_progress.size() != static_cast<std::size_t>(line_count))
        throw std::runtime_error("Sustained multiline work or finite custody was invalid.");
    // Audit every accelerated candidate with the public complete validator on
    // a separate owner. Keep these full replay checks outside timed samples.
    auto audited = w::World::restore("mixed-scale", site.profile, stage_snapshot);
    if (!audited) throw std::runtime_error("The multiline audit World did not restore.");
    for (int sample = 0; sample < 20; ++sample)
        if (audited->tick().error != w::TransactionError::none ||
            !w::validate(site.profile, audited->snapshot()))
            throw std::runtime_error("An accelerated multiline tick failed full historical validation.");
    if (audited->snapshot().state != live->snapshot().state ||
        audited->snapshot().revision != live->snapshot().revision)
        throw std::runtime_error("Timed and fully audited multiline ticks diverged.");
    if (line_count == 10) {
        const V::Object missing_drive{{"context", V("mixed-scale")},
            {"client", V("P-client")}, {"request", V("scale-audit-refusal")},
            {"actor", V("P")}, {"action", V("set_drive")},
            {"target", V("missing-wheel")}, {"generation", V(g::Integer{1})},
            {"enabled", V(false)}};
        const w::ObserveActor nearby = [](const std::string& actor)
                -> std::optional<factory::authority::ActorCut> {
            return factory::authority::ActorCut{actor, {0, 0, 0}, 1, true, 10000};
        };
        const auto refused = live->command({"P", "P-client"}, missing_drive, nearby);
        if (!refused.completed() || !refused.result ||
            std::get<bool>(refused.result->at("accepted").storage()))
            throw std::runtime_error("The audit refusal was not recorded exactly.");
        auto fresh_after_refusal = w::World::restore("mixed-scale", site.profile, live->snapshot());
        if (!fresh_after_refusal || live->tick().error != w::TransactionError::none ||
            fresh_after_refusal->tick().error != w::TransactionError::none ||
            live->snapshot().state != fresh_after_refusal->snapshot().state ||
            live->snapshot().revision != fresh_after_refusal->snapshot().revision ||
            !w::validate(site.profile, live->snapshot()))
            throw std::runtime_error("The post-refusal tick reused a stale historical proof.");
    }
    std::cout << "WORLD_PRODUCTIVE_LINES count=" << line_count
              << " components=" << site.snapshot.state.placed_components.size()
              << " records=" << site.snapshot.history.records.size()
              << " work=" << work_ids.size() << " build_ms=" << build_ms
              << " audited_commands=" << (audit_commands ? site.command_ms.size() : 0)
              << " command_tail_median_ms=" << tail_commands[tail_commands.size() / 2]
              << " command_tail_p95_ms=" << tail_commands[tail_commands.size() * 95 / 100]
              << " first_tick_ms=" << first_tick_ms
              << " tick_median_ms=" << ticks[10] << " tick_p95_ms=" << ticks[18]
              << " passed\n";
}

int main(int argc, char** argv) {
    w::Profile profile;
    w::State state;
    constexpr int collectors = 200;
    constexpr int presses = 100;
    int serial = 1;
    const auto add = [&](const std::string& name, m::Component kind, g::Point center) {
        state.placed_components.emplace(name, w::PlacedComponent{kind, center, serial++});
    };
    for (int index = 0; index < collectors; ++index) {
        const g::Integer x = index * 8;
        const auto name = "collector-" + std::to_string(index);
        profile.collector_faces.push_back({{x, 0, 0}, {-1, 0, 0}});
        add(name + "-frame", m::Component::wooden_frame, {x, 0, 0});
        add(name + "-mount", m::Component::tool_mount, {x - 1, 0, 0});
        add(name + "-edge", m::Component::cutting_edge, {x - 2, 0, 0});
        add(name + "-tray", m::Component::receiver_tray, {x, 0, 1});
        add(name + "-shaft", m::Component::wooden_shaft, {x + 1, 0, 0});
    }
    for (int index = 0; index < presses; ++index) {
        const g::Integer x = index * 8;
        const auto name = "press-" + std::to_string(index);
        add(name + "-frame", m::Component::wooden_frame, {x, 8, 16});
        add(name + "-anvil", m::Component::anvil, {x, 9, 16});
        add(name + "-ram", m::Component::ram_face, {x, 10, 16});
        add(name + "-guide", m::Component::sliding_guide, {x, 11, 16});
        add(name + "-mount", m::Component::tool_mount, {x, 12, 16});
        add(name + "-shaft", m::Component::wooden_shaft, {x + 1, 12, 16});
        add(name + "-cog", m::Component::wooden_cog, {x + 2, 12, 16});
    }
    profile.material = {1, 2, 2};
    profile.material.manual_ore = m::OreSite{"ore", {-3, 0, 0}};
    profile.actors = {"P"};
    profile.foundation_parts = 9;
    profile.starting_foundation_kits = {{"P", 0}};
    profile.landing_pod_center = g::Point{0, 0, 2000};
    w::State empty_site;
    empty_site.material.cargo.emplace("P", m::Cargo{});
    empty_site.kits.emplace("P", factory::stationary::Kit{});
    empty_site.foundation_kits.emplace("P", 0);
    empty_site.landing_pod = w::LandingPod{"landing-pod", *profile.landing_pod_center, 1};
    empty_site.fabrication_hub = w::FabricationHub{"pod-fabrication-hub",
        w::landing_hub_center(*profile.landing_pod_center), 1};
    empty_site.issued_entities = {{"landing-pod", 1}, {"pod-fabrication-hub", 1}};
    const auto deck = w::landing_deck_centers(*profile.landing_pod_center);
    for (std::size_t index = 0; index < deck.size(); ++index) {
        const auto id = "pod-floor-" + std::to_string(index);
        empty_site.foundations.emplace(id, w::Foundation{deck[index], 1});
        empty_site.issued_entities.emplace(id, 1);
    }
    if (!w::World::create("modular-scale-profile", profile, empty_site))
        throw std::runtime_error("The World refused a trusted site with 200 independent collector faces.");
    const auto derived = w::drive_power(profile, state);
    if (!derived.mechanical.accepted() ||
        derived.mechanical.motion.size() != collectors * 3 + presses * 3)
        throw std::runtime_error("The mixed modular graph did not preserve each distinct drive part.");

    if (argc > 1 && std::string(argv[1]) == "--benchmark") {
        std::vector<double> samples;
        samples.reserve(20);
        for (int sample = 0; sample < 20; ++sample) {
            const auto start = std::chrono::steady_clock::now();
            if (!w::drive_power(profile, state).mechanical.accepted())
                throw std::runtime_error("The measured modular graph was rejected.");
            samples.push_back(std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - start).count());
        }
        std::sort(samples.begin(), samples.end());
        std::cout << "WORLD_MODULAR_STAGE collectors=" << collectors
                  << " presses=" << presses << " parts=" << state.placed_components.size()
                  << " samples=" << samples.size() << " median_ms=" << samples[10]
                  << " p95_ms=" << samples[19] << '\n';
    }
    const std::string mode = argc > 1 ? argv[1] : "";
    if (mode == "--lines-10" || mode == "--lines-20" || mode == "--lines-40" ||
        mode == "--lines-80" || mode == "--lines-40-audit" || mode == "--lines-80-audit")
        productive_line_scale(mode == "--lines-10" ? 10 : mode == "--lines-20" ? 20 :
            mode == "--lines-40" || mode == "--lines-40-audit" ? 40 : 80,
            mode == "--lines-40-audit" || mode == "--lines-80-audit");
    else
        powered_cog_world(mode == "--benchmark" || mode == "--benchmark-sustained-400" ||
            mode == "--benchmark-sustained-1000", mode == "--benchmark-sustained-1000" ? 1000 : 400,
            mode == "--benchmark-sustained-400" || mode == "--benchmark-sustained-1000");
    std::cout << "WORLD_MODULAR_CHECK collectors=" << collectors
              << " presses=" << presses << " placed=" << state.placed_components.size()
              << " passed\n";
}
