#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/support_edit_preview.hpp"

#include <iostream>
#include <stdexcept>
#include <string_view>

namespace {
namespace native = factory::godot_world;
namespace preview = native::support_edit_preview;
namespace world = factory::world;
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

bool reason_is(const preview::Result& result, std::string_view expected) {
    const auto* reason = std::get_if<const char*>(&result);
    return reason && *reason && std::string_view(*reason) == expected;
}

bool unchanged(const world::World& actual, const world::Snapshot& before) {
    const auto after = actual.snapshot();
    return after.state == before.state && after.revision == before.revision &&
        after.history.order == before.history.order &&
        after.history.records.size() == before.history.records.size();
}

Object place_shaft(Integer x, Integer z) {
    return {{"action", Value("place")}, {"role", Value("shaft")},
        {"center", Value(Array{Value(x), Value(Integer{4}), Value(z)})},
        {"axis", Value("x")}, {"half_span", Value(Integer{2})}};
}

void preview_native_edits() {
    const auto authored = native::make_arrival_configuration(false, false, {"P"});
    check(authored.has_value(), "An authored native start supplies the real edit source.");
    auto actual = world::World::create("support-preview", authored->profile, authored->seed);
    check(actual != nullptr, "One native World owns the actual construction state.");
    const auto before = actual->snapshot();
    check(preview::applies("place") && preview::applies("place_foundations") &&
          preview::applies("place_selected_belt_span") && preview::applies("remove_belt_span") &&
          !preview::applies("operate_hand_crank"),
          "Only support-changing native actions request a temporary geometry preview.");

    const auto placed = preview::build(before.state, place_shaft(0, 0));
    check(std::holds_alternative<world::State>(placed) &&
          std::get<world::State>(placed).topology.parts.size() == 1 &&
          std::get<world::State>(placed).topology.parts.front().geometry.id == "support-preview" &&
          unchanged(*actual, before),
          "A new shaft appears only in temporary geometry; World and history stay untouched.");
    const auto& one_shaft = std::get<world::State>(placed);
    check(reason_is(preview::build(one_shaft, place_shaft(0, 0)), "occupied"),
          "A second part at the same native center refuses before support selection.");
    auto other_shaft = preview::build(one_shaft, place_shaft(8, 0));
    check(std::holds_alternative<world::State>(other_shaft) &&
          std::get<world::State>(other_shaft).topology.parts.size() == 2 &&
          std::get<world::State>(other_shaft).topology.parts.back().geometry.id == "support-preview-",
          "A temporary part avoids an existing native identity.");
    const auto& two_shafts = std::get<world::State>(other_shaft);
    const auto cleared_shaft = preview::build(two_shafts,
        Object{{"action", Value("remove")}, {"target", Value("support-preview-")}});
    check(std::holds_alternative<world::State>(cleared_shaft) &&
          std::get<world::State>(cleared_shaft).topology.parts.size() == 1 &&
          two_shafts.topology.parts.size() == 2,
          "Removing a part proposes a new geometry without changing the placed World parts.");
    const auto belt = preview::build(two_shafts, Object{{"action", Value("place_belt_span")},
        {"target", Value("support-preview")}, {"to", Value("support-preview-")}});
    check(std::holds_alternative<world::State>(belt) &&
          std::get<world::State>(belt).topology.belt_spans.size() == 1 &&
          std::get<world::State>(belt).topology.belt_spans.front().geometry.id == "support-preview--",
          "A belt preview keeps both endpoints and chooses an unused identity.");
    const auto cleared_belt = preview::build(std::get<world::State>(belt),
        Object{{"action", Value("remove_belt_span")}, {"target", Value("support-preview--")}});
    check(std::holds_alternative<world::State>(cleared_belt) &&
          std::get<world::State>(cleared_belt).topology.belt_spans.empty() &&
          std::get<world::State>(belt).topology.belt_spans.size() == 1,
          "Removing a preview belt leaves its source state intact.");

    const auto foundations = preview::build(before.state,
        Object{{"action", Value("place_foundations")},
            {"center", Value(Array{Value(Integer{0}), Value(Integer{0}), Value(Integer{0})})},
            {"end", Value(Array{Value(Integer{4}), Value(Integer{0}), Value(Integer{4})})}});
    check(std::holds_alternative<world::State>(foundations) &&
          std::get<world::State>(foundations).foundations.size() == 4 &&
          before.state.foundations.empty(),
          "An area edit previews four native foundation cells without spending a kit.");
    const auto reduced = preview::build(std::get<world::State>(foundations),
        Object{{"action", Value("remove_foundation")},
            {"target", Value("support-preview:0:0")}});
    check(std::holds_alternative<world::State>(reduced) &&
          std::get<world::State>(reduced).foundations.size() == 3 &&
          std::get<world::State>(foundations).foundations.size() == 4,
          "Foundation removal changes only the proposed site copy.");
    auto unknown = place_shaft(0, 0);
    unknown.at("role") = Value("unknown_part");
    check(reason_is(preview::build(before.state, unknown), "invalid_command") &&
          unchanged(*actual, before),
          "An unrecognized normalized part cannot reach World or alter the original state.");
    check(reason_is(preview::build(before.state, Object{{"action", Value("operate_hand_crank")}}),
          "invalid_command") && reason_is(preview::build(before.state, Object{}), "invalid_command"),
          "The preview module refuses unsupported or missing actions instead of inventing a belt.");
}
}  // namespace

int main() {
    try {
        preview_native_edits();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
