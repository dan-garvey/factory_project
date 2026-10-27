#pragma once

#include <array>
#include <cstdint>
#include <string>

namespace factory::godot_world::site_geometry {

// Current opening geometry. These are site values, not a permanent game scale.
inline constexpr double pitch = 1.65;
inline constexpr std::int64_t height_denominator = 4;
inline constexpr std::int64_t foundation_height_units = 2;
inline constexpr double height_step = pitch / height_denominator;
inline constexpr double foundation_depth = foundation_height_units * height_step;
inline constexpr double anchor_height = pitch / 2.0;
inline constexpr double belt_half_width = pitch * 0.55 / 2.0;
inline constexpr double belt_frame_outer_half_width = 0.57;
inline constexpr double belt_outer_radius = 0.1425;
inline constexpr double press_work_height = anchor_height + belt_outer_radius;
inline constexpr std::int64_t wheel_radius_hundredths = 224;
inline constexpr std::int64_t wheel_axle_offset_hundredths = 200;
inline constexpr double base_reach = 4.0;
inline constexpr double capsule_radius = 0.3;
inline constexpr double capsule_height = 1.8;
inline constexpr double machine_width = 1.45;
inline constexpr double machine_height = 1.65;
inline constexpr double machine_center_height = 0.8;
inline constexpr std::array<double, 3> collector_intake_size{0.28, 0.20, 0.24};
inline constexpr double collector_intake_x = -0.84;
inline constexpr double collector_intake_y = 0.50;
inline constexpr double collector_second_cell_z = -0.60;

struct CollectorLift {
    double pickup_x;
    double pickup_y;
    std::array<double, 3> pickup_size;
    double carrier_x;
    double carrier_bottom;
    double carrier_top_offset;
    std::array<double, 2> carrier_size_xz;
    std::array<double, 2> guide_offset;
    std::array<double, 2> guide_size;
    double flight_offset_x;
    double flight_raise_y;
    std::array<double, 3> flight_size;
    std::int64_t flight_count;
    double flight_span;
    double head_x;
    double head_y_offset;
    std::array<double, 2> head_size_xy;
    std::array<double, 2> head_z_size;
};

inline constexpr CollectorLift collector_lift{
    -1.04, 0.55, {0.34, 0.30, 0.40},
    -1.05, 0.67, 1.95, {0.34, 0.42},
    {0.09, 0.17}, {0.055, 0.055},
    -0.025, 0.05, {0.25, 0.16, 0.30},
    5, 0.88, -0.60, 1.77, {0.90, 0.36}, {0.40, 0.86},
};

[[nodiscard]] std::string gdscript_block();

} // namespace factory::godot_world::site_geometry
