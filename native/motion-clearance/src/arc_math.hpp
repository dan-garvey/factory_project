#pragma once

#include <algorithm>
#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <numeric>
#include <utility>

namespace factory::clearance::detail {
using I = std::int64_t;
struct Limit {};

// Private unsigned fixed-width arithmetic. Only dyadic numerators, their
// squares and bounded scalar multiples are needed; no division or heap exists.
struct Wide {
    std::array<std::uint32_t, 16> words{};
    explicit Wide(std::uint64_t value = 0) {
        words[0] = static_cast<std::uint32_t>(value); words[1] = static_cast<std::uint32_t>(value >> 32);
    }
    unsigned bits() const {
        for (std::size_t i = words.size(); i-- > 0;) {
            if (words[i]) return static_cast<unsigned>(32 * i + 32 - std::countl_zero(words[i]));
        }
        return 0;
    }
    int compare(const Wide& other) const {
        for (std::size_t i = words.size(); i-- > 0;) {
            if (words[i] != other.words[i]) return words[i] < other.words[i] ? -1 : 1;
        }
        return 0;
    }
    Wide operator+(const Wide& other) const {
        Wide out;
        std::uint64_t carry{};
        for (std::size_t i = 0; i < words.size(); ++i) {
            const auto sum = std::uint64_t(words[i]) + other.words[i] + carry;
            out.words[i] = static_cast<std::uint32_t>(sum); carry = sum >> 32;
        }
        if (carry) throw Limit{};
        return out;
    }
    Wide shifted(unsigned shift) const {
        if (shift >= 512 || bits() + shift > 512) throw Limit{};
        Wide out;
        for (std::size_t i = 0; i < words.size(); ++i) {
            if (!words[i]) continue;
            const auto target = i + shift / 32;
            const auto value = std::uint64_t(words[i]) << (shift % 32);
            out.words[target] |= static_cast<std::uint32_t>(value);
            if ((value >> 32) != 0) out.words[target + 1] |= static_cast<std::uint32_t>(value >> 32);
        }
        return out;
    }
    Wide scaled(std::uint32_t factor) const {
        Wide out;
        std::uint64_t carry{};
        for (std::size_t i = 0; i < words.size(); ++i) {
            const auto product = std::uint64_t(words[i]) * factor + carry;
            out.words[i] = static_cast<std::uint32_t>(product); carry = product >> 32;
        }
        if (carry) throw Limit{};
        return out;
    }
    Wide squared() const {
        if (2 * bits() > 512) throw Limit{};
        Wide out;
        const auto count = (bits() + 31) / 32;
        for (unsigned i = 0; i < count; ++i) {
            std::uint64_t carry{};
            for (unsigned j = 0; j < count; ++j) {
                const auto product = std::uint64_t(words[i]) * words[j] + out.words[i + j] + carry;
                out.words[i + j] = static_cast<std::uint32_t>(product); carry = product >> 32;
            }
            auto next = i + count;
            while (carry) {
                if (next >= out.words.size()) throw Limit{};
                const auto sum = std::uint64_t(out.words[next]) + carry;
                out.words[next++] = static_cast<std::uint32_t>(sum); carry = sum >> 32;
            }
        }
        return out;
    }
};

inline int sign_sum(std::initializer_list<std::pair<I, Wide>> terms) {
    Wide positive, negative;
    for (const auto& [coefficient, magnitude] : terms) {
        const auto absolute = coefficient < 0 ? std::uint64_t(-(coefficient + 1)) + 1 : std::uint64_t(coefficient);
        if (absolute > UINT32_MAX) throw Limit{};
        const auto term = magnitude.scaled(static_cast<std::uint32_t>(absolute));
        if (coefficient < 0) negative = negative + term; else positive = positive + term;
    }
    return positive.compare(negative);
}

struct Dyadic { Wide numerator; unsigned bits{}; };  // numerator / 2^bits.
struct Polynomial {
    I a{}, b{}, c{};
    bool operator==(const Polynomial&) const = default;
    int sign(const Dyadic& q) const {
        return sign_sum({{a, q.numerator.squared()}, {b, q.numerator.shifted(q.bits)},
                         {c, Wide(1).shifted(2 * q.bits)}});
    }
};

struct Root {
    bool rational{true};
    I numerator{}, denominator{1};
    Polynomial polynomial{};  // Primitive, positive leading coefficient.
    int branch{};            // -1 is the smaller irrational root; +1 the larger.
    int compare(const Dyadic& q) const {
        if (rational) return sign_sum({{numerator, Wide(1).shifted(q.bits)}, {-denominator, q.numerator}});
        const auto vertex = sign_sum({{2 * polynomial.a, q.numerator}, {polynomial.b, Wide(1).shifted(q.bits)}});
        if (branch < 0 && vertex >= 0) return -1;
        if (branch > 0 && vertex <= 0) return 1;
        const auto value = polynomial.sign(q);
        if (!value) throw Limit{};  // A genuinely irrational root cannot equal a dyadic.
        return branch < 0 ? value : -value;
    }
    bool same(const Root& other) const {
        if (rational != other.rational) return false;
        return rational ? numerator == other.numerator && denominator == other.denominator
                        : polynomial == other.polynomial && branch == other.branch;
    }
};

inline Root rational_root(I numerator, I denominator) {
    if (!denominator) throw Limit{};
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    const auto divisor = std::gcd(numerator, denominator);
    return {true, numerator / divisor, denominator / divisor, {}, 0};
}
inline I floor_sqrt(I value) {
    if (value <= 0) return 0;
    I low{}, high{1};
    while (high <= value / high) high *= 2;
    while (low + 1 < high) {
        const auto middle = low + (high - low) / 2;
        if (middle <= value / middle) low = middle; else high = middle;
    }
    return low;
}
inline std::size_t roots(Polynomial p, std::array<Root, 2>& out) {
    if (!p.a) {
        if (!p.b) return 0;
        out[0] = rational_root(-p.c, p.b); return 1;
    }
    if (p.a < 0) { p.a = -p.a; p.b = -p.b; p.c = -p.c; }
    const auto divisor = std::gcd(std::gcd(p.a, p.b), p.c);
    p.a /= divisor; p.b /= divisor; p.c /= divisor;
    const auto discriminant = p.b * p.b - 4 * p.a * p.c;
    if (discriminant < 0) return 0;
    const auto square = floor_sqrt(discriminant);
    if (square * square == discriminant) {
        out[0] = rational_root(-p.b - square, 2 * p.a);
        if (!square) return 1;
        out[1] = rational_root(-p.b + square, 2 * p.a);
    } else {
        out[0] = {false, 0, 1, p, -1}; out[1] = {false, 0, 1, p, 1};
    }
    return 2;
}

// Quadratic coefficients are at most 4,000,000; H=32,000,000 also bounds the
// reduced rational root representations. Distinct primitive quadratic roots in
// [0,1] have separation > 1/(H^4*(2H+2)^3): a nonzero integer resultant is at
// least one and bounds the other three root distances and leading factors.
// Rational roots obey the weaker corresponding degree-one bound; the two roots
// of one irreducible polynomial differ by at least 1/H. Thus 192
// dyadic steps suffice. Squared numerators plus coefficients use < 412 bits;
// 512 checked bits leave margin. Any breached bound refuses instead of guessing.
inline constexpr unsigned maximum_steps = 192;
inline int compare_roots(const Root& a, const Root& b) {
    if (a.same(b)) return 0;
    Wide lower;
    for (unsigned bits = 1; bits <= maximum_steps; ++bits) {
        const auto base = lower.shifted(1), middle = base + Wide(1);
        const auto ac = a.compare({middle, bits}), bc = b.compare({middle, bits});
        if (ac != bc) return ac < bc ? -1 : 1;
        if (!ac) return 0;
        lower = ac > 0 ? middle : base;
    }
    throw Limit{};
}
inline Dyadic between(const Root& a, const Root& b) {
    Wide lower;
    for (unsigned bits = 1; bits <= maximum_steps; ++bits) {
        const auto base = lower.shifted(1), middle = base + Wide(1);
        const auto ac = a.compare({middle, bits}), bc = b.compare({middle, bits});
        if (ac < 0 && bc > 0) return {middle, bits};
        lower = ac >= 0 ? middle : base;
    }
    throw Limit{};
}

inline bool positive_somewhere(const std::array<Polynomial, 8>& conditions) {
    std::array<Root, 18> events;
    events[0] = rational_root(0, 1); events[1] = rational_root(1, 1);
    std::size_t count{2};
    for (const auto& p : conditions) {
        for (const auto coefficient : {p.a, p.b, p.c}) {
            if (coefficient < -4000000 || coefficient > 4000000) throw Limit{};
        }
        if (!p.a && !p.b && p.c <= 0) return false;
        std::array<Root, 2> found;
        const auto number = roots(p, found);
        for (std::size_t i = 0; i < number; ++i) {
            if (found[i].compare({Wide(0), 0}) > 0 && found[i].compare({Wide(1), 0}) < 0) events[count++] = found[i];
        }
    }
    auto end = events.begin() + static_cast<std::ptrdiff_t>(count);
    std::sort(events.begin(), end, [](const Root& a, const Root& b) { return compare_roots(a, b) < 0; });
    end = std::unique(events.begin(), end, [](const Root& a, const Root& b) { return a.same(b); });
    for (auto next = events.begin() + 1; next != end; ++next) {
        const auto sample = between(*(next - 1), *next);
        bool positive = true;
        for (const auto& p : conditions) positive = positive && p.sign(sample) > 0;
        if (positive) return true;
    }
    return false;
}
}  // namespace factory::clearance::detail
