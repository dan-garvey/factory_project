#include "factory/terrain_surface.hpp"

#include "physical_geometry.hpp"
#include "arrival_excavation.hpp"
#include "factory/site_geometry_contract.hpp"
#include "factory/waterflow.hpp"
#include "factory/waterwheel.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <set>
#include <tuple>
#include <utility>

namespace factory::godot_world::terrain_surface {
namespace {
using Array = values::Value::Array;
using Integer = values::Value::Integer;
using Object = values::Value::Object;
using Bounds = arrival_geometry::Bounds;

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

std::optional<authority::Point> point(const Array& values) {
    if (values.size() != 3) return std::nullopt;
    authority::Point output;
    for (std::size_t index = 0; index < 3; ++index) {
        if (const auto* value = std::get_if<double>(&values[index].storage())) output[index] = *value;
        else if (const auto* value = std::get_if<Integer>(&values[index].storage())) {
            // Reject a lossy observation conversion rather than moving a body.
            constexpr Integer exact_limit = 9007199254740992;
            if (*value < -exact_limit || *value > exact_limit) return std::nullopt;
            output[index] = static_cast<double>(*value);
        } else return std::nullopt;
        if (!std::isfinite(output[index])) return std::nullopt;
    }
    return output;
}
}  // namespace

ParseResult parse(const Object& input, const world::Profile& profile) {
    const auto* axis = field<Array>(input, "axis");
    const auto* heights = field<Array>(input, "heights");
    const auto* obstacles = field<Array>(input, "obstacles");
    const auto* source_obstacle = field<Integer>(input, "source_obstacle");
    const auto* tree_obstacles = field<Object>(input, "tree_obstacles");
    const auto* water = field<Array>(input, "water");
    const auto* flow_cells = field<Array>(input, "flow_cells");
    if (input.size() != (water || flow_cells ? 4u : 3u) + (source_obstacle ? 1u : 0u) +
        (tree_obstacles ? 1u : 0u) || (water && flow_cells) ||
        !axis || !heights || !obstacles || obstacles->size() > 1024 || axis->size() < 2 || axis->size() > 200 ||
        heights->size() != axis->size() * axis->size()) return {{}, "invalid_terrain"};
    Surface surface;
    for (const auto& value : *axis) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000 ||
            (!surface.axis.empty() && surface.axis.back() >= *number)) return {{}, "invalid_terrain"};
        surface.axis.push_back(*number);
    }
    for (const auto& value : *heights) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000) return {{}, "invalid_terrain"};
        surface.heights.push_back(*number);
    }
    for (const auto& value : *obstacles) {
        const auto* ends = std::get_if<Array>(&value.storage());
        if (!ends || ends->size() != 2) return {{}, "invalid_terrain"};
        const auto* low_array = std::get_if<Array>(&ends->at(0).storage());
        const auto* high_array = std::get_if<Array>(&ends->at(1).storage());
        const auto low = low_array ? point(*low_array) : std::nullopt;
        const auto high = high_array ? point(*high_array) : std::nullopt;
        if (!low || !high) return {{}, "invalid_terrain"};
        for (std::size_t coordinate = 0; coordinate < 3; ++coordinate)
            if ((*low)[coordinate] >= (*high)[coordinate]) return {{}, "invalid_terrain"};
        surface.obstacles.emplace_back(*low, *high);
    }
    if (input.contains("source_obstacle") && (!source_obstacle || *source_obstacle < 0 ||
        static_cast<std::size_t>(*source_obstacle) >= surface.obstacles.size())) return {{}, "invalid_terrain"};
    if (source_obstacle) {
        const auto& [low, high] = surface.obstacles[static_cast<std::size_t>(*source_obstacle)];
        const Bounds source{{(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2},
                            {(high[0] - low[0]) / 2, (high[1] - low[1]) / 2, (high[2] - low[2]) / 2}};
        if (!physical_geometry::overlap(source, *physical_geometry::collector_intake_bounds({0, 0, 0})) ||
            !physical_geometry::overlap(source, *physical_geometry::collector_intake_bounds({0, 0, 4})))
            return {{}, "invalid_terrain"};
        surface.source_obstacle = static_cast<std::size_t>(*source_obstacle);
    }
    if (tree_obstacles) for (const auto& [id, value] : *tree_obstacles) {
        const auto* index = std::get_if<Integer>(&value.storage());
        if (!index || *index < 0 || static_cast<std::size_t>(*index) >= surface.obstacles.size() ||
            (source_obstacle && *index == *source_obstacle) ||
            !profile.material.timber_sites.contains(id) ||
            surface.tree_obstacles.contains(static_cast<std::size_t>(*index)))
            return {{}, "invalid_terrain"};
        surface.tree_obstacles.emplace(static_cast<std::size_t>(*index), id);
    }
    auto next_profile = profile;
    if (source_obstacle && next_profile.material.manual_ore)
        next_profile.manual_ore_contact_bounds = surface.obstacles[*surface.source_obstacle];
    if (profile.ore_field) {
        next_profile.excavation = arrival_excavation::seed(surface, profile.initial_units);
        if (!next_profile.excavation) return {{}, "invalid_excavation_terrain"};
        next_profile.ore_field = false;
        next_profile.ore_exposures = {};
        next_profile.manual_ore_contact_bounds.reset();
        next_profile.collector_faces.clear();
    }
    if (flow_cells) {
        if (flow_cells->empty() || flow_cells->size() > 65536) return {{}, "invalid_water"};
        std::vector<waterflow::Cell> cells;
        cells.reserve(flow_cells->size());
        for (const auto& value : *flow_cells) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 3) return {{}, "invalid_water"};
            const auto* x = std::get_if<Integer>(&row->at(0).storage());
            const auto* z = std::get_if<Integer>(&row->at(1).storage());
            const auto* surface_height = std::get_if<Integer>(&row->at(2).storage());
            if (!x || !z || !surface_height) return {{}, "invalid_water"};
            cells.push_back({*x, *z, *surface_height});
        }
        const auto derived = waterflow::derive({surface.axis, surface.heights, site_geometry::height_step}, cells);
        if (!derived) return {{}, "invalid_water"};
        next_profile.water = *derived;
    }
    if (water) {
        if (water->empty() || water->size() > 65536) return {{}, "invalid_water"};
        for (const auto& value : *water) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 6) return {{}, "invalid_water"};
            std::array<Integer, 6> fields{};
            for (std::size_t index = 0; index < fields.size(); ++index) {
                const auto* number = std::get_if<Integer>(&row->at(index).storage());
                if (!number) return {{}, "invalid_water"};
                fields[index] = *number;
            }
            if (!next_profile.water.emplace(std::array<Integer, 2>{fields[0], fields[1]},
                    waterwheel::Sample{fields[2], fields[3], fields[4], fields[5]}).second)
                return {{}, "invalid_water"};
        }
    }
    return {Binding{std::move(surface), std::move(next_profile),
        water || flow_cells || profile.ore_field || (source_obstacle && profile.material.manual_ore)}, nullptr};
}

bool Surface::blocked(const authority::Point& low, const authority::Point& high,
        std::optional<std::size_t> ignored) const {
    for (std::size_t index = 0; index < obstacles.size(); ++index) {
        if (ignored == index || (excavated && source_obstacle == index)) continue;
        const auto& obstacle = obstacles[index];
        bool overlaps = true;
        for (std::size_t coordinate = 0; coordinate < 3; ++coordinate)
            if (high[coordinate] <= obstacle.first[coordinate] ||
                low[coordinate] >= obstacle.second[coordinate]) overlaps = false;
        if (overlaps) return true;
    }
    return false;
}

namespace {
bool covered(const std::vector<double>& axis, double x, double z, double half_x, double half_z) {
    return axis.size() >= 2 && std::isfinite(x) && std::isfinite(z) &&
        std::isfinite(half_x) && std::isfinite(half_z) && half_x >= 0 && half_z >= 0 &&
        x - half_x >= axis.front() && x + half_x <= axis.back() &&
        z - half_z >= axis.front() && z + half_z <= axis.back();
}

std::size_t axis_cell(const std::vector<double>& axis, double at, bool lower = false) {
    const auto end = lower ? std::lower_bound(axis.begin(), axis.end(), at) :
        std::upper_bound(axis.begin(), axis.end(), at);
    return std::min(axis.size() - 2, static_cast<std::size_t>(
        std::max<std::ptrdiff_t>(0, end - axis.begin() - 1)));
}

bool overlaps_query(const Triangle& tri,double left,double right,double near,double far) {
    // Terrain bins can contain many small excavated faces. Keep boundary
    // contacts, but avoid clipping and allocating for distant triangles.
    // Enclose the point path's barycentric tolerance across both edge spans.
    const double padding=256*std::numeric_limits<double>::epsilon()*std::max({1.,
        std::abs(left),std::abs(right),std::abs(near),std::abs(far),
        std::abs(tri[0][0]),std::abs(tri[0][2]),std::abs(tri[1][0]),
        std::abs(tri[1][2]),std::abs(tri[2][0]),std::abs(tri[2][2])});
    if(std::max({tri[0][0],tri[1][0],tri[2][0]})<left-padding||
       std::min({tri[0][0],tri[1][0],tri[2][0]})>right+padding||
       std::max({tri[0][2],tri[1][2],tri[2][2]})<near-padding||
       std::min({tri[0][2],tri[1][2],tri[2][2]})>far+padding)return false;
    return true;
}

struct Measurement {
    double low = std::numeric_limits<double>::infinity();
    authority::Point high{0, -std::numeric_limits<double>::infinity(), 0};
    void sample(const authority::Point& p) {
        low = std::min(low,p[1]);
        if (p[1] > high[1] || (p[1] == high[1] &&
                std::pair{p[0],p[2]} < std::pair{high[0],high[2]})) high = p;
    }
    void include(const Triangle& tri, double left, double right, double near, double far) {
        if(!overlaps_query(tri,left,right,near,far))return;
        if (left == right && near == far) {
            // A vertical line query is a triangle intersection, not a
            // zero-area polygon. Repeated clipping can lose shared diagonals.
            const auto& a=tri[0];const auto& b=tri[1];const auto& c=tri[2];
            const long double bx=b[0]-a[0],bz=b[2]-a[2],cx=c[0]-a[0],cz=c[2]-a[2];
            const long double determinant=bx*cz-bz*cx;
            constexpr long double epsilon=64*std::numeric_limits<double>::epsilon();
            if (determinant != 0) {
                const long double x=static_cast<long double>(left)-a[0],z=static_cast<long double>(near)-a[2];
                const long double u=(x*cz-z*cx)/determinant,v=(bx*z-bz*x)/determinant;
                if (u>=-epsilon && v>=-epsilon && u+v<=1+epsilon)
                    sample({left,static_cast<double>(a[1]+u*(b[1]-a[1])+v*(c[1]-a[1])),near});
                return;
            }
            // Vertical pit walls have no XZ area. Their edge intersections
            // still supply the exact low/high obstruction interval.
            for (std::size_t index=0;index<3;++index) {
                const auto& p=tri[index];const auto& q=tri[(index+1)%3];
                const long double dx=q[0]-p[0],dz=q[2]-p[2];
                const long double extent=std::max({1.0,std::abs(left),std::abs(near),std::abs(p[0]),std::abs(p[2])});
                if (dx==0 && dz==0) {
                    if (std::abs(left-p[0])<=epsilon*extent && std::abs(near-p[2])<=epsilon*extent) {sample(p);sample(q);}
                    continue;
                }
                const long double t=std::abs(dx)>=std::abs(dz)?(static_cast<long double>(left)-p[0])/dx:
                    (static_cast<long double>(near)-p[2])/dz;
                if (t>=-epsilon && t<=1+epsilon &&
                        std::abs(p[0]+t*dx-left)<=epsilon*extent && std::abs(p[2]+t*dz-near)<=epsilon*extent)
                    sample({left,static_cast<double>(p[1]+t*(q[1]-p[1])),near});
            }
            return;
        }
        std::vector<authority::Point> polygon{tri.begin(), tri.end()};
        for (const auto& [coordinate, boundary, sign] : {std::tuple{0, left, 1.0}, {0, right, -1.0},
                {2, near, 1.0}, {2, far, -1.0}}) {
            std::vector<authority::Point> clipped;
            for (std::size_t index = 0; index < polygon.size(); ++index) {
                const auto& p = polygon[index];
                const auto& q = polygon[(index + 1) % polygon.size()];
                const bool inside = (p[coordinate] - boundary) * sign >= 0;
                const bool next = (q[coordinate] - boundary) * sign >= 0;
                if (inside) clipped.push_back(p);
                if (inside != next) {
                    const double t = (boundary - p[coordinate]) / (q[coordinate] - p[coordinate]);
                    authority::Point hit{p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]),
                        p[2] + t * (q[2] - p[2])};
                    hit[coordinate] = boundary;
                    clipped.push_back(hit);
                }
            }
            polygon = std::move(clipped);
        }
        for (const auto& p : polygon) sample(p);
    }
    std::optional<std::pair<double, double>> range() const {
        return std::isfinite(low) && std::isfinite(high[1]) ?
            std::optional{std::pair{low, high[1]}} : std::nullopt;
    }
};

std::optional<Measurement> measure_natural(const Surface& surface, double x, double z,
        double half_x, double half_z) {
    const auto& axis = surface.axis;
    if (!covered(axis, x, z, half_x, half_z) || surface.heights.size() != axis.size() * axis.size())
        return std::nullopt;
    const double left = x - half_x, right = x + half_x;
    const double near = z - half_z, far = z + half_z;
    const auto vertex = [&](std::size_t gx, std::size_t gz) {
        return authority::Point{axis[gx], surface.heights[gz * axis.size() + gx], axis[gz]};
    };
    Measurement measured;
    for (auto gz = axis_cell(axis, near); gz <= axis_cell(axis, far); ++gz)
    for (auto gx = axis_cell(axis, left); gx <= axis_cell(axis, right); ++gx) {
        const auto a = vertex(gx, gz), b = vertex(gx + 1, gz), c = vertex(gx + 1, gz + 1), d = vertex(gx, gz + 1);
        for (const auto& tri : {std::array<authority::Point, 3>{a, b, c}, std::array<authority::Point, 3>{a, c, d}}) {
            measured.include(tri, left, right, near, far);
        }
    }
    return measured;
}
} // namespace

std::optional<std::pair<double, double>> Surface::natural_range(double x, double z,
        double half_x, double half_z) const {
    if (half_x == 0 && half_z == 0 && covered(axis, x, z, 0, 0) &&
            heights.size() == axis.size() * axis.size()) {
        // A point on a shared diagonal must not disappear through successive
        // zero-area polygon clips. Evaluate the same a-c triangle directly.
        const auto gx = axis_cell(axis, x), gz = axis_cell(axis, z);
        const long double u = (static_cast<long double>(x) - axis[gx]) / (axis[gx+1] - axis[gx]);
        const long double v = (static_cast<long double>(z) - axis[gz]) / (axis[gz+1] - axis[gz]);
        const auto at = [&](std::size_t dx, std::size_t dz) { return heights[(gz+dz)*axis.size()+gx+dx]; };
        const long double a = at(0,0), c = at(1,1);
        const double h = static_cast<double>(u >= v ? a + u*(at(1,0)-a) + v*(c-at(1,0)) :
            a + v*(at(0,1)-a) + u*(c-at(0,1)));
        if (std::isfinite(h)) return std::pair{h,h};
        return std::nullopt;
    }
    const auto measured = measure_natural(*this, x, z, half_x, half_z);
    return measured ? measured->range() : std::nullopt;
}

std::optional<authority::Point> Surface::natural_highest(double x, double z,
        double half_x, double half_z) const {
    const auto measured = measure_natural(*this, x, z, half_x, half_z);
    return measured && measured->range() ? std::optional{measured->high} : std::nullopt;
}

std::optional<std::pair<double, double>> Surface::range(double x, double z,
        double half_x, double half_z) const {
    return excavated ? excavated->range(x, z, half_x, half_z) : natural_range(x, z, half_x, half_z);
}

void Mesh::index(const std::vector<double>& terrain_axis) {
    axis = terrain_axis;
    bins.clear();
    for (std::size_t i = 0; i < faces.size(); ++i) {
        const auto& triangle = faces[i];
        const double left = std::min({triangle[0][0], triangle[1][0], triangle[2][0]});
        const double right = std::max({triangle[0][0], triangle[1][0], triangle[2][0]});
        const double near = std::min({triangle[0][2], triangle[1][2], triangle[2][2]});
        const double far = std::max({triangle[0][2], triangle[1][2], triangle[2][2]});
        for (auto z = axis_cell(axis, near, true); z <= axis_cell(axis, far); ++z)
        for (auto x = axis_cell(axis, left, true); x <= axis_cell(axis, right); ++x)
            bins[z * axis.size() + x].push_back(i);
    }
}

std::optional<std::pair<double, double>> Mesh::range(double x, double z,
        double half_x, double half_z) const {
    if (!covered(axis, x, z, half_x, half_z)) return std::nullopt;
    Measurement measured;
    std::set<std::size_t> visited;
    for (auto gz = axis_cell(axis, z - half_z, true); gz <= axis_cell(axis, z + half_z); ++gz)
    for (auto gx = axis_cell(axis, x - half_x, true); gx <= axis_cell(axis, x + half_x); ++gx) {
        const auto found = bins.find(gz * axis.size() + gx);
        if (found == bins.end()) continue;
        for (const auto i : found->second)
            if (overlaps_query(faces[i],x-half_x,x+half_x,z-half_z,z+half_z) && visited.insert(i).second)
            measured.include(faces[i], x - half_x, x + half_x, z - half_z, z + half_z);
    }
    return measured.range();
}

}  // namespace factory::godot_world::terrain_surface
