#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};

template<class T> const T& field(const V& value, const char* name) {
    return std::get<T>(std::get<O>(value.storage()).at(name).storage());
}
bool accepted(const V& value) { return field<bool>(value, "accepted"); }
bool same(const V& left, const V& right) { return !factory::values::typed_difference(left, right); }
V child(const V& value, const char* name) { return std::get<O>(value.storage()).at(name); }
V state(const Host& host) { return child(child(host.checkpoint(), "world"), "state"); }
void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
O request(const char* action, const std::string& id, const char* actor = "P") {
    return {{"context", V("attachment-test")}, {"client", V(actor)},
        {"request", V(id)}, {"action", V(action)}};
}
O shaft(I x, I z, const char* axis, const char* id) {
    auto wire = request("place_shaft", id);
    wire.emplace("center", V(A{V(x), V(I{0}), V(z)}));
    wire.emplace("axis", V(axis)); wire.emplace("half_span", V(I{2}));
    return wire;
}
O span(const std::string& from, const std::string& to, const std::string& id, const char* actor = "P") {
    auto wire = request("place_belt_span", id, actor);
    wire.emplace("from", V(from)); wire.emplace("to", V(to));
    return wire;
}
O target(const char* action, const std::string& entity, const std::string& id) {
    auto wire = request(action, id); wire.emplace("entity", V(entity)); return wire;
}
void observe(Host& host, const char* actor, double x, double z, I epoch) {
    check(accepted(host.publish_actor(actor, {V(x), V(1.0), V(z)}, epoch)),
          "The synthetic actor observation is accepted.");
}
std::string place(Host& host, const O& wire) {
    const auto result = host.command("P", wire);
    check(accepted(result), "Construction " + field<std::string>(V(wire), "request") +
          " succeeds; reason=" + field<std::string>(result, "reason") + ".");
    return field<std::string>(result, "entity");
}
O low_site() {
    auto site = factory::godot_world::tests::flat_site();
    site.at("heights") = V(A{V(-1.0), V(-1.0), V(-1.0), V(-1.0)});
    return site;
}
V alter_last_target(V saved, bool coherent = false) {
    auto root = std::get<O>(saved.storage());
    auto world = field<O>(saved, "world");
    auto history = field<O>(V(world), "history");
    auto records = field<A>(V(history), "records");
    auto found = records.end();
    for (auto it = records.begin(); it != records.end(); ++it) {
        const auto intent = field<O>(*it, "intent");
        if (field<std::string>(V(intent), "request") == "belt") { found = it; break; }
    }
    check(found != records.end(), "The original span receipt is present.");
    auto record = std::get<O>(found->storage());
    auto result = field<O>(*found, "result");
    auto targets = field<A>(V(result), "targets");
    auto distances = field<A>(V(result), "distances_squared");
    check(targets.size() == 2 && distances.size() == 2, "Span placement records both endpoint reaches.");
    if (coherent) {
        auto center = field<A>(V(result), "last_center");
        auto point = std::get<A>(targets.back().storage());
        const auto position = field<A>(V(result), "actor_position");
        center[0] = V(std::get<I>(center[0].storage()) + 4);
        point[0] = V(std::get<double>(point[0].storage()) + 1.65);
        double squared{};
        for (std::size_t index = 0; index < 3; ++index) {
            const auto delta = std::get<double>(point[index].storage()) - std::get<double>(position[index].storage());
            squared += delta * delta;
        }
        result.at("last_center") = V(std::move(center));
        targets.back() = V(std::move(point));
        distances.back() = V(squared);
    } else {
        targets.back() = targets.front();
        distances.back() = distances.front();
    }
    result.at("targets") = V(std::move(targets));
    result.at("distances_squared") = V(std::move(distances));
    record.at("result") = V(std::move(result));
    *found = V(std::move(record));
    history.at("records") = V(std::move(records));
    world.at("history") = V(std::move(history));
    root.at("world") = V(std::move(world));
    return V(std::move(root));
}

V alter_selection_target(V saved) {
    auto root = std::get<O>(saved.storage());
    auto world = field<O>(saved, "world");
    auto history = field<O>(V(world), "history");
    auto records = field<A>(V(history), "records");
    auto selected = records.end(), built = records.end();
    for (auto it = records.begin(); it != records.end(); ++it) {
        const auto intent = field<O>(*it, "intent");
        const auto id = field<std::string>(V(intent), "request");
        if (id == "selection") selected = it;
        if (id == "selected-span") built = it;
    }
    check(selected != records.end() && built != records.end(), "Both selection and span receipts exist.");
    auto record = std::get<O>(selected->storage());
    auto result = field<O>(*selected, "result");
    result.at("targets") = child(child(*built, "result"), "targets");
    result.at("distances_squared") = child(child(*built, "result"), "distances_squared");
    record.at("result") = V(std::move(result));
    *selected = V(std::move(record));
    history.at("records") = V(std::move(records));
    world.at("history") = V(std::move(history));
    root.at("world") = V(std::move(world));
    return V(std::move(root));
}

void span_history_and_custody(bool travel_z, bool reversed) {
    Host host;
    const auto site = low_site();
    check(accepted(host.initialize("attachment-test", {"P", "Q"})) && accepted(host.configure_terrain(site)),
          "The Host starts with the finite starter kit and synthetic terrain.");
    const auto at = [&](const char* actor, double along, I epoch) {
        observe(host, actor, travel_z ? -1.65 : along, travel_z ? along : -1.65, epoch);
    };
    const auto* axis = travel_z ? "x" : "z";
    at("P", 0, 1);
    const auto first = place(host, shaft(0, 0, axis, "first"));
    at("P", 3.3, 2);
    const auto last = place(host, shaft(travel_z ? 0 : 8, travel_z ? 8 : 0, axis, "last"));
    at("P", 1.65, 3);
    at("Q", 1.65, 1);
    const auto& from = reversed ? last : first;
    const auto& to = reversed ? first : last;
    const auto before = state(host);
    const auto no_kit = host.command("Q", span(from, to, "no-kit", "Q"));
    check(!accepted(no_kit) && field<std::string>(no_kit, "reason") == "unavailable_part" && same(before, state(host)),
          "An actor cannot borrow the other actor's belt or alter the finite world; reason=" +
          field<std::string>(no_kit, "reason") + ".");
    at("P", 20, 4);
    const auto far_wire = span(from, to, "far-span");
    const auto far = host.command("P", far_wire);
    check(!accepted(far) && field<std::string>(far, "reason") == "out_of_reach" && same(before, state(host)),
          "A distant actor cannot construct a span or change custody.");
    at("P", 1.65, 5);
    const auto retry = host.command("P", far_wire);
    check(!accepted(retry) && field<bool>(retry, "duplicate") && same(before, state(host)),
          "Retry retains the original distant refusal after the actor moves near.");
    const auto wire = span(from, to, "belt");
    const auto belt = place(host, wire);
    const auto view = host.projection();
    check(field<I>(child(view, "parts"), "belt") == 1 && field<A>(view, "links").empty() &&
              field<std::string>(field<O>(view, "belt_spans").at(belt), "from") == from &&
              field<std::string>(field<O>(view, "belt_spans").at(belt), "to") == to,
          "One carried belt connects the ordered shaft endpoints without machine links.");
    auto saved = host.checkpoint();
    const auto forged = host.validate_checkpoint(alter_last_target(saved));
    check(!accepted(forged) && same(saved, host.checkpoint()),
          "A coherently forged endpoint reach is rejected without changing the live authority; reason=" +
          field<std::string>(forged, "reason") + ".");
    check(!accepted(host.validate_checkpoint(alter_last_target(saved, true))),
          "Changing both the reach point and the claimed center cannot move a live shaft in history.");
    check(accepted(host.command("P", target("remove_belt_span", belt, "remove-belt"))) &&
              field<I>(child(host.projection(), "parts"), "belt") == 2 &&
              field<O>(host.projection(), "belt_spans").empty(),
          "Removing the empty span returns exactly its belt and leaves the shafts.");
    saved = host.checkpoint();
    Host restored;
    check(accepted(restored.initialize("fresh-host", {"P", "Q"})) && accepted(restored.configure_terrain(site)) &&
              accepted(restored.restore_checkpoint(saved)) && same(saved, restored.checkpoint()),
          "A fresh Host restores finite custody and typed history exactly.");
    const auto old = restored.command("P", wire);
    check(accepted(old) && field<bool>(old, "duplicate") && field<std::string>(old, "entity") == belt &&
              field<O>(restored.projection(), "belt_spans").empty(),
          "Historical replay names the removed span without reconstructing it.");
    observe(restored, "P", travel_z ? -1.65 : 1.65, travel_z ? 1.65 : -1.65, 1);
    const auto replacement = place(restored, span(from, to, "replacement"));
    check(replacement != belt && field<I>(child(restored.projection(), "parts"), "belt") == 1 &&
              accepted(restored.validate_checkpoint(restored.checkpoint())),
          "Reconstruction consumes one belt, creates a fresh identity and retains a valid checkpoint.");
    check(accepted(restored.command("P", target("remove_belt_span", replacement, "remove-replacement"))) &&
              accepted(restored.command("P", target("remove", first, "remove-first"))) &&
              accepted(restored.command("P", target("remove", last, "remove-last"))),
          "The span and both endpoint shafts can be reclaimed.");
    const auto removed = restored.checkpoint();
    check(accepted(restored.validate_checkpoint(removed)) &&
              !accepted(restored.validate_checkpoint(alter_last_target(removed, true))) && same(removed, restored.checkpoint()),
          "Historical placement still binds both removed shafts without mutating the live World.");
}

void selected_history() {
    Host host;
    check(accepted(host.initialize("attachment-test", {"P"})) && accepted(host.configure_terrain(low_site())),
          "The selected-span Host binds its site.");
    observe(host, "P", 0, -1.65, 1);
    const auto first = place(host, shaft(0, 0, "z", "selected-first"));
    observe(host, "P", 3.3, -1.65, 2);
    const auto last = place(host, shaft(8, 0, "z", "selected-last"));
    observe(host, "P", 1.65, -1.65, 3);
    check(accepted(host.command("P", target("select_belt_shaft", first, "selection"))),
          "The first shaft selection is recorded at the same cut as the second endpoint.");
    auto install = span(first, last, "selected-span");
    install.at("action") = V("place_selected_belt_span");
    install.emplace("selection", V("selection"));
    const auto belt = place(host, install);
    const auto live = host.checkpoint();
    check(accepted(host.validate_checkpoint(live)) && !accepted(host.validate_checkpoint(alter_selection_target(live))),
          "A selected span rejects a selection receipt retargeted to the other reachable shaft.");
    check(accepted(host.command("P", target("remove_belt_span", belt, "selected-remove"))) &&
              accepted(host.command("P", target("remove", first, "selected-remove-first"))) &&
              accepted(host.command("P", target("remove", last, "selected-remove-last"))),
          "The selected span and both endpoints can be reclaimed.");
    const auto removed = host.checkpoint();
    check(accepted(host.validate_checkpoint(removed)) && !accepted(host.validate_checkpoint(alter_selection_target(removed))) &&
              same(removed, host.checkpoint()),
          "Selection history remains bound to its original shaft after both endpoints are removed.");
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc > 2 || (argc == 2 && std::string(argv[1]) != "--axis-placement-only"))
            throw std::runtime_error("Expected no arguments or --axis-placement-only.");
        for (bool travel_z : {false, true}) for (bool reversed : {false, true})
            span_history_and_custody(travel_z, reversed);
        selected_history();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_shaft_span_attachment_unit\",\"checks\":"
                  << checks << ",\"engine_calls\":0,\"physical_observations\":\"synthetic\"}\n";
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << "Check " << checks << ": " << failure.what() << '\n';
        return 1;
    }
}
