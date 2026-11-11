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
        std::cout << "PISTON_WORLD_PASS " << checks << '\n';
    } catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
