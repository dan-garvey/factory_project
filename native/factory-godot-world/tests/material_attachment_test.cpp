#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
namespace w = factory::world;
namespace s = factory::stationary;
namespace m = factory::mechanics;
int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const V& value, const char* name) {
    return std::get<T>(std::get<O>(value.storage()).at(name).storage());
}

bool accepted(const V& value) { return field<bool>(value, "accepted"); }
bool same(const V& left, const V& right) { return !factory::values::typed_difference(left, right); }
V child(const V& value, const char* name) { return std::get<O>(value.storage()).at(name); }
V state(const Host& host) { return child(child(host.checkpoint(), "world"), "state"); }

O request(const char* action, const std::string& id, const char* actor = "P") {
    return {{"context", V("attachment-test")}, {"client", V(actor)},
        {"request", V(id)}, {"action", V(action)}};
}

O placement(const char* kind, I x, I z, const std::string& id, const char* actor = "P") {
    auto wire = request("place", id, actor);
    wire.emplace("kind", V(kind));
    wire.emplace("cell", V(A{V(x), V(z)}));
    return wire;
}

void initialize(Host& host) {
    check(accepted(host.initialize("attachment-test", {"P", "Q"})), "The finite native Host initializes.");
    check(accepted(host.configure_terrain(factory::godot_world::tests::flat_site())), "The test binds explicit synthetic terrain.");
    check(accepted(host.publish_actor("P", {V(1.65), V(1.0), V(1.65)}, 1)),
          "The fixture supplies its disclosed synthetic observation.");
}

std::string place(Host& host, const char* kind, I x, I z, const std::string& id) {
    const auto reply = host.command("P", placement(kind, x, z, id));
    check(accepted(reply), "Ordinary material-machine placement succeeds.");
    return field<std::string>(reply, "entity");
}

void exact_links(const Host& host, const std::string& collector, const std::string& belt,
                 const std::string& press) {
    const auto view = host.projection();
    check(same(child(view, "links"), V(A{V(A{V(collector), V(belt)}), V(A{V(belt), V(press)})})) ||
          same(child(view, "links"), V(A{V(A{V(belt), V(press)}), V(A{V(collector), V(belt)})})),
          "The exact directed material path is attached without Connect commands.");
    check(field<A>(view, "drive_links").empty() && !field<bool>(view, "powered"),
          "Material attachment supplies no mechanical drive or power.");
    const auto stock = child(view, "stock");
    check(same(stock, V(O{{"source", V(I{4096})}, {"collector", V(I{0})}, {"belt", V(I{0})},
        {"input", V(I{0})}, {"held", V(I{0})}, {"output", V(I{0})}, {"player", V(I{0})}})),
        "Construction does not step, refill or move the original finite deposit.");
}

void every_build_order() {
    std::array<int, 3> order{0, 1, 2};
    constexpr const char* kinds[] = {"collector", "belt", "processor"};
    do {
        Host host;
        initialize(host);
        std::array<std::string, 3> ids;
        for (const auto index : order) ids[index] = place(host, kinds[index], index, 0, kinds[index]);
        exact_links(host, ids[0], ids[1], ids[2]);
        check(field<I>(host.projection(), "order") == 3, "Three placements need exactly three material requests.");
        const auto parts = child(host.projection(), "parts");
        check(field<I>(parts, "collector") == 0 && field<I>(parts, "belt") == 1 &&
              field<I>(parts, "processor") == 0 && field<I>(parts, "shaft") == 8,
              "The three placements consume their original kit and no shafts.");
        check(accepted(host.validate_checkpoint(host.checkpoint())), "Every construction order produces a valid typed checkpoint.");
    } while (std::next_permutation(order.begin(), order.end()));
}

void geometry_and_empty_kit() {
    for (const auto reverse : {false, true}) {
        Host host;
        initialize(host);
        (void)place(host, "collector", 0, 0, "collector");
        check(accepted(host.publish_actor("P", reverse ? A{V(-1.65), V(1.0), V(1.65)} :
                                                        A{V(1.65), V(1.0), V(3.3)}, 2)),
              "The fixture cut remains near the tested construction and outside its occupancy.");
        if (reverse) {
            (void)place(host, "belt", -1, 0, "belt");
            (void)place(host, "processor", -2, 0, "press");
        } else {
            (void)place(host, "belt", 1, 1, "belt");
            (void)place(host, "processor", 2, 0, "press");
        }
        check(field<A>(host.projection(), "links").empty(), "Reverse and misaligned ports do not attach by proximity.");
    }
    Host gap;
    initialize(gap);
    (void)place(gap, "collector", 0, 0, "collector");
    const auto belt = place(gap, "belt", 2, 0, "belt");
    check(accepted(gap.publish_actor("P", {V(3.3), V(1.0), V(1.65)}, 2)), "The fixture moves its synthetic observation before a farther build.");
    const auto press = place(gap, "processor", 3, 0, "press");
    check(same(child(gap.projection(), "links"), V(A{V(A{V(belt), V(press)})})),
          "An adjacent downstream port attaches while a collector gap stays disconnected.");
    Host empty;
    initialize(empty);
    check(accepted(empty.publish_actor("Q", {V(1.65), V(1.0), V(1.65)}, 1)), "The second fixture actor is ready.");
    const auto before = state(empty);
    check(!accepted(empty.command("Q", placement("belt", 1, 0, "empty-kit", "Q"))),
          "A fresh namespace cannot borrow another actor's belt.");
    check(same(before, state(empty)), "Refusing an empty kit leaves all custody and topology exact.");
}

void atomic_reach_and_retry() {
    Host host;
    initialize(host);
    const auto collector = place(host, "collector", 0, 0, "collector");
    const auto press = place(host, "processor", 2, 0, "press");
    check(accepted(host.publish_actor("P", {V(-1.0), V(1.0), V(1.65)}, 2)), "The new fixture cut reaches the belt but not the press.");
    const auto original = state(host);
    const auto wire = placement("belt", 1, 0, "far-attachment");
    const auto refused = host.command("P", wire);
    check(!accepted(refused) && field<std::string>(refused, "reason") == "out_of_reach",
          "Attachment checks every existing endpoint rather than only the new belt.");
    check(field<A>(refused, "targets").size() == 3, "The original refusal retains all three canonical targets.");
    check(same(original, state(host)), "One unreachable endpoint refuses the complete placement and kit commit.");
    const auto order = field<I>(host.projection(), "order");
    check(accepted(host.publish_actor("P", {V(1.65), V(1.0), V(1.65)}, 3)), "A later fixture observation is near both ports.");
    const auto retry = host.command("P", wire);
    check(!accepted(retry) && field<bool>(retry, "duplicate") && field<I>(retry, "native_epoch") == 2 &&
          field<I>(host.projection(), "order") == order && same(original, state(host)),
          "Exact retry preserves the original refusal and cut without re-admission.");
    const auto belt = place(host, "belt", 1, 0, "fresh-attachment");
    exact_links(host, collector, belt, press);
    const auto committed = state(host);
    check(!accepted(host.command("P", placement("belt", 1, 0, "occupied"))), "An occupied attachment refuses.");
    check(same(committed, state(host)), "An occupied refusal cannot partially consume kit or edit links.");
}

V alter_last_target(V saved, const A& target) {
    auto root = std::get<O>(saved.storage());
    auto world = field<O>(saved, "world");
    auto history = field<O>(V(world), "history");
    auto records = field<A>(V(history), "records");
    auto record = std::get<O>(records.back().storage());
    auto result = field<O>(records.back(), "result");
    auto targets = field<A>(V(result), "targets");
    auto distances = field<A>(V(result), "distances_squared");
    targets.back() = V(target);
    const auto position = field<A>(V(result), "actor_position");
    double distance{};
    for (std::size_t index = 0; index < 3; ++index) {
        const auto delta = std::get<double>(target[index].storage()) - std::get<double>(position[index].storage());
        distance += delta * delta;
    }
    distances.back() = V(distance);
    result.at("targets") = V(std::move(targets));
    result.at("distances_squared") = V(std::move(distances));
    record.at("result") = V(std::move(result));
    records.back() = V(std::move(record));
    history.at("records") = V(std::move(records));
    world.at("history") = V(std::move(history));
    root.at("world") = V(std::move(world));
    return V(std::move(root));
}

void checkpoint_and_removed_identity() {
    Host host;
    initialize(host);
    const auto collector = place(host, "collector", 0, 0, "collector");
    const auto press = place(host, "processor", 2, 0, "press");
    const auto old_belt_wire = placement("belt", 1, 0, "belt");
    const auto belt = place(host, "belt", 1, 0, "belt");
    auto saved = host.checkpoint();
    for (const auto& bad : {A{V(1.65), V(0.5), V(0.0)}, A{V(3.3), V(0.6), V(0.0)},
                            A{V(1.65), V(0.5), V(1.65)}}) {
        check(!accepted(host.validate_checkpoint(alter_last_target(saved, bad))),
              "Coherently altered reach facts cannot invent a duplicate, elevated or diagonal port.");
        check(same(saved, host.checkpoint()), "Refused historical validation cannot edit the owner.");
    }
    auto removal = request("remove", "remove-belt");
    removal.emplace("entity", V(belt));
    check(accepted(host.command("P", removal)), "An empty attached belt can be removed without a separate disconnect.");
    check(field<A>(host.projection(), "links").empty() && field<I>(child(host.projection(), "parts"), "belt") == 2,
          "Removal atomically removes both old links and refunds exactly one belt.");
    saved = host.checkpoint();
    Host fresh;
    check(accepted(fresh.initialize("fresh-host", {"P", "Q"})), "A separate typed Host fixture initializes.");
    check(accepted(fresh.configure_terrain(factory::godot_world::tests::flat_site())), "The restored fixture binds the same explicit terrain.");
    check(accepted(fresh.restore_checkpoint(saved)) && same(saved, fresh.checkpoint()),
          "Typed restoration preserves all old topology, kit, history and saved positions.");
    const auto retry = fresh.command("P", old_belt_wire);
    check(accepted(retry) && field<bool>(retry, "duplicate") && field<std::string>(retry, "entity") == belt &&
          field<A>(fresh.projection(), "links").empty(),
          "An old placement receipt names its removed belt without reconstructing its topology.");
    check(accepted(fresh.publish_actor("P", {V(1.65), V(1.0), V(1.65)}, 1)), "The restored fixture actor publishes a new observation.");
    const auto replacement = place(fresh, "belt", 1, 0, "new-belt");
    check(replacement != belt, "Reconstruction allocates a fresh identity.");
    exact_links(fresh, collector, replacement, press);
    const auto old_records = field<A>(child(child(saved, "world"), "history"), "records");
    const auto new_records = field<A>(child(child(fresh.checkpoint(), "world"), "history"), "records");
    check(new_records.size() == old_records.size() + 1, "Reconstruction adds one request after the restored history.");
    for (std::size_t index = 0; index < old_records.size(); ++index)
        check(same(old_records[index], new_records[index]), "Every original intent and outcome stays typed and unchanged.");
}

void height_and_legacy_history() {
    w::Profile profile;
    profile.material = {1, 1, 2};
    profile.initial_units = 16;
    profile.actors = {"P"};
    profile.build_reach = 10.0;
    profile.finite_parts = {{{s::Role::collector, 0, 0}, 1}, {{s::Role::belt, 0, 0}, 1}, {{s::Role::processor, 0, 0}, 1}};
    w::State seed;
    seed.material.initial_units = 16;
    seed.material.stock.source = 16;
    seed.material.cargo = {{"P", {}}};
    seed.kits = {{"P", {{{s::Role::belt, 0, 0}, 1}}}};
    seed.topology.parts = {{{"collector", m::Kind::hub, {0, 0, 0}, m::Axis::x, 0, 0}, 1, s::Role::collector},
                           {{"press", m::Kind::hub, {8, 4, 0}, m::Axis::x, 0, 0}, 1, s::Role::processor}};
    seed.issued_entities = {{"collector", 1}, {"press", 1}};
    const auto observe = [](const std::string& actor) {
        return std::optional<factory::authority::ActorCut>{{actor, {2.0, 1.0, 1.0}, 1, true, 10.0}};
    };
    O command{{"context", V("core-attachment")}, {"client", V("P")}, {"actor", V("P")},
        {"request", V("belt")}, {"action", V("place_connected")}, {"role", V("belt")},
        {"center", V(A{V(I{4}), V(I{0}), V(I{0})})}, {"axis", V("z")}, {"teeth", V(I{0})}, {"half_span", V(I{0})}};
    auto owner = w::World::create("core-attachment", profile, seed);
    check(owner != nullptr, "The native fixture has a valid elevated downstream machine.");
    const auto attached = owner->command({"P", "P"}, command, observe);
    check(attached.result && field<bool>(V(*attached.result), "accepted") &&
          owner->snapshot().state.topology.material_links.size() == 1,
          "An elevated press never attaches despite matching horizontal coordinates.");
    command.at("action") = V("place");
    owner = w::World::create("core-attachment", profile, seed);
    const auto old = owner->command({"P", "P"}, command, observe);
    check(old.result && field<bool>(V(*old.result), "accepted") && owner->snapshot().state.topology.material_links.empty(),
          "The historical placement operation retains its original behavior.");
    auto snapshot = owner->snapshot();
    check(w::World::restore("core-attachment", profile, snapshot) != nullptr, "Old one-target placement history still restores.");
    auto& result = snapshot.history.records.back().result;
    auto targets = field<A>(V(result), "targets");
    auto distances = field<A>(V(result), "distances_squared");
    targets.emplace_back(A{V(0.0), V(0.0), V(0.0)});
    distances.emplace_back(6.0);
    result.at("targets") = V(std::move(targets));
    result.at("distances_squared") = V(std::move(distances));
    check(w::World::restore("core-attachment", profile, snapshot) == nullptr,
          "Adding connected placement does not weaken the old exact one-target history schema.");
}

void oriented_wire_join() {
    for (const auto* axis : std::array<const char*, 2>{"z", nullptr}) {
        Host host;
        initialize(host);
        const auto make_wire = [&](const char* kind, I x) {
            auto wire = placement(kind, x, 0, kind);
            if (axis) wire.emplace("axis", V(axis));
            return wire;
        };
        const auto collector = host.command("P", make_wire("collector", 0));
        const auto press = host.command("P", make_wire("processor", 2));
        const auto belt_wire = make_wire("belt", 1);
        const auto belt = host.command("P", belt_wire);
        check(accepted(collector) && accepted(press) && accepted(belt),
              "The perpendicular axis and its omitted default preserve ordinary placement.");
        exact_links(host, field<std::string>(collector, "entity"), field<std::string>(belt, "entity"),
                    field<std::string>(press, "entity"));
        check(field<A>(belt, "targets").size() == 3,
              "The oriented belt still admits its new location and both original material endpoints.");
        const auto saved = host.checkpoint();
        const auto records = field<A>(child(child(saved, "world"), "history"), "records");
        check(field<std::string>(child(records.back(), "intent"), "axis") == "z" &&
              field<std::string>(child(records.back(), "intent"), "action") == "place_connected" &&
              same(child(child(records.back(), "intent"), "wire"), V(belt_wire)),
              "One connected-placement record preserves the exact incoming axis and original wire.");
        check(accepted(host.validate_checkpoint(saved)), "The joined Host validates its typed oriented history.");
        Host fresh;
        check(accepted(fresh.initialize("fresh", {"P", "Q"})) &&
                  accepted(fresh.configure_terrain(factory::godot_world::tests::flat_site())) &&
                  accepted(fresh.restore_checkpoint(saved)),
              "A fresh native Host restores the joined checkpoint before native readiness.");
        check(same(saved, fresh.checkpoint()), "Typed state and all original records restore exactly.");
        const auto retry = fresh.command("P", belt_wire);
        check(accepted(retry) && field<bool>(retry, "duplicate") &&
              field<std::string>(retry, "entity") == field<std::string>(belt, "entity") &&
              same(saved, fresh.checkpoint()), "Historical replay precedes new native registration.");
        const auto* other_axis = axis && std::string(axis) == "y" ? "z" : "y";
        auto changed_wire = belt_wire;
        changed_wire.insert_or_assign("axis", V(other_axis));
        check(field<std::string>(fresh.command("P", changed_wire), "reason") == "request_reuse" &&
              same(saved, fresh.checkpoint()), "An old request cannot silently change its axis.");
        auto root = std::get<O>(saved.storage());
        auto world = std::get<O>(root.at("world").storage());
        auto history = std::get<O>(world.at("history").storage());
        auto rows = std::get<A>(history.at("records").storage());
        auto record = std::get<O>(rows.back().storage());
        auto intent = std::get<O>(record.at("intent").storage());
        auto altered_wire = std::get<O>(intent.at("wire").storage());
        altered_wire.insert_or_assign("axis", V(other_axis));
        intent.at("wire") = V(std::move(altered_wire));
        record.at("intent") = V(std::move(intent));
        rows.back() = V(std::move(record));
        history.at("records") = V(std::move(rows));
        world.at("history") = V(std::move(history));
        root.at("world") = V(std::move(world));
        check(!accepted(fresh.validate_checkpoint(V(std::move(root)))) && same(saved, fresh.checkpoint()),
              "Import rejects an altered original axis without changing live custody or history.");
    }
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 1) {
            every_build_order();
            geometry_and_empty_kit();
            atomic_reach_and_retry();
            checkpoint_and_removed_identity();
            height_and_legacy_history();
        } else if (argc != 2 || std::string(argv[1]) != "--axis-placement-only") {
            throw std::runtime_error("Expected no arguments or --axis-placement-only.");
        }
        oriented_wire_join();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_material_attachment_unit\",\"checks\":"
                  << checks << ",\"engine_calls\":0,\"physical_observations\":\"synthetic\"}\n";
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}
