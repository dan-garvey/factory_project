#include "coupling.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>

namespace factory_art::coupling {
namespace {
void require(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
Point minus(const Point &a, const Point &b) {
  return {a[0] - b[0], a[1] - b[1], a[2] - b[2]};
}
Point cross(const Point &a, const Point &b) {
  return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
          a[0] * b[1] - a[1] * b[0]};
}
double length(const Point &a) { return std::hypot(a[0], a[1], a[2]); }
Point unit(Point a) {
  const auto size = length(a);
  require(std::isfinite(size) && size > 1e-12, "Degenerate source normal.");
  for (auto &value : a)
    value /= size;
  return a;
}
using Key = std::array<std::int64_t, 3>;
Key key(const Point &p) {
  Key result{};
  for (unsigned axis = 0; axis < 3; ++axis) {
    require(std::isfinite(p[axis]) && std::abs(p[axis]) < 1000,
            "Unsupported art coordinate.");
    result[axis] = std::llround(p[axis] * 100000000.0);
  }
  return result;
}
Vertex intersection(const Vertex &a, const Vertex &b, double plane) {
  const auto t = (plane - a.position[1]) / (b.position[1] - a.position[1]);
  require(std::isfinite(t) && t >= 0 && t <= 1, "Invalid cut intersection.");
  Vertex result;
  for (unsigned axis = 0; axis < 3; ++axis) {
    result.position[axis] =
        a.position[axis] + t * (b.position[axis] - a.position[axis]);
    result.normal[axis] =
        a.normal[axis] + t * (b.normal[axis] - a.normal[axis]);
  }
  for (unsigned axis = 0; axis < 2; ++axis)
    result.uv[axis] = a.uv[axis] + t * (b.uv[axis] - a.uv[axis]);
  result.position[1] = plane;
  result.normal = unit(result.normal);
  return result;
}
bool nondegenerate(const Triangle &t) {
  return length(cross(minus(t[1].position, t[0].position),
                      minus(t[2].position, t[0].position))) > 1e-15;
}
double area(std::span<const Point> points) {
  double result = 0;
  for (std::size_t i = 0; i < points.size(); ++i)
    result += points[i][0] * points[(i + 1) % points.size()][2] -
              points[i][2] * points[(i + 1) % points.size()][0];
  return result / 2;
}
double side(const Point &a, const Point &b, const Point &p) {
  return (b[0] - a[0]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[0] - a[0]);
}
bool intersects(const Point &a, const Point &b, const Point &c,
                const Point &d) {
  const auto ab_c = side(a, b, c), ab_d = side(a, b, d);
  const auto cd_a = side(c, d, a), cd_b = side(c, d, b);
  if (((ab_c > 0 && ab_d < 0) || (ab_c < 0 && ab_d > 0)) &&
      ((cd_a > 0 && cd_b < 0) || (cd_a < 0 && cd_b > 0)))
    return true;
  auto on = [](const Point &p, const Point &x, const Point &y, double s) {
    return std::abs(s) <= 1e-12 && p[0] >= std::min(x[0], y[0]) - 1e-12 &&
           p[0] <= std::max(x[0], y[0]) + 1e-12 &&
           p[2] >= std::min(x[2], y[2]) - 1e-12 &&
           p[2] <= std::max(x[2], y[2]) + 1e-12;
  };
  return on(c, a, b, ab_c) || on(d, a, b, ab_d) || on(a, c, d, cd_a) ||
         on(b, c, d, cd_b);
}
bool inside(const Point &p, std::span<const Point> loop) {
  bool result = false;
  for (std::size_t i = 0; i < loop.size(); ++i) {
    const auto &a = loop[i], &b = loop[(i + 1) % loop.size()];
    if ((a[2] > p[2]) != (b[2] > p[2]) &&
        p[0] < a[0] + (p[2] - a[2]) * (b[0] - a[0]) / (b[2] - a[2]))
      result = !result;
  }
  return result;
}
void cap_triangle(Mesh &result, Point a, Point b, Point c) {
  Triangle triangle;
  for (unsigned n = 0; n < 3; ++n) {
    const auto &p = n == 0 ? a : n == 1 ? b : c;
    triangle[n] = {p, {0, -1, 0}, {p[0], p[2]}};
  }
  if (!nondegenerate(triangle))
    return;
  if (cross(minus(b, a), minus(c, a))[1] > 0)
    std::swap(triangle[1], triangle[2]);
  result.cut.push_back(triangle);
}
std::string digest(std::span<const unsigned char> bytes) {
  std::array<unsigned char, EVP_MAX_MD_SIZE> value{};
  unsigned count = 0;
  require(EVP_Digest(bytes.data(), bytes.size(), value.data(), &count,
                     EVP_sha256(), nullptr) == 1 &&
              count == 32,
          "Cannot hash the selected source.");
  std::ostringstream text;
  text << std::hex << std::setfill('0');
  for (unsigned i = 0; i < count; ++i)
    text << std::setw(2) << unsigned(value[i]);
  return text.str();
}
float scalar(std::span<const unsigned char> bytes, std::size_t at) {
  require(at <= bytes.size() && bytes.size() - at >= 4,
          "Source accessor exceeds the input.");
  const auto word = std::uint32_t(bytes[at]) |
                    (std::uint32_t(bytes[at + 1]) << 8) |
                    (std::uint32_t(bytes[at + 2]) << 16) |
                    (std::uint32_t(bytes[at + 3]) << 24);
  const auto result = std::bit_cast<float>(word);
  require(std::isfinite(result), "Nonfinite source attribute.");
  return result;
}
} // namespace

Mesh cut_shell(std::span<const Triangle> input, double plane) {
  require(std::isfinite(plane) && std::abs(plane) < 1000 && !input.empty() &&
              input.size() <= 65536,
          "Unsupported cut input.");
  Mesh result;
  for (const auto &triangle : input) {
    for (const auto &v : triangle) {
      (void)key(v.position);
      (void)unit(v.normal);
      require(std::isfinite(v.uv[0]) && std::isfinite(v.uv[1]),
              "Nonfinite source coordinates.");
    }
    std::vector<Vertex> polygon;
    for (unsigned n = 0; n < 3; ++n) {
      const auto &a = triangle[n];
      const auto &b = triangle[(n + 1) % 3];
      const bool keep_a = a.position[1] >= plane,
                 keep_b = b.position[1] >= plane;
      if (keep_a)
        polygon.push_back(a);
      if (keep_a != keep_b)
        polygon.push_back(intersection(a, b, plane));
    }
    for (std::size_t n = 1; n + 1 < polygon.size(); ++n) {
      Triangle face{polygon[0], polygon[n], polygon[n + 1]};
      if (nondegenerate(face))
        result.source.push_back(face);
    }
  }
  require(!result.source.empty(), "The cut removed the entire source.");
  using Edge = std::array<Key, 2>;
  std::map<Edge, unsigned> counts;
  std::map<Key, Point> points;
  for (const auto &triangle : result.source)
    for (unsigned n = 0; n < 3; ++n) {
      const auto &a = triangle[n].position;
      const auto &b = triangle[(n + 1) % 3].position;
      if (std::abs(a[1] - plane) > 1e-12 || std::abs(b[1] - plane) > 1e-12)
        continue;
      auto ka = key(a), kb = key(b);
      if (ka == kb)
        continue;
      points.emplace(ka, a);
      points.emplace(kb, b);
      if (kb < ka)
        std::swap(ka, kb);
      require(++counts[{ka, kb}] <= 2, "Nonmanifold cut boundary.");
    }
  std::map<Key, std::vector<Key>> adjacent;
  for (const auto &[edge, count] : counts)
    if (count == 1) {
      adjacent[edge[0]].push_back(edge[1]);
      adjacent[edge[1]].push_back(edge[0]);
    }
  for (const auto &[vertex, neighbors] : adjacent) {
    (void)vertex;
    require(neighbors.size() == 2, "Open or branched cut boundary.");
  }
  std::set<Key> visited;
  std::vector<std::vector<Point>> loops;
  for (const auto &[start, neighbors] : adjacent) {
    if (visited.contains(start))
      continue;
    std::vector<Point> loop;
    auto current = start, previous = start;
    do {
      require(!visited.contains(current),
              "Cut boundary revisits another loop.");
      visited.insert(current);
      loop.push_back(points.at(current));
      const auto &next = adjacent.at(current);
      const auto target = next[0] == previous ? next[1] : next[0];
      previous = current;
      current = target;
    } while (current != start);
    require(loop.size() >= 3, "Cut loop has too few vertices.");
    if (area(loop) < 0)
      std::reverse(loop.begin(), loop.end());
    // Retain the donor's tiny nonconvex surface variations. Every edge
    // must advance strictly around the axis; never convexify its shape.
    double angle_sum = 0;
    for (std::size_t n = 0; n < loop.size(); ++n) {
      const auto &a = loop[n];
      const auto &b = loop[(n + 1) % loop.size()];
      const auto wedge = a[0] * b[2] - a[2] * b[0];
      require(wedge > 1e-12, "The cut loop is not star-shaped about the axis.");
      angle_sum += std::atan2(wedge, a[0] * b[0] + a[2] * b[2]);
    }
    require(std::abs(angle_sum - 2 * std::acos(-1.0)) < 1e-8,
            "The cut loop winds more than once.");
    loops.push_back(std::move(loop));
  }
  require(loops.size() == 2, "The fitting needs exactly two cut loops.");
  if (area(loops[0]) < area(loops[1]))
    std::swap(loops[0], loops[1]);
  auto &outer = loops[0];
  auto &inner = loops[1];
  for (const auto &p : inner)
    require(inside(p, outer), "The cut loops are not nested.");
  for (std::size_t a = 0; a < outer.size(); ++a)
    for (std::size_t b = 0; b < inner.size(); ++b)
      require(!intersects(outer[a], outer[(a + 1) % outer.size()], inner[b],
                          inner[(b + 1) % inner.size()]),
              "The cut contours intersect or touch.");
  auto polar = [](const Point &p) { return std::atan2(p[2], p[0]); };
  for (auto *loop : {&outer, &inner})
    std::sort(loop->begin(), loop->end(), [&](const auto &a, const auto &b) {
      return polar(a) < polar(b);
    });
  std::size_t a = 0, b = 0;
  const double tau = 2 * std::acos(-1.0);
  while (a < outer.size() || b < inner.size()) {
    const auto next_a = a < outer.size()
                            ? polar(outer[(a + 1) % outer.size()]) +
                                  (a + 1 == outer.size() ? tau : 0)
                            : std::numeric_limits<double>::infinity();
    const auto next_b = b < inner.size()
                            ? polar(inner[(b + 1) % inner.size()]) +
                                  (b + 1 == inner.size() ? tau : 0)
                            : std::numeric_limits<double>::infinity();
    if (next_a <= next_b) {
      cap_triangle(result, outer[a % outer.size()],
                   outer[(a + 1) % outer.size()], inner[b % inner.size()]);
      ++a;
    } else {
      cap_triangle(result, outer[a % outer.size()],
                   inner[(b + 1) % inner.size()], inner[b % inner.size()]);
      ++b;
    }
  }
  require(!result.cut.empty(), "Cannot close the selected cut.");
  double cap_area = 0;
  for (const auto &face : result.cut)
    cap_area -= cross(minus(face[1].position, face[0].position),
                      minus(face[2].position, face[0].position))[1] /
                2;
  const auto expected_area = area(outer) - area(inner);
  require(expected_area > 0 && std::abs(cap_area - expected_area) <=
                                   std::max(1e-12, expected_area * 1e-8),
          "Annular closure overlaps or does not cover the cut.");
  return result;
}

Mesh prepare(std::span<const unsigned char> bytes) {
  require(bytes.size() == 515160 &&
              digest(bytes) == "2e11e1a7dabd56b1e158364f48b0b388bf316fcab61a012"
                               "74740db75dbafa448",
          "Expected the exact qualified pipe source.");
  std::vector<Triangle> selected;
  // Descriptor accessors 0..3: 810 source vertices, 1,800 uint16 indices.
  // The first body and its upper eight fasteners precede vertex 562.
  for (std::size_t face = 0; face < 1800; face += 3) {
    Triangle triangle;
    bool keep = true;
    for (unsigned corner = 0; corner < 3; ++corner) {
      const auto at = 25920 + (face + corner) * 2;
      const std::size_t index =
          std::uint16_t(bytes[at]) | (std::uint16_t(bytes[at + 1]) << 8);
      require(index < 810, "Invalid selected source index.");
      keep = keep && index < 562;
      for (unsigned axis = 0; axis < 3; ++axis) {
        triangle[corner].position[axis] = scalar(bytes, index * 12 + axis * 4);
        triangle[corner].normal[axis] =
            scalar(bytes, 9720 + index * 12 + axis * 4);
      }
      triangle[corner].normal = unit(triangle[corner].normal);
      for (unsigned axis = 0; axis < 2; ++axis)
        triangle[corner].uv[axis] = scalar(bytes, 19440 + index * 8 + axis * 4);
    }
    if (keep)
      selected.push_back(triangle);
  }
  auto result = cut_shell(selected, source_cut);
  for (auto *group : {&result.source, &result.cut})
    for (auto &face : *group)
      for (auto &vertex : face) {
        vertex.position[1] -= source_datum;
        for (auto &value : vertex.position)
          value *= scale;
      }
  return result;
}
} // namespace factory_art::coupling
