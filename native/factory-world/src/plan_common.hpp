#pragma once

#include "factory/world.hpp"

#include <array>
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace factory::world {

inline constexpr std::size_t maximum_issued_entities = 4096;
inline constexpr std::string_view allocated_prefix = "native-part-";
inline constexpr authority::Integer foundation_depth_levels = 2;

template<class T> const T* field(const authority::Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

struct WorkingPress {
    std::string anchor;
    mechanics::Point anchor_center{};
    mechanics::Point work_center{};
    mechanics::Point shaft_center{};
    std::string shaft;
    std::vector<assembly::PressFeed> open_feeds;
    std::optional<mechanics::Point> offcut_receiver;
    std::optional<mechanics::Point> plate_receiver;
    bool sliding{};
};

struct WorkingPressInspection {
    assembly::PressStatus status{assembly::PressStatus::invalid_input};
    std::optional<WorkingPress> press;
};

struct CollectorMatch {
    std::optional<assembly::Collector> collector;
    bool ambiguous{};
};

[[nodiscard]] bool crank_input_port(const PlacedComponent&, const mechanics::Point&);
[[nodiscard]] bool crank_face_on_axis(const mechanics::Point&, mechanics::Axis);
[[nodiscard]] mechanics::Point crank_face_from_actor(const Profile&,
    const authority::Point&, const mechanics::Point&, mechanics::Axis);
[[nodiscard]] bool manual_input_available(const mechanics::Motion&);
[[nodiscard]] bool slide_input_port_clear(const State&, const std::string&,
    const mechanics::Point&);
[[nodiscard]] std::optional<bool> hand_slide_contact(
    const State::SlidePhase&, const State::SlidePhase&, mechanics::Rate);
[[nodiscard]] CollectorMatch collector_for_input(const Profile&,
    const std::vector<assembly::Part>&, const std::string&);
[[nodiscard]] values::Value slide_phase_value(const State::SlidePhase&);

[[nodiscard]] bool has_attached_crank(const State&, const std::string&,
    const mechanics::Point&);
[[nodiscard]] std::vector<assembly::Part> assembly_parts(const State&);
[[nodiscard]] WorkingPressInspection inspect_working_press(const assembly::Layout&,
    materials::Component anchor_kind, const mechanics::Point&);
[[nodiscard]] bool placement(const std::string& action);
[[nodiscard]] bool slide_component(materials::Component);
[[nodiscard]] bool material_machine(stationary::Role);
[[nodiscard]] bool transmission_role(stationary::Role);
[[nodiscard]] bool transmission_center(stationary::Role, const mechanics::Point&,
    mechanics::Axis, authority::Integer half_span);
[[nodiscard]] std::optional<mechanics::Rate> wheel_rate(
    const Profile&, const stationary::PlacedPart&);
[[nodiscard]] bool spec_valid(const stationary::PartSpec&);
[[nodiscard]] std::optional<mechanics::Axis> axis(const std::string&);
[[nodiscard]] bool two_endpoints(const std::string& action);
[[nodiscard]] values::Value point_value(const authority::Point& point);
[[nodiscard]] values::Value grid_value(const mechanics::Point& point);
[[nodiscard]] std::array<mechanics::Point, 4> broad_cells(const mechanics::Point&);
[[nodiscard]] bool broad_item(const materials::Cargo&);
[[nodiscard]] std::vector<authority::Point> broad_reach_targets(const Profile&, const mechanics::Point&);
[[nodiscard]] std::optional<std::vector<materials::DropPoint>> channel_swept_cells(
    const mechanics::Point&, const mechanics::Point&, materials::Footprint,
    authority::Integer rotation, bool small_move);
[[nodiscard]] bool channel_cells_fit(const std::vector<materials::DropPoint>&,
    const std::vector<materials::DropPoint>& supports,
    const std::vector<materials::DropPoint>& blocked);
[[nodiscard]] std::optional<mechanics::Point> grid_point(
    const authority::Object&, authority::Integer limit = mechanics::maximum_coordinate);
[[nodiscard]] std::vector<mechanics::Point> foundation_area(const authority::Object&);
[[nodiscard]] bool add(authority::Integer& total, authority::Integer count);
[[nodiscard]] std::optional<stationary::Role> role(const std::string& value);
[[nodiscard]] const stationary::PlacedPart* part(const stationary::Topology&, const std::string& id);
[[nodiscard]] authority::Point anchor(const Profile&, const mechanics::Point&);
[[nodiscard]] values::Value removed_span_value(const stationary::PlacedBeltSpan&);
[[nodiscard]] values::Value lots_value(const std::vector<materials::WorkLot>&);
[[nodiscard]] bool copper_profile(const materials::Config&);
[[nodiscard]] values::Value belt_cargo_value(const materials::Cargo&, bool copper = false);
[[nodiscard]] authority::Object reach_facts(const Binding&, const authority::ReachReceipt&);
[[nodiscard]] Owner::Decision refused(std::string reason, std::string entity = {},
                                      authority::Object facts = {});
[[nodiscard]] Owner::Decision accepted(State state, std::string entity,
                                       authority::Object facts);

} // namespace factory::world
