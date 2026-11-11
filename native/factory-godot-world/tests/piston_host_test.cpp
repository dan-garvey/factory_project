#include "factory/godot_world.hpp"
#include "factory/piston.hpp"
#include "site_fixture.hpp"

#include <iostream>
#include <stdexcept>

namespace {
using V = factory::values::Value;
using O = V::Object;
using A = V::Array;
using I = V::Integer;
using Host = factory::godot_world::Host;
int checks{};
template<class T> T get(const V& value, const char* key) {
    return std::get<T>(std::get<O>(value.storage()).at(key).storage());
}
void check(bool okay, const char* why) {
    ++checks;
    if (!okay) throw std::runtime_error(why);
}
O level_site() {
    auto site=factory::godot_world::tests::flat_site();
    site.at("heights")=V(A{V(0.0),V(0.0),V(0.0),V(0.0)});
    return site;
}
struct Fixture {
    Host host;
    I request{}, epoch{};
    Fixture() {
        check(get<bool>(host.initialize_arrival_advanced_fixture("surface-drill", {"P"}), "accepted"), "Initialize arrival.");
        check(get<bool>(host.configure_terrain(level_site()), "accepted"), "Bind real finite columns.");
    }
    void move(double x, double y, double z) {
        check(get<bool>(host.publish_actor("P", {V(x), V(y), V(z)}, ++epoch), "accepted"), "Publish observed actor.");
    }
    V command(const char* action, O args = {}) {
        args.emplace("context", V("surface-drill")); args.emplace("client", V("P"));
        args.emplace("request", V(std::to_string(++request))); args.emplace("action", V(action));
        try { return host.command("P", args); }
        catch (factory::materials::Error) { throw std::runtime_error(std::string(action)+": invalid native state"); }
    }
    V accepted(const char* action, O args = {}) {
        auto result = command(action, args);
        if (!get<bool>(result, "accepted"))
            throw std::runtime_error(std::string(action) + ": " + get<std::string>(result, "reason"));
        ++checks; return result;
    }
    void saveable(const char* label) {
        const auto result=host.validate_checkpoint(host.checkpoint());
        if (!get<bool>(result,"accepted")) throw std::runtime_error(std::string(label)+": "+get<std::string>(result,"reason"));
        ++checks;
    }
    void stock() {
        move(6.6, 1, 3.3);
        accepted("set_developer_conveniences", {{"enabled", V(true)}});
        for (int n=0; n<8; ++n) accepted("harvest_source", {{"target", V("tree-east-south")}});
        move(6.6, 1, 11.55);
        for (int n=0; n<8; ++n) accepted("harvest_source", {{"target", V("tree-east-north")}});
        move(6.6,1,-1.65);
        for (int n=0; n<4; ++n) accepted("harvest_source", {{"target", V("tree-east-upstream")}});
        move(-1.2375, 1, 0);
        for (int n=0; n<22; ++n)
            accepted("harvest_source", {{"target", V(factory::godot_world::tests::reachable_ore(host,"P"))}});
        move(3.3, 1, 4.8);
        for (const auto kind : {"stationary_mount", "segmented_piston", "piston_segment", "drill_head", "hand_crank", "hand_crank", "hand_crank"})
            accepted("craft_component", {{"entity", V("pod-fabrication-hub")}, {"component", V(kind)}});
        accepted("set_developer_conveniences", {{"enabled", V(false)}});
    }
};
void horizontal_reuse() {
    Fixture f; f.stock();
    for (const auto kind : {"copper_shaft","copper_cog"})
        f.accepted("craft_component",{{"entity",V("pod-fabrication-hub")},{"component",V(kind)}});
    f.accepted("craft_part",{{"entity",V("pod-fabrication-hub")},{"role",V("vertical_gearbox")},{"half_span",V(I{0})}});
    I orientation=-1;
    for (I n=0;n<24;++n) {
        const auto basis=*factory::piston::basis(n);
        if (basis[0]==factory::mechanics::Point{0,0,-1} && basis[1]==factory::mechanics::Point{-1,0,0}) orientation=n;
    }
    check(orientation>=0,"Horizontal orientation has side feed and vertical tool inputs.");
    f.move(8.25,1,2);
    const auto place=[&](const char* kind,I x,const std::string& parent,I turn) {
        return get<std::string>(f.accepted("place_component",{{"component",V(kind)},
            {"center",V(A{V(x),V(I{0}),V(I{0})})},{"orientation",V(turn)},{"parent",V(parent)}}),"entity");
    };
    const auto body=place("segmented_piston",40,"",orientation);
    place("piston_segment",36,body,orientation);
    const auto shaft=place("copper_shaft",44,body,0);
    const auto cog=place("copper_cog",48,body,0);
    const auto gearbox=get<std::string>(f.accepted("place_relay",{{"kind",V("vertical_gearbox")},
        {"center",V(A{V(I{40}),V(I{4}),V(I{0})})},{"axis",V("z")}}),"entity");
    f.saveable("Assembled horizontal frame before power");
    const auto cranks=get<O>(f.host.projection(),"crank_items");
    auto item=cranks.begin(); const auto tool=item++->first,feed=item++->first,reverse=item++->first;
    const auto attach=[&](const std::string& crank,const std::string& owner,A port,A face) {
        f.accepted("attach_hand_crank",{{"entity",V(owner)},{"crank",V(crank)},{"port",V(port)},{"face",V(face)}});
    };
    attach(tool,gearbox,{V(I{42}),V(I{4}),V(I{0})},{V(I{1}),V(I{0}),V(I{0})});
    attach(feed,body,{V(I{40}),V(I{0}),V(I{-2})},{V(I{0}),V(I{0}),V(I{-1})});
    attach(reverse,body,{V(I{40}),V(I{0}),V(I{2})},{V(I{0}),V(I{0}),V(I{1})});
    const auto pulse=[&](const std::string& crank,int count) {
        for (int n=0;n<count;++n) f.accepted("operate_hand_crank",{{"entity",V(crank)}});
    };
    const auto progress=[&] {
        return get<I>(V(get<O>(get<O>(f.host.projection(),"placed_components").at(body),"piston")),"position_ticks");
    };
    pulse(feed,1);
    check(progress()==256,"Direct side feed advances horizontal travel independently of the tool gearbox.");
    const auto moved=get<A>(get<O>(f.host.projection(),"placed_components").at(shaft),"position");
    check(std::get<double>(moved[0].storage())>44*.20625,"Native projection moves the carried shaft.");
    pulse(tool,1);
    check(progress()==256,"Tool pulse leaves horizontal feed stopped.");
    f.move(11.05,.8,0);
    pulse(feed,20);
    check(progress()<4096,"A real actor stops the swept payload before the stroke limit.");
    f.move(8.25,1,2);
    pulse(feed,20);
    check(progress()==4096,"Clearance permits the full paid one-unit stroke.");
    pulse(feed,4);
    check(progress()==4096,"Feed cannot overrun the last extension.");
    f.saveable("Horizontal displaced custody");
    pulse(reverse,20);
    check(progress()==0,"The opposite feed face retracts to the original limit.");
    f.accepted("reclaim_component",{{"entity",V(cog)}});
    f.accepted("reclaim_component",{{"entity",V(shaft)}});
}
}
int main() {
    try {
        Fixture f; f.stock(); f.move(6.6,1,-4.95);
        const auto place=[&](const char* kind, I y, const std::string& parent="") {
            O args{{"component",V(kind)},{"center",V(A{V(I{24}),V(y),V(I{-24})})}};
            if (!parent.empty()) args.emplace("parent",V(parent));
            return get<std::string>(f.accepted("place_component",args),"entity");
        };
        const auto mount=place("stationary_mount",0);
        const auto body=place("segmented_piston",5);
        const auto segment=place("piston_segment",9,body);
        const auto head=place("drill_head",1,body);
        const auto cranks=get<O>(f.host.projection(),"crank_items");
        auto item=cranks.begin(); const auto tool=item++->first,feed=item++->first,reverse=item++->first;
        const auto attach=[&](const std::string& crank,I x,I z,I dx,I dz) {
            f.accepted("attach_hand_crank",{{"entity",V(body)},{"crank",V(crank)},
                {"port",V(A{V(x),V(I{5}),V(z)})},{"face",V(A{V(dx),V(I{0}),V(dz)})}});
        };
        attach(tool,24,-22,0,1); attach(feed,26,-24,1,0); attach(reverse,22,-24,-1,0);
        const auto source=[&] { return get<I>(V(get<O>(f.host.projection(),"stock")),"source"); };
        const auto progress=[&] {
            return get<I>(V(get<O>(get<O>(f.host.projection(),"placed_components").at(body),"piston")),"position_ticks");
        };
        const auto pulse=[&](const std::string& crank,int count) {
            for (int n=0;n<count;++n) f.accepted("operate_hand_crank",{{"entity",V(crank)}});
        };
        const auto before=source();
        pulse(feed,4);
        check(progress()==0 && source()==before,"Feed cannot push an unpowered cutter through intact earth.");
        pulse(tool,64);
        check(source()==before-16 && progress()==0,"Independent tool power forms the first 16-copper divot without feeding.");
        pulse(feed,4);
        check(progress()==1024 && source()==before-16,"Feed advances only into the cleared one-H band.");
        pulse(feed,4);
        check(progress()==1024,"Fresh ground stops the feed without tunnelling.");
        const auto partial=f.host.checkpoint();
        const auto valid=f.host.validate_checkpoint(partial);
        if (!get<bool>(valid,"accepted")) throw std::runtime_error("Partial checkpoint: "+get<std::string>(valid,"reason"));
        Host restored;
        check(get<bool>(restored.initialize_arrival_advanced_fixture("surface-drill",{"P"}),"accepted") &&
            get<bool>(restored.configure_terrain(level_site()),"accepted"),"Restore fixture initialized.");
        const auto rejoin=restored.restore_checkpoint(partial);
        if (!get<bool>(rejoin,"accepted")) throw std::runtime_error("Restore: "+get<std::string>(rejoin,"reason"));
        check(!factory::values::typed_difference(partial,restored.checkpoint()),"A fresh Host resumes the exact partial stroke and copper custody.");
        check(!get<bool>(f.command("reclaim_component",{{"entity",V(segment)}}),"accepted"),"Extended sections cannot be removed.");
        pulse(tool,64);
        check(source()==before-32 && progress()==1024,"The same translated head cuts the next local band.");
        pulse(feed,4); check(progress()==2048,"Second cleared band is reachable.");
        pulse(reverse,8); check(progress()==0,"Opposite feed input retracts independently of tool rotation.");
        f.accepted("reclaim_component",{{"entity",V(segment)}});
        check(!get<bool>(f.command("reclaim_component",{{"entity",V(mount)}}),"accepted"),"Mounted piston retains its support.");
        I loose{}; for (const auto& drop:get<A>(f.host.projection(),"dropped_material")) loose+=get<I>(drop,"raw");
        check(loose==32,"All mined copper remains in loose custody; piston adds no automatic collection.");
        check(get<bool>(f.host.validate_checkpoint(f.host.checkpoint()),"accepted"),"Retracted assembly and reclaimed segment remain saveable.");
        (void)head;
        horizontal_reuse();
        std::cout<<"PISTON-HOST-PASS "<<checks<<" checks\n";
    } catch (const std::exception& e) { std::cerr<<"After "<<checks<<": "<<e.what()<<'\n'; return 1; }
}
