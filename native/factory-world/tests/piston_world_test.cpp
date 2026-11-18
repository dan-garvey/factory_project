#include "factory/piston_assembly.hpp"

#include <iostream>
#include <stdexcept>

namespace {
namespace w=factory::world;
namespace p=factory::piston;
namespace m=factory::mechanics;
using C=factory::materials::Component;
int checks{};
void check(bool ok,const char* why) { ++checks; if (!ok) throw std::runtime_error(why); }
w::State assembly(int sections) {
    w::State state;
    state.placed_components.emplace("piston",w::PlacedComponent{C::segmented_piston,{0,5,0},1});
    state.placed_components.emplace("head",w::PlacedComponent{C::drill_head,{0,1,0},2,0,"piston"});
    state.piston_progress.emplace("piston",p::Progress{});
    for (int n=0;n<sections;++n)
        state.placed_components.emplace("segment-"+std::to_string(n),
            w::PlacedComponent{C::piston_segment,{0,9+4*n,0},3+n,0,"piston"});
    return state;
}
}
int main() {
    try {
        w::Profile profile;
        for (int sections : {1,4}) {
            auto state=assembly(sections);
            check(w::piston_assembly::valid(state),"connected head and contiguous paid segments");
            const auto sockets=w::drive_power(profile,state).rotary_ports.at("piston");
            check(sockets.size()==3,"projection exposes two housing inputs and the moving output");
            check(!w::hand_crank_power(profile,state,"piston",{-2,5,0}).mechanical.accepted() &&
                !w::hand_crank_power(profile,state,"piston",{0,5,-2}).mechanical.accepted(),
                "closed housing faces cannot accept direct crank power");
            const auto feed=w::hand_crank_power(profile,state,"piston",{2,5,0});
            check(feed.mechanical.accepted(),"feed accepts horizontal source");
            check(feed.mechanical.motion.at("piston").state==m::MotionState::rotating,"feed is powered");
            check(feed.mechanical.motion.at("head").state==m::MotionState::unpowered,"feed does not rotate tool");
            check(feed.load.at("piston").impact==2 && feed.load.at("piston").capacity==12,
                "segment count does not alter feed load or capacity");
            const auto tool=w::hand_crank_power(profile,state,"piston",{0,5,2});
            check(tool.mechanical.accepted(),"independent tool input accepts horizontal source");
            check(tool.mechanical.motion.at("piston").state==m::MotionState::unpowered,"tool does not drive feed");
            check(tool.mechanical.motion.at("head").state==m::MotionState::rotating,"inner shaft powers real drill head");
            check(tool.load.at("head").impact==4 && tool.load.at("head").capacity==12,
                "segment count does not alter spindle load or capacity");
            check(w::piston_assembly::advance(state,feed,[](auto&,auto&,auto&,auto&,auto&) { return p::Clearance::clear; }),
                "native authority can admit observed motion");
            check(state.piston_progress.at("piston").position==256,"one pulse advances common distance");
            const auto position=w::piston_assembly::position(profile,state,state.placed_components.at("head"));
            check(position==factory::authority::Point{0,.75,0},"actual head position includes fractional native motion");
            const auto still=w::hand_crank_power(profile,state,"piston",{0,5,2});
            check(still.mechanical.motion.at("head")==tool.mechanical.motion.at("head"),
                "through power remains connected between construction levels");
            check(w::piston_assembly::reclaim_refusal(state,"segment-0")!=nullptr,
                "cannot remove moving structure midstroke");
        }
        auto state=assembly(4);
        check(w::piston_assembly::reclaim_refusal(state,"segment-0")!=nullptr,"inner segment cannot leave gap");
        check(w::piston_assembly::reclaim_refusal(state,"segment-3")==nullptr,"retracted end section can return to inventory");
        check(w::piston_assembly::reclaim_refusal(state,"piston")!=nullptr,"cannot delete support beneath carried parts");
        state.placed_components.erase("segment-1");
        check(!w::piston_assembly::valid(state),"discontinuous section custody refuses");
        state=assembly(1);
        state.placed_components.at("head").parent="missing";
        check(!w::piston_assembly::valid(state),"missing attachment identity refuses");
        state=assembly(1);
        state.piston_progress.at("piston").position=p::segment_ticks+1;
        check(!w::piston_assembly::valid(state),"save cannot grant more reach than owned segments");
        state=assembly(1);
        factory::stationary::PlacedPart shaft{{"shaft",m::Kind::shaft,{0,-3,0},m::Axis::y,0,2},
            10,factory::stationary::Role::shaft};
        shaft.parent="piston";
        check(!w::piston_assembly::placement_refusal(state,shaft),"Canonical shaft attaches to the drill spindle.");
        state.topology.parts.push_back(shaft);
        factory::stationary::PlacedPart cog{{"cog",m::Kind::gear,{0,-7,0},m::Axis::y,2,0},
            11,factory::stationary::Role::gear};
        cog.parent="piston";
        check(!w::piston_assembly::placement_refusal(state,cog),"Canonical small cog attaches to the carried shaft.");
        state.topology.parts.push_back(cog);
        check(w::piston_assembly::valid(state),"Canonical transmission parts share the native moving frame.");
        check(w::piston_assembly::reclaim_refusal(state,shaft)!=nullptr,"Reclaim cannot orphan a carried cog.");
        check(w::piston_assembly::reclaim_refusal(state,cog)==nullptr,"The exposed canonical cog can be reclaimed.");
        state.topology.parts.push_back({{"fixed",m::Kind::shaft,{0,-7,0},m::Axis::y,0,2},
            12,factory::stationary::Role::shaft});
        const auto moved_power=w::hand_crank_power(profile,state,"piston",{0,5,2});
        check(moved_power.mechanical.accepted() &&
            moved_power.mechanical.motion.at("shaft").state==m::MotionState::rotating &&
            moved_power.mechanical.motion.at("cog").state==m::MotionState::rotating &&
            moved_power.mechanical.motion.at("fixed").state==m::MotionState::unpowered,
            "A reference-pose overlap cannot teleport through power into the fixed world frame.");
        state.piston_progress.at("piston").position=256;
        check(w::piston_assembly::reclaim_refusal(state,cog)!=nullptr,"Moving canonical kits require retraction before reclaim.");
        auto unattached=cog; unattached.parent="missing";
        check(w::piston_assembly::placement_refusal(state,unattached)!=nullptr,"Unknown carriage identity refuses.");
        state.topology.parts[1].parent="missing";
        check(!w::piston_assembly::valid(state),"Restore refuses an orphaned canonical transmission part.");
        std::cout << "PISTON_WORLD_PASS " << checks << '\n';
    } catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
