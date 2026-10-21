#include "coupling.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <map>
#include <stdexcept>
#include <string>

namespace {
using namespace factory_art::coupling;
unsigned checks = 0;
void check(bool ok, const char *message) {
  ++checks;
  if (!ok)
    throw std::runtime_error(message);
}
template <class F> void refuses(F operation, const char *message) {
  bool refused = false;
  try {
    operation();
  } catch (const std::runtime_error &) {
    refused = true;
  }
  check(refused, message);
}
Point subtract(Point a, const Point &b) {
  for (unsigned i = 0; i < 3; ++i)
    a[i] -= b[i];
  return a;
}
Point cross(const Point &a, const Point &b) {
  return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
          a[0] * b[1] - a[1] * b[0]};
}
void triangle(std::vector<Triangle> &out, Point a, Point b, Point c) {
  auto normal = cross(subtract(b, a), subtract(c, a));
  const auto length = std::hypot(normal[0], normal[1], normal[2]);
  for (auto &n : normal)
    n /= length;
  out.push_back({Vertex{a, normal, {a[0] / 7, a[1] / 9}},
                 Vertex{b, normal, {b[0] / 7, b[1] / 9}},
                 Vertex{c, normal, {c[0] / 7, c[1] / 9}}});
}
void quad(std::vector<Triangle> &out, Point a, Point b, Point c, Point d) {
  triangle(out, a, b, c);
  triangle(out, a, c, d);
}
std::vector<Triangle> cup(unsigned count = 16, double phase = 0) {
  std::vector<Triangle> out;
  for (unsigned i = 0; i < count; ++i) {
    auto p = [&](double r, double y, unsigned j) {
      const auto angle = phase + 2 * std::acos(-1.0) * j / count;
      return Point{r * std::cos(angle), y, r * std::sin(angle)};
    };
    const auto j = i + 1;
    quad(out, p(2, 0, i), p(2, 3, i), p(2, 3, j), p(2, 0, j));
    quad(out, p(1, 1, j), p(1, 3, j), p(1, 3, i), p(1, 1, i));
    quad(out, p(1, 3, i), p(1, 3, j), p(2, 3, j), p(2, 3, i));
    triangle(out, {0, 0, 0}, p(2, 0, i), p(2, 0, j));
    triangle(out, {0, 1, 0}, p(1, 1, j), p(1, 1, i));
  }
  return out;
}
using Key = std::array<std::int64_t, 3>;
Key key(const Point &p) {
  return {std::llround(p[0] * 1e8), std::llround(p[1] * 1e8),
          std::llround(p[2] * 1e8)};
}
bool closed(std::span<const Triangle> faces) {
  std::map<std::array<Key, 2>, unsigned> edges;
  for (const auto &face : faces)
    for (unsigned i = 0; i < 3; ++i) {
      auto a = key(face[i].position), b = key(face[(i + 1) % 3].position);
      if (a == b)
        return false;
      if (b < a)
        std::swap(a, b);
      ++edges[{a, b}];
    }
  return !edges.empty() &&
         std::all_of(edges.begin(), edges.end(),
                     [](const auto &edge) { return edge.second == 2; });
}
double side(const Point &a, const Point &b, const Point &p) {
  return (b[0] - a[0]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[0] - a[0]);
}
bool axis_blocked(std::span<const Triangle> faces) {
  for (const auto &t : faces) {
    const auto a = t[0].position, b = t[1].position, c = t[2].position;
    if (std::abs(side(a, b, c)) < 1e-12)
      continue;
    const auto ab = side(a, b, {}), bc = side(b, c, {}), ca = side(c, a, {});
    if ((ab >= -1e-12 && bc >= -1e-12 && ca >= -1e-12) ||
        (ab <= 1e-12 && bc <= 1e-12 && ca <= 1e-12))
      return true;
  }
  return false;
}
double axis_distance(const Point &a, const Point &b) {
  const auto x = b[0] - a[0], z = b[2] - a[2];
  const auto t = std::clamp(-(a[0] * x + a[2] * z) / (x * x + z * z), 0.0, 1.0);
  return std::hypot(a[0] + t * x, a[2] + t * z);
}
void positive(unsigned segments, double phase) {
  const auto original = cup(segments, phase);
  check(closed(original), "The invented capped source must start closed.");
  check(axis_blocked(original),
        "The original blind cap must obstruct the axis.");
  const auto result = cut_shell(original, 2);
  auto complete = result.source;
  complete.insert(complete.end(), result.cut.begin(), result.cut.end());
  check(closed(complete),
        "The cut closure must have exactly two faces per edge.");
  check(!closed(result.source), "Removing the closure must be detected.");
  check(!axis_blocked(complete), "The cut must leave the shaft passage open.");
  double area = 0;
  for (const auto &face : complete)
    for (const auto &v : face) {
      check(v.position[1] >= 2, "No removed surface may remain below the cut.");
      if (v.position[1] > 2) {
        bool found = false;
        for (const auto &before : original)
          for (const auto &old : before)
            found = found || (v.position == old.position &&
                              v.normal == old.normal && v.uv == old.uv);
        check(found, "Untouched vertices must preserve all source attributes.");
      } else if (v.normal != Point{0, -1, 0}) {
        check(std::abs(std::hypot(v.normal[0], v.normal[1], v.normal[2]) - 1) <
                  1e-12,
              "New cut normals must remain unit length.");
        check(std::abs(v.uv[0] - v.position[0] / 7) < 1e-12 &&
                  std::abs(v.uv[1] - 2.0 / 9) < 1e-12,
              "Cut source UVs must interpolate the original attributes.");
      }
    }
  for (const auto &face : result.cut) {
    const auto normal = cross(subtract(face[1].position, face[0].position),
                              subtract(face[2].position, face[0].position));
    check(normal[1] < 0, "Every annular closure face must wind outward.");
    area -= normal[1] / 2;
    for (unsigned i = 0; i < 3; ++i) {
      check(face[i].normal == Point{0, -1, 0},
            "The closure needs a hard machined normal.");
      check(axis_distance(face[i].position, face[(i + 1) % 3].position) >=
                std::cos(std::acos(-1.0) / segments) - 1e-10,
            "No closure edge may enter the inscribed bore.");
    }
  }
  check(std::abs(area - 1.5 * segments *
                            std::sin(2 * std::acos(-1.0) / segments)) < 1e-9,
        "Closure area must equal the polygonal annulus, without overlap.");
  auto plugged = complete;
  triangle(plugged, {-1, 2, -1}, {1, 2, -1}, {0, 2, 1});
  check(axis_blocked(plugged),
        "The oracle must reject a plugged shaft passage.");
}
} // namespace

int main() {
  try {
    for (unsigned n : {8, 13, 16, 23})
      for (double phase : {0.0, 0.17})
        positive(n, phase);
    refuses([] { (void)cut_shell({}, 2); }, "Empty input must be refused.");
    refuses([] { (void)cut_shell(cup(), 4); },
            "A fully removed source must be refused.");
    refuses([] { (void)cut_shell(cup(), -1); },
            "An uncut source must not be relabelled as a fitting.");
    refuses(
        [] {
          (void)cut_shell(cup(), std::numeric_limits<double>::quiet_NaN());
        },
        "A nonfinite plane must be refused.");
    auto malformed = cup();
    malformed[0][0].position[0] = std::numeric_limits<double>::infinity();
    refuses([&] { (void)cut_shell(malformed, 2); },
            "Nonfinite vertices must be refused.");
    malformed = cup();
    malformed[0][0].normal = {};
    refuses([&] { (void)cut_shell(malformed, 2); },
            "Degenerate normals must be refused.");
    malformed = cup();
    malformed[0][0].uv[0] = std::numeric_limits<double>::quiet_NaN();
    refuses([&] { (void)cut_shell(malformed, 2); },
            "Nonfinite UVs must be refused.");
    malformed = cup();
    malformed.erase(malformed.begin());
    refuses([&] { (void)cut_shell(malformed, 2); },
            "An open cut loop must be refused.");
    malformed = cup();
    malformed.push_back(malformed.front());
    refuses([&] { (void)cut_shell(malformed, 2); },
            "A branched cut loop must be refused.");
    malformed = cup();
    for (auto &t : malformed)
      for (auto &v : t)
        if (v.position[0] > 1.9 && std::abs(v.position[2]) < 1e-12)
          v.position[0] = 1.2;
    const auto nonconvex = cut_shell(malformed, 2);
    auto complete = nonconvex.source;
    complete.insert(complete.end(), nonconvex.cut.begin(), nonconvex.cut.end());
    check(closed(complete) && !axis_blocked(complete),
          "A star-shaped, radially separated nonconvex loop must retain its "
          "bore and seams.");
    auto touching = cup();
    for (auto &t : touching)
      for (auto &v : t)
        if (v.position[0] > 1.9 && std::abs(v.position[2]) < 1e-12)
          v.position[0] = .99;
    refuses([&] { (void)cut_shell(touching, 2); },
            "An outer contour entering the bore must be refused.");
    for (auto &t : malformed)
      for (auto &v : t)
        if (v.position[0] > 1.19 && v.position[0] < 1.21 &&
            std::abs(v.position[2]) < 1e-12)
          v.position[0] = -.5;
    refuses([&] { (void)cut_shell(malformed, 2); },
            "A contour that crosses the axis must be refused.");
    malformed = cup();
    for (auto &t : malformed)
      for (auto &v : t)
        v.position[0] += 10;
    refuses([&] { (void)cut_shell(malformed, 2); },
            "An off-axis bore must be refused.");
    malformed = cup();
    auto extra = cup(8, .1);
    for (auto &t : extra)
      for (auto &v : t)
        v.position[0] += 10;
    malformed.insert(malformed.end(), extra.begin(), extra.end());
    refuses([&] { (void)cut_shell(malformed, 2); },
            "Multiple annuli must be refused.");
    refuses(
        [] {
          std::vector<unsigned char> wrong(515160);
          (void)prepare(wrong);
        },
        "Changed source identity must be refused.");
    refuses(
        [] {
          std::array<unsigned char, 1> short_source{};
          (void)prepare(short_source);
        },
        "Wrong source length must be refused.");
    std::cout << "Coupling cut-and-cap checks passed: " << checks << ".\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "Coupling check failed after " << checks
              << " assertions: " << error.what() << '\n';
    return 1;
  }
}
