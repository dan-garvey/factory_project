#include "factory/godot_world.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using Host = factory::godot_world::Host;

int checks{};
void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class T> const T& field(const Value& value, const char* name) {
    return std::get<T>(std::get<Object>(value.storage()).at(name).storage());
}
bool accepted(const Value& value) { return field<bool>(value, "accepted"); }
void near(double actual, double expected, const char* message) {
    check(std::abs(actual - expected) < 1e-9, message);
}
Object request(const char* action, const char* id) {
    return {{"context", Value("stand-test")}, {"client", Value("P")},
            {"request", Value(id)}, {"action", Value(action)}};
}
Object shaft(Integer x, Integer y, Integer z, const char* id) {
    auto wire = request("place_shaft", id);
    wire.emplace("center", Value(Array{Value(x), Value(y), Value(z)}));
    wire.emplace("axis", Value("z"));
    wire.emplace("half_span", Value(Integer{2}));
    return wire;
}
Object gear(Integer x, Integer y, Integer z, const char* id) {
    auto wire = request("place_gear", id);
    wire.emplace("center", Value(Array{Value(x), Value(y), Value(z)}));
    wire.emplace("axis", Value("y"));
    wire.emplace("teeth", Value(Integer{2}));
    return wire;
}
void actor(Host& host, double x, double y, double z, Integer epoch) {
    check(accepted(host.publish_actor("P", {Value(x), Value(y), Value(z)}, epoch)),
          "The disclosed synthetic actor pose is accepted.");
}
Object support(const Host& host, const std::string& id) {
    return field<Object>(Value(field<Object>(host.projection(), "transmission_parts").at(id)), "support");
}
void stand_seat_and_recovery() {
    Host host;
    check(accepted(host.initialize("stand-test", {"P"})) &&
          accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),
          "A native Host binds the synthetic flat site.");
    actor(host, 1.65, 1.0, 0.0, 1);
    auto base = request("place_foundation", "base");
    base.emplace("cell", Value(Array{Value(Integer{1}), Value(Integer{0})}));
    base.emplace("level", Value(Integer{0}));
    const auto base_reply = host.command("P", base);
    check(accepted(base_reply), "The foundation is placed beneath the proposed bearing.");
    const auto placed = host.command("P", shaft(4, 4, 0, "shaft"));
    check(accepted(placed), "A shaft is admitted above the foundation.");
    const auto id = field<std::string>(placed, "entity");
    const auto with_base = support(host, id);
    const auto& foot = std::get<Array>(with_base.at("foot").storage());
    const auto& bearing = std::get<Array>(with_base.at("bearing").storage());
    near(std::get<double>(foot[0].storage()), 1.65, "The foot stays below its shaft center.");
    near(std::get<double>(foot[1].storage()), 0.0, "The native stand seats on the foundation top.");
    near(std::get<double>(foot[2].storage()), 0.35, "A horizontal axle has an outboard bearing.");
    check(std::get<double>(bearing[1].storage()) > std::get<double>(foot[1].storage()),
          "The bearing rises above the confirmed support seat.");
    const auto saved = host.checkpoint();
    check(accepted(host.validate_checkpoint(saved)), "The supported shaft checkpoint validates.");
    Host fresh;
    check(accepted(fresh.initialize("fresh", {"P"})) &&
          accepted(fresh.configure_terrain(factory::godot_world::tests::flat_site())) &&
          accepted(fresh.restore_checkpoint(saved)), "A fresh native Host restores the supported shaft.");
    check(!factory::values::typed_difference(saved, fresh.checkpoint()),
          "The stand adds no second saved state or changes the original checkpoint.");
    const auto restored = support(fresh, id);
    near(std::get<double>(std::get<Array>(restored.at("foot").storage())[1].storage()), 0.0,
         "The restored projection derives the same foundation seat.");
    actor(host, 0.0, 1.0, -1.65, 2);
    const auto placed_gear = host.command("P", gear(0, 4, 4, "gear"));
    check(accepted(placed_gear), "A horizontal cog has its own native-confirmed bearing seat: " +
          field<std::string>(placed_gear, "reason"));
    const auto gear_id = field<std::string>(placed_gear, "entity");
    const auto gear_support = support(host, gear_id);
    near(std::get<double>(std::get<Array>(gear_support.at("foot").storage())[0].storage()), 0.24,
         "The cog support stands outboard of its vertical axle.");
    auto remove = request("remove", "remove-base");
    remove.emplace("entity", Value(field<std::string>(base_reply, "entity")));
    check(accepted(host.command("P", remove)), "Removing a foundation retains the shaft and its finite kit.");
    const auto grounded = support(host, id);
    near(std::get<double>(std::get<Array>(grounded.at("foot").storage())[1].storage()), -0.02,
         "After foundation removal the stand reaches the real ground.");
    check(accepted(host.validate_checkpoint(host.checkpoint())),
          "The ground-supported shaft remains restorable after removal.");
    actor(host, 0.0, 1.0, -1.65, 3);
    auto raised = request("place_foundation", "raised-seat");
    raised.emplace("cell", Value(Array{Value(Integer{1}), Value(Integer{0})}));
    raised.emplace("level", Value(Integer{4}));
    const auto raised_reply = host.command("P", raised);
    check(accepted(raised_reply), "A later foundation can lift the same fixed bearing seat.");
    const auto raised_support = support(host, id);
    near(std::get<double>(std::get<Array>(raised_support.at("foot").storage())[1].storage()), 1.65,
         "Post-placement foundation edits update the confirmed support foot.");
    auto remove_raised = request("remove", "remove-raised-seat");
    remove_raised.emplace("entity", Value(field<std::string>(raised_reply, "entity")));
    const auto raised_removal = host.command("P", remove_raised);
    check(!accepted(raised_removal) && field<std::string>(raised_removal, "reason") == "foundation_in_use",
          "The World retains its foundation dependency while the shaft occupies that cell.");
    auto remove_shaft = request("remove", "remove-shaft");
    remove_shaft.emplace("entity", Value(id));
    actor(host, 1.65, 1.0, 0.0, 4);
    check(accepted(host.command("P", remove_shaft)), "The supported shaft can be reclaimed.");
    check(!field<Object>(host.projection(), "transmission_parts").contains(id),
          "Removing the shaft also removes its projected fixed support.");
    auto remove_after_shaft = request("remove", "remove-raised-after-shaft");
    remove_after_shaft.emplace("entity", Value(field<std::string>(raised_reply, "entity")));
    check(accepted(host.command("P", remove_after_shaft)),
          "The raised foundation can be reclaimed after its shaft is removed.");
}
void blocked_or_excessive_stand() {
    auto site = factory::godot_world::tests::flat_site();
    site.at("obstacles") = Value(Array{Value(Array{
        Value(Array{Value(1.5), Value(0.0), Value(0.25)}),
        Value(Array{Value(1.8), Value(1.0), Value(0.5)})})});
    Host blocked;
    check(accepted(blocked.initialize("stand-test", {"P"})) &&
          accepted(blocked.configure_terrain(site)), "The ground-connected rock binds.");
    actor(blocked, 1.65, 1.0, 0.0, 1);
    const auto rock_seated = blocked.command("P", shaft(4, 4, 0, "rock-seated"));
    check(accepted(rock_seated), "A clear shaft can stand on the rock below its axle.");
    const auto rock_id = field<std::string>(rock_seated, "entity");
    const auto rock_support = support(blocked, rock_id);
    near(std::get<double>(std::get<Array>(rock_support.at("foot").storage())[1].storage()), 1.0,
         "The native stand rests on the rock top instead of passing through it.");
    check(accepted(blocked.validate_checkpoint(blocked.checkpoint())),
          "A shaft seated on a rock remains valid on checkpoint review.");
    Host clear;
    check(accepted(clear.initialize("stand-test", {"P"})) &&
          accepted(clear.configure_terrain(factory::godot_world::tests::flat_site())),
          "The unobstructed control binds the same synthetic ground.");
    actor(clear, 1.65, 1.0, 0.0, 1);
    const auto clear_shaft = clear.command("P", shaft(4, 4, 0, "clear"));
    check(accepted(clear_shaft),
          "The same axle is admitted without the post obstruction.");
    const auto saved = clear.checkpoint();
    Host changed_site;
    check(accepted(changed_site.initialize("fresh", {"P"})) &&
          accepted(changed_site.configure_terrain(site)),
          "A fresh Host binds the obstructed terrain fixture.");
    const auto reseated = changed_site.restore_checkpoint(saved);
    check(accepted(reseated), "Restoring against a new rock derives the higher valid seat.");
    const auto restored_support = support(changed_site, field<std::string>(clear_shaft, "entity"));
    near(std::get<double>(std::get<Array>(restored_support.at("foot").storage())[1].storage()), 1.0,
         "The restored stand sits on the new rock.");
    auto axle_site = site;
    axle_site.at("obstacles") = Value(Array{Value(Array{
        Value(Array{Value(1.5), Value(2.3), Value(0.25)}),
        Value(Array{Value(1.8), Value(2.6), Value(0.5)})})});
    Host axle_blocked;
    check(accepted(axle_blocked.initialize("stand-test", {"P"})) &&
          accepted(axle_blocked.configure_terrain(axle_site)), "The axle-intersecting rock binds.");
    actor(axle_blocked, 1.65, 1.0, 0.0, 1);
    const auto refused = axle_blocked.command("P", shaft(4, 4, 0, "axle-blocked"));
    check(!accepted(refused) && field<std::string>(refused, "reason") == "site_occupied",
          "A rock actually intersecting the shaft axle still refuses placement.");
    auto floating_site = site;
    floating_site.at("obstacles") = Value(Array{Value(Array{
        Value(Array{Value(1.5), Value(0.8), Value(0.25)}),
        Value(Array{Value(1.8), Value(1.0), Value(0.5)})})});
    Host floating;
    check(accepted(floating.initialize("stand-test", {"P"})) &&
          accepted(floating.configure_terrain(floating_site)), "The elevated obstruction binds.");
    actor(floating, 1.65, 1.0, 0.0, 1);
    const auto floating_refusal = floating.command("P", shaft(4, 4, 0, "floating-blocked"));
    check(!accepted(floating_refusal) && field<std::string>(floating_refusal, "reason") == "site_occupied",
          "A floating obstruction cannot become a stand seat above an empty gap.");
    Host tall;
    check(accepted(tall.initialize("stand-test", {"P"})) &&
          accepted(tall.configure_terrain(factory::godot_world::tests::flat_site())),
          "A separate native Host binds flat ground.");
    actor(tall, 0.0, 10.5, 0.0, 1);
    const auto unsupported = tall.command("P", gear(0, 24, 0, "too-tall"));
    check(!accepted(unsupported) && field<std::string>(unsupported, "reason") == "support_required",
          "An unbraced cog beyond the stand height refuses without using a gear.");
    Host overhead;
    check(accepted(overhead.initialize("stand-test", {"P"})) &&
          accepted(overhead.configure_terrain(factory::godot_world::tests::flat_site())),
          "The overhead-foundation control binds real ground.");
    actor(overhead, 0.0, 1.0, -1.65, 1);
    auto high_base = request("place_foundation", "high-base");
    high_base.emplace("cell", Value(Array{Value(Integer{0}), Value(Integer{0})}));
    high_base.emplace("level", Value(Integer{8}));
    check(accepted(overhead.command("P", high_base)), "A high foundation can exist above a free lower worksite.");
    const auto hanging = overhead.command("P", gear(0, 0, 0, "hanging"));
    check(!accepted(hanging) && field<std::string>(hanging, "reason") == "support_required",
          "A foundation above the axle cannot become its downward load-bearing seat.");
}
void foundation_dependency() {
    auto deep_site = factory::godot_world::tests::flat_site();
    deep_site.at("heights") = Value(Array{Value(-10.0), Value(-10.0), Value(-10.0), Value(-10.0)});
    Host host;
    check(accepted(host.initialize("stand-test", {"P"})) && accepted(host.configure_terrain(deep_site)),
          "The deep terrain fixture binds without redefining the world grid.");
    actor(host, 1.65, 1.0, 0.0, 1);
    auto foundation = request("place_foundation", "deep-base");
    foundation.emplace("cell", Value(Array{Value(Integer{1}), Value(Integer{0})}));
    foundation.emplace("level", Value(Integer{0}));
    const auto base = host.command("P", foundation);
    check(accepted(base), "A constructed foundation can seat a shaft above distant terrain.");
    const auto placed = host.command("P", shaft(4, 4, 0, "supported-deep"));
    check(accepted(placed), "The finite shaft uses its placed foundation seat.");
    auto remove = request("remove", "remove-deep-base");
    remove.emplace("entity", Value(field<std::string>(base, "entity")));
    const auto refusal = host.command("P", remove);
    check(!accepted(refusal) && field<std::string>(refusal, "reason") == "support_required",
          "The only foundation cannot be removed while its shaft exceeds the ground stand span.");
    const auto foot = support(host, field<std::string>(placed, "entity"));
    near(std::get<double>(std::get<Array>(foot.at("foot").storage())[1].storage()), 0.0,
         "A refused removal leaves the original bearing seat unchanged.");
    check(accepted(host.validate_checkpoint(host.checkpoint())),
          "The retained foundation, shaft and refusal history remain restorable.");
}
} // namespace

int main() {
    try {
        stand_seat_and_recovery();
        blocked_or_excessive_stand();
        foundation_dependency();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"native_transmission_support\",\"checks\":"
                  << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Check " << checks << ": " << error.what() << '\n';
        return 1;
    }
}
