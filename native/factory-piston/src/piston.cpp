#include "factory/piston.hpp"

#include <algorithm>
#include <limits>
#include <numeric>
#include <stdexcept>

namespace factory::piston {
namespace {
Point cross(Point a, Point b) {
    return {a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]};
}
const std::array<Basis,24>& orientations() {
    static const auto result = [] {
        std::array<Basis,24> values{};
        constexpr std::array<Point,6> axes{{{1,0,0},{0,1,0},{0,0,1},{-1,0,0},{0,-1,0},{0,0,-1}}};
        std::size_t count{};
        for (auto x : axes) for (auto y : axes) {
            const auto z = cross(x,y);
            if (z != Point{}) values[count++] = {x,y,z};
        }
        return values;
    }();
    return result;
}
Bounds box(const Config& config, const Progress& progress, Point low, Point high, bool moving) {
    const auto axes = *basis(config.orientation);
    const auto shift = moving ? displacement(config,progress) : Point{};
    Bounds result;
    result.minimum.fill(std::numeric_limits<Integer>::max());
    result.maximum.fill(std::numeric_limits<Integer>::min());
    for (int corner=0; corner<8; ++corner) {
        Point local{};
        for (unsigned n=0;n<3;++n) local[n] = corner & (1<<n) ? high[n] : low[n];
        const auto point = rotate(axes,local);
        for (unsigned n=0;n<3;++n) {
            const auto world = config.center[n]*ticks_per_level + point[n] + shift[n];
            result.minimum[n] = std::min(result.minimum[n],world);
            result.maximum[n] = std::max(result.maximum[n],world);
        }
    }
    return result;
}
} // namespace
std::optional<Basis> basis(Integer orientation) noexcept {
    if (orientation<0 || orientation>=24) return std::nullopt;
    return orientations()[orientation];
}
Point rotate(const Basis& axes, Point local) noexcept {
    Point result{};
    for (unsigned n=0;n<3;++n) for (unsigned a=0;a<3;++a) result[n]+=axes[a][n]*local[a];
    return result;
}
bool valid(const Config& c, const Progress& p) noexcept {
    if (!basis(c.orientation) || c.segments<0 || c.segments>maximum_segments ||
        p.position<0 || p.position>c.segments*segment_ticks || p.denominator<=0 ||
        p.remainder<=-p.denominator || p.remainder>=p.denominator) return false;
    for (auto at : c.center)
        if (at < -mechanics::maximum_coordinate+4*maximum_segments+4 ||
            at > mechanics::maximum_coordinate-4*maximum_segments-4) return false;
    return true;
}
Point displacement(const Config& c, const Progress& p) {
    if (!valid(c,p)) throw std::invalid_argument("invalid piston");
    return rotate(*basis(c.orientation),{0,-p.position,0});
}
Point moving_point(const Config& c, const Progress& p, Point reference) {
    const auto shift = displacement(c,p);
    for (unsigned n=0;n<3;++n) reference[n]=reference[n]*ticks_per_level+shift[n];
    return reference;
}
Point segment_center(const Config& c, Integer index) {
    if (!valid(c) || index<0 || index>=maximum_segments) throw std::invalid_argument("invalid segment");
    auto result=rotate(*basis(c.orientation),{0,4*(index+1),0});
    for (unsigned n=0;n<3;++n) result[n]+=c.center[n];
    return result;
}
Bounds enclosure(Bounds a, Bounds b) noexcept {
    for (unsigned n=0;n<3;++n) {
        a.minimum[n]=std::min(a.minimum[n],b.minimum[n]);
        a.maximum[n]=std::max(a.maximum[n],b.maximum[n]);
    }
    return a;
}
bool overlaps(const Bounds& a, const Bounds& b) noexcept {
    for (unsigned n=0;n<3;++n)
        if (a.maximum[n]<=b.minimum[n] || a.minimum[n]>=b.maximum[n]) return false;
    return true;
}
Geometry geometry(const Config& c, const Progress& p) {
    if (!valid(c,p)) throw std::invalid_argument("invalid piston");
    constexpr Integer h=ticks_per_level;
    Geometry result{box(c,p,{-2*h,-h,-2*h},{2*h,h,2*h},false),
        box(c,p,{-h/2,-2*h,-h/2},{h/2,2*h+c.segments*segment_ticks,h/2},true),{}};
    for (Integer index=0;index<c.segments;++index) {
        const auto y=2*h+index*segment_ticks;
        result.segments.push_back(box(c,p,{-h/2,y,-h/2},{h/2,y+segment_ticks,h/2},true));
    }
    return result;
}
std::array<mechanics::Part,3> spindles(const Config& c, const std::string& owner) {
    if (!valid(c) || owner.empty()) throw std::invalid_argument("invalid piston");
    const auto axes=*basis(c.orientation);
    const auto axis=[](Point direction) {
        for (unsigned n=0;n<3;++n) if (direction[n]) return static_cast<mechanics::Axis>(n);
        throw std::invalid_argument("invalid axis");
    };
    return {{{owner,mechanics::Kind::shaft,c.center,axis(axes[0]),0,2},
        {owner+"/tool",mechanics::Kind::shaft,c.center,axis(axes[2]),0,2},
        {owner+"/output",mechanics::Kind::shaft,c.center,axis(axes[1]),0,2}}};
}
std::vector<Port> ports(const Config& c, const Progress& p) {
    const auto parts=spindles(c,"piston");
    std::vector<Port> result;
    const auto forward=rotate(*basis(c.orientation),{0,-1,0});
    for (unsigned index=0;index<3;++index) for (auto port : mechanics::rotary_ports(parts[index])) {
        if (index==2 && port.outward!=forward) continue;
        auto position=port.position;
        for (auto& n : position) n*=ticks_per_level;
        if (index==2) position=moving_point(c,p,port.position);
        result.push_back({static_cast<Channel>(index),port,position,index==2});
    }
    return result;
}
mechanics::Engagement through_connection(const Config& c, const std::string& owner) {
    if (!valid(c)) throw std::invalid_argument("invalid piston");
    const auto axes=*basis(c.orientation);
    const auto sign=[](Point axis) { return axis[0]+axis[1]+axis[2]; };
    return {owner+"/tool",owner+"/output",mechanics::EngagementKind::relay,
        {sign(axes[2])*sign(axes[1]),1}};
}
Motion advance(const Config& c, const Progress& previous, mechanics::Rate rate, const ObserveSweep& query) {
    const auto failure=[&](Error error) { return Motion{error,previous,0,false}; };
    if (!valid(c,previous)) return failure(Error::invalid_state);
    if (rate.denominator<=0 || rate.numerator==std::numeric_limits<Integer>::min())
        return failure(Error::invalid_rate);
    __extension__ using Wide=__int128;
    // Mechanical rates use a positive world axis. Feed uses the body's local
    // X axle so rotating the housing rotates its winding as well as its ports.
    const auto feed_axis=(*basis(c.orientation))[0];
    rate.numerator*=feed_axis[0]+feed_axis[1]+feed_axis[2];
    const auto common=std::gcd(previous.denominator,rate.denominator);
    const Wide denominator=Wide(previous.denominator/common)*rate.denominator;
    if (denominator>std::numeric_limits<Integer>::max()) return failure(Error::invalid_rate);
    const Wide tick_work=Wide(rate.numerator)*feed_ticks_per_turn;
    const Wide whole=tick_work/rate.denominator;
    if (whole < -segment_ticks || whole>segment_ticks) return failure(Error::invalid_rate);
    const Wide total=whole*denominator+Wide(previous.remainder)*(rate.denominator/common)+
        (tick_work%rate.denominator)*(previous.denominator/common);
    const Wide requested=total/denominator;
    if (requested < -segment_ticks || requested>segment_ticks)
        return failure(Error::invalid_rate);
    auto next=previous;
    next.blocked=false;
    next.remainder=static_cast<Integer>(total%denominator);
    next.denominator=static_cast<Integer>(denominator);
    const auto divisor=std::gcd(next.remainder,next.denominator);
    next.remainder/=divisor; next.denominator/=divisor;
    const Integer limit=c.segments*segment_ticks;
    const Integer target=std::clamp(previous.position+static_cast<Integer>(requested),Integer{0},limit);
    if (target!=previous.position && !query) return failure(Error::query_failed);
    try {
        while (next.position!=target) {
            auto step=next;
            step.position+=std::clamp(target-next.position,-maximum_step,maximum_step);
            const auto swept=enclosure(geometry(c,next).arm,geometry(c,step).arm);
            const auto clearance=query(next,step,swept);
            if (clearance==Clearance::unavailable) return failure(Error::query_failed);
            if (clearance==Clearance::blocked) { next.blocked=true; break; }
            if (clearance!=Clearance::clear) return failure(Error::query_failed);
            next=step;
        }
    } catch (...) { return failure(Error::query_failed); }
    const bool at_limit=next.position==0 || next.position==limit;
    if (next.blocked || (next.position==0 && rate.numerator<=0) ||
        (next.position==limit && rate.numerator>=0)) { next.remainder=0; next.denominator=1; }
    return {Error::none,next,next.position-previous.position,at_limit};
}
} // namespace factory::piston
