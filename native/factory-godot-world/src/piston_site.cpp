#include "factory/physical_site.hpp"
#include "factory/piston_assembly.hpp"
#include "factory/surface_drill.hpp"
#include "component_geometry.hpp"
#include "physical_geometry.hpp"

#include <algorithm>

namespace factory::godot_world::physical_site {
namespace {
using B=arrival_geometry::Bounds;
using C=materials::Component;
using P=authority::Point;
B swept(B first, B last) {
    for (unsigned n=0;n<3;++n) {
        const double low=std::min(first.center[n]-first.half[n],last.center[n]-last.half[n]);
        const double high=std::max(first.center[n]+first.half[n],last.center[n]+last.half[n]);
        first.center[n]=(low+high)/2; first.half[n]=(high-low)/2;
    }
    return first;
}
B shift(B box, const mechanics::Point& ticks, double h) {
    for (unsigned n=0;n<3;++n) box.center[n]+=h*ticks[n]/piston::ticks_per_level;
    return box;
}
piston::Clearance earth(const Site& site, const B& box) {
    // Flush faces on the edge of a cut are contact, not a terrain column
    // through the swept body. Match ordinary support's numerical seating skin.
    const auto ground=site.terrain.range(box.center[0],box.center[2],
        std::max(1e-9,box.half[0]-1e-7),std::max(1e-9,box.half[2]-1e-7));
    if (!ground) return piston::Clearance::unavailable;
    return ground->second>box.center[1]-box.half[1]+1e-7 ? piston::Clearance::blocked : piston::Clearance::clear;
}
bool obstruction(const Site& site, const world::State& state, const B& box,
        const std::string& owner, const std::string& carried_by, const std::vector<P>& actors) {
    for (const auto& [id,part] : state.placed_components) {
        if (id==owner || (!carried_by.empty() && (id==carried_by || part.parent==carried_by))) continue;
        for (const auto& solid : component_geometry::placed_solids(site.profile,state,id,part))
            if (physical_geometry::overlap(box,solid)) return true;
    }
    for (const auto& [id,foundation] : state.foundations) {
        (void)id;
        if (physical_geometry::overlap(box,physical_geometry::foundation_bounds(foundation))) return true;
    }
    for (const auto& part : state.topology.parts) {
        if (part.geometry.id==owner || (!carried_by.empty() && part.parent==carried_by)) continue;
        for (const auto& solid : physical_geometry::part_solids(site.profile,state,part))
            if (physical_geometry::overlap(box,solid)) return true;
    }
    if (physical_geometry::intersects_belt(state,box)) return true;
    for (const auto& [id,part] : arrival_geometry::supplied(state,site.profile.meters_per_grid_unit)) {
        (void)id;
        if (physical_geometry::overlap(box,part.bounds)) return true;
    }
    for (std::size_t n=0;n<site.terrain.obstacles.size();++n) {
        if (site.terrain.excavated && site.terrain.source_obstacle==n) continue;
        const auto tree=site.terrain.tree_obstacles.find(n);
        if (tree!=site.terrain.tree_obstacles.end() && state.material.timber_remaining.contains(tree->second) &&
            state.material.timber_remaining.at(tree->second)==0) continue;
        const auto& [low,high]=site.terrain.obstacles[n];
        B obstacle;
        for (unsigned a=0;a<3;++a) { obstacle.center[a]=(low[a]+high[a])/2; obstacle.half[a]=(high[a]-low[a])/2; }
        if (physical_geometry::overlap(box,obstacle)) return true;
    }
    for (const auto& actor : actors) if (physical_geometry::capsule_intersects(actor,box)) return true;
    return false;
}
}

const char* piston_placement_refusal(const Site& site, const world::State& state,
        const std::string& entity, const std::vector<P>& actors) {
    const auto found=state.placed_components.find(entity);
    if (found==state.placed_components.end()) {
        const auto moving=std::find_if(state.topology.parts.begin(),state.topology.parts.end(),
            [&](const auto& part) { return part.geometry.id==entity && !part.parent.empty(); });
        if (moving==state.topology.parts.end()) return "unknown_target";
        for (const auto& box : physical_geometry::part_solids(site.profile,state,*moving)) {
            if (earth(site,box)!=piston::Clearance::clear) return "site_occupied";
            if (obstruction(site,state,box,entity,moving->parent,actors)) return "occupied";
        }
        return nullptr;
    }
    const auto& part=found->second;
    const auto solids=component_geometry::placed_solids(site.profile,state,entity,part);
    for (const auto& box : solids) {
        // Cutting teeth retain their existing one-H contact band. The drill's
        // admission envelope owns soil clearance; its teeth still hit objects.
        if (part.kind!=C::drill_head && earth(site,box)!=piston::Clearance::clear) return "site_occupied";
        if (obstruction(site,state,box,entity,part.kind==C::segmented_piston ? entity : part.parent,actors)) return "occupied";
    }
    if (part.kind==C::drill_head) {
        const auto head=shift(component_geometry::component_bounds(site.profile,part.kind,part.center),
            world::piston_assembly::displacement(state,part.parent),site.profile.meters_per_grid_unit);
        if (earth(site,head)!=piston::Clearance::clear) return "site_occupied";
    }
    return piston_support_refusal(site,state,entity);
}

const char* piston_support_refusal(const Site& site, const world::State& state,
        const std::string& entity) {
    const auto& part=state.placed_components.at(entity);
    const auto solids=component_geometry::placed_solids(site.profile,state,entity,part);
    if (part.kind==C::segmented_piston) {
        bool supported=false;
        // Same centered guide connection as the approved reusable drill mount.
        if (part.orientation==0)
            for (const auto& [id,mount] : state.placed_components) {
                (void)id;
                if (mount.kind==C::stationary_mount && part.center==mechanics::Point{
                    mount.center[0],mount.center[1]+5,mount.center[2]}) supported=true;
            }
        if (!supported) {
            const auto body=solids.front();
            const double floor=body.center[1]-body.half[1];
            const auto ground=site.terrain.range(body.center[0],body.center[2],body.half[0],body.half[2]);
            supported=ground && ground->first>=floor-1e-7 && ground->second<=floor+1e-7;
            for (const auto& [id,foundation] : state.foundations) {
                (void)id;
                const auto slab=physical_geometry::foundation_bounds(foundation);
                if (std::abs(slab.center[1]+slab.half[1]-floor)<1e-7 &&
                    std::abs(body.center[0]-slab.center[0])+body.half[0]<=slab.half[0]+1e-7 &&
                    std::abs(body.center[2]-slab.center[2])+body.half[2]<=slab.half[2]+1e-7) supported=true;
            }
        }
        if (!supported) return "support_required";
    }
    return nullptr;
}

piston::Clearance piston_sweep(const Site& site, const world::State& state,
        const std::string& entity, const piston::Progress& from, const piston::Progress& to,
        const piston::Bounds& swept_arm, const std::vector<P>& actors, const std::vector<B>& supports) {
    const auto config=world::piston_assembly::configuration(state,entity);
    if (!config || !site.terrain.bound()) return piston::Clearance::unavailable;
    const auto arm=component_geometry::piston_bounds(site.profile,swept_arm);
    const auto arm_ground=earth(site,arm);
    if (arm_ground!=piston::Clearance::clear) return arm_ground;
    if (obstruction(site,state,arm,entity,entity,actors)) return piston::Clearance::blocked;
    for (const auto& support : supports)
        if (physical_geometry::overlap(arm,support)) return piston::Clearance::blocked;
    auto first=piston::displacement(*config,from),last=piston::displacement(*config,to);
    const auto current=piston::displacement(*config,state.piston_progress.at(entity));
    for (unsigned n=0;n<3;++n) { first[n]-=current[n]; last[n]-=current[n]; }
    for (const auto& [id,part] : state.placed_components) {
        if (part.parent!=entity || part.kind==C::piston_segment) continue;
        const auto boxes=component_geometry::placed_solids(site.profile,state,id,part);
        for (const auto& box : boxes) {
            const auto volume=swept(shift(box,first,site.profile.meters_per_grid_unit),shift(box,last,site.profile.meters_per_grid_unit));
            if (part.kind!=C::drill_head) {
                const auto clearance=earth(site,volume);
                if (clearance!=piston::Clearance::clear) return clearance;
            }
            if (obstruction(site,state,volume,id,entity,actors)) return piston::Clearance::blocked;
            for (const auto& support : supports)
                if (physical_geometry::overlap(volume,support)) return piston::Clearance::blocked;
        }
        if (part.kind==C::drill_head) {
            auto head=component_geometry::component_bounds(site.profile,part.kind,part.center);
            head=shift(head,current,site.profile.meters_per_grid_unit);
            const auto volume=swept(shift(head,first,site.profile.meters_per_grid_unit),shift(head,last,site.profile.meters_per_grid_unit));
            const auto clearance=earth(site,volume);
            if (clearance!=piston::Clearance::clear) return clearance;
        }
    }
    for (const auto& part : state.topology.parts) {
        if (part.parent!=entity) continue;
        for (const auto& box : physical_geometry::part_solids(site.profile,state,part)) {
            const auto volume=swept(shift(box,first,site.profile.meters_per_grid_unit),shift(box,last,site.profile.meters_per_grid_unit));
            const auto clearance=earth(site,volume);
            if (clearance!=piston::Clearance::clear) return clearance;
            if (obstruction(site,state,volume,part.geometry.id,entity,actors)) return piston::Clearance::blocked;
            for (const auto& support : supports)
                if (physical_geometry::overlap(volume,support)) return piston::Clearance::blocked;
        }
    }
    return piston::Clearance::clear;
}
} // namespace factory::godot_world::physical_site
