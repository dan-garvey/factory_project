#include "factory/piston.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <set>
#include <stdexcept>

namespace {
namespace p=factory::piston;
namespace m=factory::mechanics;
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}
auto clear=[](const p::Progress&,const p::Progress&,const p::Bounds&) { return p::Clearance::clear; };
}
int main() {
    p::Config short_arm{{0,5,0},0,1}, long_arm{{0,5,0},0,4};
    p::Progress short_motion,long_motion;
    check(p::valid(short_arm),"valid starter assembly");
    check(!p::valid({{},24,1}) && !p::valid({{},0,65}),"bounded geometry");
    check(!p::valid(short_arm,{p::segment_ticks+1,0,1,false}),"travel cannot exceed paid length");
    check(p::basis(0)==p::Basis{{{1,0,0},{0,1,0},{0,0,1}}},"default orientation is vertical down");
    for (int i=0;i<16;++i) {
        auto a=p::advance(short_arm,short_motion,{1,1},clear);
        auto b=p::advance(long_arm,long_motion,{1,1},clear);
        check(a.error==p::Error::none && b.error==p::Error::none,"ordinary feed");
        check(a.displacement==b.displacement && a.displacement==256,"length does not alter speed");
        short_motion=a.progress; long_motion=b.progress;
    }
    check(short_motion.position==p::segment_ticks,"one segment gives 1U travel");
    check(p::advance(short_arm,short_motion,{1,1},clear).displacement==0,"finite short stroke");
    check(p::advance(long_arm,long_motion,{1,1},clear).displacement==256,"longer stroke continues");
    const auto retracted=p::advance(short_arm,short_motion,{-1,1},clear);
    check(retracted.displacement==-256,"feed can reverse at its limit");
    auto fraction=p::Progress{};
    for (int i=0;i<8;++i) fraction=p::advance(short_arm,fraction,{1,2048},clear).progress;
    check(fraction.position==1 && fraction.remainder==0,"fractional feed accumulates at rest");
    const auto obstacle=[](const p::Progress& from,const p::Progress& to,const p::Bounds& arm) {
        check(arm.minimum[1]<=3*p::ticks_per_level-to.position,"arm sweep includes leading endpoint");
        if (to.position>from.position && to.position>128) return p::Clearance::blocked;
        return p::Clearance::clear;
    };
    auto blocked=p::advance(short_arm,{}, {1,1},obstacle);
    check(blocked.displacement==128 && blocked.progress.blocked,"obstruction stops at last clear substep");
    check(blocked.progress.remainder==0,"blocked feed does not accumulate force or deferred travel");
    auto retreat=p::advance(short_arm,blocked.progress,{-1,1},obstacle);
    check(retreat.progress.position==0 && !retreat.progress.blocked,"blocked tool can retract");
    const auto unavailable=[](const p::Progress&,const p::Progress& to,const p::Bounds&) {
        return to.position>128 ? p::Clearance::unavailable : p::Clearance::clear;
    };
    auto failed=p::advance(short_arm,{}, {1,1},unavailable);
    check(failed.error==p::Error::query_failed && failed.progress==p::Progress{},"observer failure rolls back entire proposal");
    check(p::advance(short_arm,{}, {1,1},{}).error==p::Error::query_failed,"movement needs a site observer");
    check(p::advance(short_arm,{}, {1,1},[](auto&,auto&,auto&)->p::Clearance {
        throw std::runtime_error("site unavailable");
    }).error==p::Error::query_failed,"observer exception refuses safely");
    check(p::advance(short_arm,{}, {std::numeric_limits<p::Integer>::min(),1},clear).error==p::Error::invalid_rate,
        "minimum integer rate refuses");
    check(p::advance(short_arm,{}, {std::numeric_limits<p::Integer>::max(),1},clear).error==p::Error::invalid_rate,
        "unbounded rate refuses without arithmetic overflow");
    check(p::advance(short_arm,{}, {std::numeric_limits<p::Integer>::max(),std::numeric_limits<p::Integer>::max()},clear).displacement==256,
        "large equal rational remains one turn");
    std::set<p::Basis> orientations;
    for (int orientation=0;orientation<24;++orientation) {
        auto c=long_arm; c.orientation=orientation;
        const auto axes=*p::basis(orientation); orientations.insert(axes);
        const auto a=p::ports(c,{}), b=p::ports(c,{1001,0,1,false});
        check(a.size()==5 && b.size()==5,"two independent pairs and one moving output");
        for (unsigned n=0;n<4;++n) check(a[n].position==b[n].position,"body ports remain fixed");
        check(b.back().position==p::moving_point(c,{1001,0,1,false},a.back().reference.position),
            "output port follows fractional native displacement");
        check(a.back().reference.outward==p::rotate(axes,{0,-1,0}),"output normal rotates with body");
        const auto geometry=p::geometry(c,{1001,0,1,false});
        check(geometry.segments.size()==4,"each paid section has physical geometry");
        for (auto segment : geometry.segments)
            check(p::enclosure(geometry.arm,segment)==geometry.arm,"moving arm contains its segments");
        const auto native=p::spindles(c,"drive");
        std::vector<m::Part> parts(native.begin(),native.end());
        const auto ports=p::ports(c,{});
        const auto tool=ports[2].reference;
        auto power=m::resolve_engagements(parts,{{"drive/tool",{1,1},tool.position}},
            {p::through_connection(c,"drive")});
        check(power.accepted(),"shared ratio solver accepts registered through passage");
        check(power.motion.at("drive").state==m::MotionState::unpowered,"tool power cannot drive feed");
        check(power.motion.at("drive/output").state==m::MotionState::rotating,"through output rotates with feed idle");
        const auto feed=ports[0].reference;
        power=m::resolve_engagements(parts,{{"drive",{-1,1},feed.position},{"drive/tool",{1,1},tool.position}},
            {p::through_connection(c,"drive")});
        check(power.accepted() && power.motion.at("drive/output").state==m::MotionState::rotating,
            "reversing feed does not reverse or stall tool");
    }
    check(orientations.size()==24,"all grid orientations are distinct");
    const auto parts=p::spindles(short_arm,"drive");
    std::vector<m::Part> graph(parts.begin(),parts.end());
    auto edge=p::through_connection(short_arm,"drive");
    check(m::resolve_engagements(graph,{}, {edge,edge}).error==m::Error::invalid_engagement,"duplicate joint refuses");
    edge.b="absent";
    check(m::resolve_engagements(graph,{}, {edge}).error==m::Error::invalid_engagement,"missing joint endpoint refuses");
    std::cout << "PISTON_TEST_PASS " << checks << '\n';
}
