#include "factory/opening_engineering.hpp"

#include <iostream>
#include <limits>
#include <stdexcept>

namespace e = factory::opening_engineering;
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class T> const T& field(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}

void content_contract() {
    const auto view = e::format_progress({}, "P");
    check(field<I>(view, "schema") == 1 && field<std::string>(view, "format") == "factory-opening-engineering",
          "The payload has its own versioned view format, separate from a World checkpoint.");
    const auto& cell = field<A>(view, "wheel_cell");
    check(cell.size() == 2 && std::get<I>(cell[0].storage()) == -1 && std::get<I>(cell[1].storage()) == 0,
          "The published upstream target differs from the ordinary row-1 starter line.");
    check(field<I>(view, "first_target") == 4 && field<I>(view, "target") == 8,
          "Both actual inventory thresholds remain exact native integers.");
    check(field<std::string>(view, "brief") == e::definition().brief &&
          field<std::string>(view, "relocate_hint") == e::definition().relocate_hint &&
          field<std::string>(view, "gear_hint") == e::definition().gear_hint,
          "The view receives existing content, rather than a second copy of its rules or text.");
}

void scalar_and_phase_contract() {
    // Invented records exercise only formatting, not material creation or new
    // native runtime outcomes. Original construction evidence remains cfd263a.
    const e::Progress large{e::Phase::ready, std::numeric_limits<I>::max(), 2, 3, true, true};
    const auto view = e::format_progress(large, "Q");
    check(field<I>(view, "products") == std::numeric_limits<I>::max(), "No double/JSON conversion can round a native integer count.");
    check(field<std::string>(view, "actor") == "Q" && field<bool>(view, "ready") && field<bool>(view, "known_actor"),
          "The actor label and Boolean eligibility retain their exact types.");
    check(field<I>(view, "placed_gears") == 2 && field<I>(view, "placed_shafts") == 3 &&
          field<bool>(view, "source_at_target") && field<bool>(view, "machines_running"),
          "Construction counts and current native facts are not converted to display strings.");
    for (const auto phase : {e::Phase::unavailable, e::Phase::first_shift, e::Phase::move_source,
                            e::Phase::restore_drive, e::Phase::deliver_more, e::Phase::ready}) {
        auto record = large;
        record.phase = phase;
        const auto projected = e::format_progress(record, "P");
        check(field<std::string>(projected, "phase") == e::phase_name(phase) &&
              field<bool>(projected, "ready") == (phase == e::Phase::ready),
              "Publishing a phase preserves the existing inspector's decision instead of recalculating eligibility.");
    }
}

void live_read_only_contract() {
    factory::godot_world::Host absent;
    const auto missing = e::projection(absent, "P");
    check(!field<bool>(missing, "known_actor") && !field<bool>(missing, "ready") &&
          field<std::string>(missing, "phase") == "unavailable", "No Host owner yields an explicit unavailable view.");
    factory::godot_world::Host host;
    check(field<bool>(host.initialize("payload-native", {"P", "Q"}), "accepted"), "The unchanged opening Host initializes.");
    const auto saved = host.checkpoint();
    for (const auto* actor : {"P", "Q"}) {
        const auto expected = e::inspect(host, actor);
        const auto value = e::projection(host, actor);
        check(field<bool>(value, "known_actor") && !field<bool>(value, "ready") &&
              field<std::string>(value, "phase") == "first_shift" && field<I>(value, "products") == expected.products &&
              field<std::string>(value, "actor") == actor,
              "The wrapper publishes the current per-actor inspector result without an actor observation or step.");
    }
    const auto unknown = e::projection(host, "not-in-roster");
    check(!field<bool>(unknown, "known_actor") && !field<bool>(unknown, "ready") && field<I>(unknown, "products") == 0,
          "Unknown actor lookup cannot borrow a registered actor's objective or create a participant.");
    check(!factory::values::typed_difference(saved, host.checkpoint()),
          "All view reads preserve typed material, kit, topology, actor seeds, request history and revision.");
}
}  // namespace

int main() {
    try {
        content_contract();
        scalar_and_phase_contract();
        live_read_only_contract();
        std::cout << checks << " native challenge-payload checks, 0 failures; engine_calls=0, physical_producers=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
