#include "factory/site_geometry_contract.hpp"

#include <charconv>
#include <stdexcept>
#include <string>

namespace factory::godot_world::site_geometry {
namespace {

std::string number(double value) {
    char buffer[64];
    const auto [end, error] = std::to_chars(buffer, buffer + sizeof(buffer), value);
    if (error != std::errc{}) throw std::runtime_error("Cannot emit a site geometry value.");
    std::string result(buffer, end);
    if (result.find_first_of(".eE") == std::string::npos) result += ".0";
    return result;
}

template<std::size_t N>
std::string array(const std::array<double, N>& values) {
    std::string result = "[";
    for (std::size_t index = 0; index < N; ++index) {
        if (index != 0) result += ", ";
        result += number(values[index]);
    }
    return result + "]";
}

} // namespace

std::string gdscript_block() {
    std::string output = "# BEGIN NATIVE SITE GEOMETRY\n";
    output += "const PITCH := " + number(pitch) + "\n";
    output += "const HEIGHT_DENOMINATOR := " + std::to_string(height_denominator) + "\n";
    output += "const HEIGHT_STEP := PITCH / HEIGHT_DENOMINATOR\n";
    output += "const FOUNDATION_HEIGHT_UNITS := " + std::to_string(foundation_height_units) + "\n";
    output += "const FOUNDATION_DEPTH := FOUNDATION_HEIGHT_UNITS * HEIGHT_STEP\n";
    output += "const ANCHOR_HEIGHT := PITCH / 2.0\n";
    output += "const WATERWHEEL_RADIUS_HUNDREDTHS := " +
        std::to_string(wheel_radius_hundredths) + "\n";
    output += "const WATERWHEEL_AXLE_OFFSET_HUNDREDTHS := " +
        std::to_string(wheel_axle_offset_hundredths) + "\n";
    output += "const WATERWHEEL_RADIUS := WATERWHEEL_RADIUS_HUNDREDTHS * HEIGHT_STEP / 100.0\n";
    output += "const BASE_REACH := " + number(base_reach) + "\n";
    output += "const CAPSULE_RADIUS := " + number(capsule_radius) + "\n";
    output += "const CAPSULE_HEIGHT := " + number(capsule_height) + "\n";
    output += "const MACHINE_SIZE := " + array(std::array<double, 3>{
        machine_width, machine_height, machine_width}) + "\n";
    output += "const MACHINE_CENTER_HEIGHT := " + number(machine_center_height) + "\n";
    output += "const COLLECTOR_INTAKE_SIZE := " + array(collector_intake_size) + "\n";
    output += "const COLLECTOR_INTAKE_X := " + number(collector_intake_x) + "\n";
    output += "const COLLECTOR_INTAKE_Y := " + number(collector_intake_y) + "\n";
    output += "const COLLECTOR_SECOND_CELL_Z := " + number(collector_second_cell_z) + "\n";
    output += "const COLLECTOR_LIFT_PROFILE := {\n";
    output += "\t\"pickup_x\": " + number(collector_lift.pickup_x) +
        ", \"pickup_y\": " + number(collector_lift.pickup_y) +
        ", \"pickup_size\": " + array(collector_lift.pickup_size) + ",\n";
    output += "\t\"carrier_x\": " + number(collector_lift.carrier_x) +
        ", \"carrier_bottom\": " + number(collector_lift.carrier_bottom) +
        ", \"carrier_top_offset\": " + number(collector_lift.carrier_top_offset) + ",\n";
    output += "\t\"carrier_size_xz\": " + array(collector_lift.carrier_size_xz) + ",\n";
    output += "\t\"guide_offset\": " + array(collector_lift.guide_offset) +
        ", \"guide_size\": " + array(collector_lift.guide_size) + ",\n";
    output += "\t\"flight_offset_x\": " + number(collector_lift.flight_offset_x) +
        ", \"flight_raise_y\": " + number(collector_lift.flight_raise_y) + ",\n";
    output += "\t\"flight_size\": " + array(collector_lift.flight_size) + ",\n";
    output += "\t\"flight_count\": " + std::to_string(collector_lift.flight_count) +
        ", \"flight_span\": " + number(collector_lift.flight_span) + ",\n";
    output += "\t\"head_x\": " + number(collector_lift.head_x) +
        ", \"head_y_offset\": " + number(collector_lift.head_y_offset) + ",\n";
    output += "\t\"head_size_xy\": " + array(collector_lift.head_size_xy) +
        ", \"head_z_size\": " + array(collector_lift.head_z_size) + ",\n";
    output += "}\n# END NATIVE SITE GEOMETRY\n";
    return output;
}

} // namespace factory::godot_world::site_geometry
