#include "factory/piston_assembly.hpp"

#include <algorithm>
#include <cmath>

namespace factory::world::piston_assembly {
namespace {
using C=materials::Component;
using P=mechanics::Point;
using I=mechanics::Integer;
bool carried_kind(C kind) {
    return kind==C::drill_head || kind==C::copper_shaft || kind==C::wooden_shaft ||
        kind==C::copper_cog || kind==C::wooden_cog;
}
bool forward_payload(const piston::Config& config, const PlacedComponent& part) {
    const auto axis=(*piston::basis(config.orientation))[1];
    I distance{};
    for (unsigned n=0;n<3;++n) distance-=(part.center[n]-config.center[n])*axis[n];
    return distance>=2;
}
mechanics::Result failure() {
    mechanics::Result result; result.error=mechanics::Error::invalid_part; return result;
}
}
std::optional<piston::Config> configuration(const State& state, const std::string& id) {
    const auto body=state.placed_components.find(id);
    if (body==state.placed_components.end() || body->second.kind!=C::segmented_piston) return std::nullopt;
    piston::Config config{body->second.center,body->second.orientation,0};
    for (const auto& [key,part] : state.placed_components) {
        (void)key;
        if (part.parent==id && part.kind==C::piston_segment) ++config.segments;
    }
    if (!piston::valid(config)) return std::nullopt;
    return config;
}
std::optional<mechanics::Part> spindle(const std::string& id, const PlacedComponent& part) {
    if (!carried_kind(part.kind) || !piston::basis(part.orientation)) return std::nullopt;
    // A drill always uses its local vertical spindle. A free shaft or cog uses
    // local X, the same default axis as its ordinary transmission counterpart.
    const auto axes=*piston::basis(part.orientation);
    const auto direction=axes[part.kind==C::drill_head ? 1 : 0];
    unsigned axis{};
    while (axis<3 && direction[axis]==0) ++axis;
    if (axis==3) return std::nullopt;
    const bool gear=part.kind==C::copper_cog || part.kind==C::wooden_cog;
    return mechanics::Part{id,gear?mechanics::Kind::gear:mechanics::Kind::shaft,
        part.center,static_cast<mechanics::Axis>(axis),gear?2:0,gear?0:2};
}
mechanics::Point displacement(const State& state, const std::string& parent) {
    if (parent.empty()) return {};
    const auto config=configuration(state,parent);
    const auto progress=state.piston_progress.find(parent);
    if (!config || progress==state.piston_progress.end()) throw materials::Error::invalid_state;
    return piston::displacement(*config,progress->second);
}
authority::Point position(const Profile& profile, const State& state, const PlacedComponent& part) {
    const auto delta=displacement(state,part.parent);
    authority::Point result{};
    for (unsigned n=0;n<3;++n)
        result[n]=profile.anchor_offset[n]+profile.meters_per_grid_unit*
            (part.center[n]+double(delta[n])/piston::ticks_per_level);
    return result;
}
const char* placement_refusal(const State& state, const PlacedComponent& part) {
    if (!piston::basis(part.orientation)) return "invalid_orientation";
    if (part.kind==C::segmented_piston) {
        if (!part.parent.empty()) return "unsupported_piston_attachment";
        if (!piston::valid({part.center,part.orientation,0})) return "invalid_area_target";
        return nullptr;
    }
    if (part.parent.empty()) {
        if (part.kind==C::piston_segment) return "segment_requires_piston";
        return part.orientation==0 ? nullptr : "invalid_orientation";
    }
    const auto config=configuration(state,part.parent);
    const auto progress=state.piston_progress.find(part.parent);
    if (!config || progress==state.piston_progress.end()) return "unknown_piston";
    if (progress->second.position!=0) return "retract_before_building";
    if (part.kind==C::piston_segment) {
        if (config->segments==piston::maximum_segments) return "segment_limit";
        if (part.orientation!=config->orientation || part.center!=piston::segment_center(*config,config->segments))
            return "segment_requires_end";
        return nullptr;
    }
    if (!carried_kind(part.kind)) return "unsupported_piston_attachment";
    if (part.kind==C::drill_head && (*piston::basis(part.orientation))[1]!=P{0,1,0})
        return "drill_requires_vertical_input";
    for (const auto& [id,other] : state.placed_components) {
        (void)id;
        if (other.parent==part.parent && other.center==part.center) return "occupied";
    }
    if (!forward_payload(*config,part)) return "attachment_requires_forward_socket";
    auto payload=spindle("candidate",part);
    if (!payload) return "invalid_orientation";
    const auto native=piston::spindles(*config,part.parent);
    std::vector<mechanics::Part> parts{native[2],*payload};
    for (const auto& [id,other] : state.placed_components)
        if (other.parent==part.parent) if (auto rotor=spindle(id,other)) parts.push_back(*rotor);
    const auto graph=mechanics::evaluate(parts,{});
    if (!graph.accepted()) return "invalid_mechanics";
    for (const auto& component : graph.components)
        if (std::find(component.parts.begin(),component.parts.end(),"candidate")!=component.parts.end() &&
            std::find(component.parts.begin(),component.parts.end(),native[2].id)!=component.parts.end()) return nullptr;
    return "attachment_requires_connection";
}
const char* reclaim_refusal(const State& state, const std::string& id) {
    const auto found=state.placed_components.find(id);
    if (found==state.placed_components.end()) return "unknown_target";
    const auto& part=found->second;
    if (part.kind==C::stationary_mount)
        for (const auto& [key,body] : state.placed_components) {
            (void)key;
            if (body.kind==C::segmented_piston && body.orientation==0 &&
                body.center==P{part.center[0],part.center[1]+5,part.center[2]}) return "piston_on_mount";
        }
    if (part.kind==C::segmented_piston) {
        for (const auto& [key,other] : state.placed_components) {
            (void)key;
            if (other.parent==id) return "parts_on_piston";
        }
    }
    if (!part.parent.empty()) {
        const auto config=configuration(state,part.parent);
        const auto progress=state.piston_progress.find(part.parent);
        if (!config || progress==state.piston_progress.end()) return "unknown_piston";
        if (progress->second.position!=0) return "retract_before_building";
        if (part.kind==C::piston_segment && part.center!=piston::segment_center(*config,config->segments-1))
            return "remove_end_segment_first";
    }
    return nullptr;
}
bool valid(const State& state) {
    std::size_t bodies{};
    for (const auto& [id,part] : state.placed_components) {
        if (!piston::basis(part.orientation)) return false;
        if (part.kind==C::segmented_piston) {
            ++bodies;
            const auto config=configuration(state,id);
            const auto progress=state.piston_progress.find(id);
            if (!part.parent.empty() || !config || progress==state.piston_progress.end() ||
                !piston::valid(*config,progress->second)) return false;
            std::set<P> sections, payload_centers;
            std::vector<mechanics::Part> rotors{piston::spindles(*config,id)[2]};
            for (const auto& [key,child] : state.placed_components) if (child.parent==id) {
                if (child.kind==C::piston_segment) {
                    if (child.orientation!=part.orientation || !sections.insert(child.center).second) return false;
                } else {
                    const auto rotor=spindle(key,child);
                    if (!rotor || !forward_payload(*config,child) || !payload_centers.insert(child.center).second ||
                        (child.kind==C::drill_head && (*piston::basis(child.orientation))[1]!=P{0,1,0})) return false;
                    rotors.push_back(*rotor);
                }
            }
            for (I n=0;n<config->segments;++n)
                if (!sections.contains(piston::segment_center(*config,n))) return false;
            const auto graph=mechanics::evaluate(rotors,{});
            if (!graph.accepted() || graph.components.size()!=1) return false;
        } else if (part.parent.empty()) {
            if (part.kind==C::piston_segment || part.orientation!=0) return false;
        } else {
            if (!configuration(state,part.parent) ||
                (part.kind!=C::piston_segment && !carried_kind(part.kind))) return false;
        }
    }
    return bodies==state.piston_progress.size();
}
bool socket_reach_target(const Profile& profile,const State& state,const std::string& owner,
        const P& reference,const authority::Point& target) {
    const auto power=drive_power(profile,state);
    const auto socket=rotary_socket(power,owner,reference);
    if (!socket) {
        authority::Point fixed{};
        for (unsigned n=0;n<3;++n) fixed[n]=reference[n]*profile.meters_per_grid_unit+profile.anchor_offset[n];
        return owner.empty() && fixed==target;
    }
    std::string parent;
    if (const auto part=state.placed_components.find(owner);part!=state.placed_components.end()) {
        parent=part->second.parent;
        if (part->second.kind==C::segmented_piston && socket->mechanical_part==owner+"/output") parent=owner;
    }
    authority::Point base{};
    for (unsigned n=0;n<3;++n) base[n]=profile.anchor_offset[n]+reference[n]*profile.meters_per_grid_unit;
    if (parent.empty()) return base==target;
    const auto config=configuration(state,parent);
    if (!config) return false;
    const auto axis=(*piston::basis(config->orientation))[1];
    double travel{};
    for (unsigned n=0;n<3;++n) {
        const auto delta=(target[n]-base[n])/profile.meters_per_grid_unit;
        if (!axis[n] && std::abs(delta)>1e-9) return false;
        travel-=delta*axis[n];
    }
    // Tick positions are native state, not construction commands. Receipts
    // preserve the sampled target; restore checks that it lies on this real
    // owned stroke rather than pretending a later pose was the earlier one.
    return travel>=-1e-9 && travel<=config->segments*4+1e-9 &&
        std::abs(travel*piston::ticks_per_level-std::round(travel*piston::ticks_per_level))<1e-6;
}
bool advance(State& state, const DrivePower& drive, const ObservePiston& observe) {
    for (auto& [id,progress] : state.piston_progress) {
        const auto config=configuration(state,id);
        const auto powered=drive.mechanical.motion.find(id);
        if (!config || powered==drive.mechanical.motion.end()) return false;
        const auto rate=powered->second.state==mechanics::MotionState::rotating ?
            powered->second.rate : mechanics::Rate{};
        const auto proposal=piston::advance(*config,progress,rate,
            [&](const auto& from,const auto& to,const auto& swept) {
                return observe ? observe(state,id,from,to,swept) : piston::Clearance::unavailable;
            });
        if (proposal.error!=piston::Error::none) return false;
        progress=proposal.progress;
    }
    return true;
}
mechanics::Result power(const State& state, const std::vector<mechanics::Part>& parts,
        const std::vector<mechanics::Drive>& sources, const std::vector<mechanics::BeltSpan>& belts,
        const std::map<std::string,std::string>& owners) {
    if (std::none_of(state.placed_components.begin(),state.placed_components.end(),
            [](const auto& entry) { return entry.second.kind==C::segmented_piston; }))
        return mechanics::evaluate(parts,sources,belts,mechanics::SourcePolicy::overpower);
    std::map<std::string,std::vector<mechanics::Part>> frames;
    std::map<std::string,std::string> frame_for;
    std::vector<mechanics::Engagement> edges;
    for (const auto& part : parts) {
        std::string frame;
        const auto owner=owners.find(part.id);
        const auto component=state.placed_components.find(owner==owners.end()?part.id:owner->second);
        if (component!=state.placed_components.end()) {
            frame=component->second.parent;
            if (component->second.kind==C::segmented_piston && part.id==component->first+"/output") frame=component->first;
        }
        frame_for.emplace(part.id,frame);
        frames[frame].push_back(part);
    }
    std::map<std::string,std::vector<mechanics::BeltSpan>> frame_belts;
    for (const auto& belt : belts) {
        if (!frame_for.contains(belt.first_shaft) || !frame_for.contains(belt.last_shaft) ||
            frame_for.at(belt.first_shaft)!=frame_for.at(belt.last_shaft)) return failure();
        frame_belts[frame_for.at(belt.first_shaft)].push_back(belt);
    }
    for (const auto& [frame,group] : frames) {
        const auto contacts=mechanics::evaluate(group,{},frame_belts[frame]);
        if (!contacts.accepted()) return contacts;
        edges.insert(edges.end(),contacts.engagements.begin(),contacts.engagements.end());
        if (!frame.empty()) {
            const auto config=configuration(state,frame);
            if (!config) return failure();
            edges.push_back(piston::through_connection(*config,frame));
        }
    }
    return mechanics::resolve_engagements(parts,sources,edges,mechanics::SourcePolicy::overpower);
}
} // namespace factory::world::piston_assembly
