#include "factory/checkpoint.hpp"
#include "factory/godot_world.hpp"
#include "factory/mineral_site.hpp"
#include "factory/ore_column_target.hpp"
#include "native/factory-godot-world/src/arrival_excavation.hpp"
#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/tests/site_fixture.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace a = factory::authority;
namespace w = factory::world;
using V=factory::values::Value;
using O=V::Object;
using A=V::Array;
using I=V::Integer;
int checks{};
void check(bool value,const char* message) {++checks;if(!value) throw std::runtime_error(message);}
template<class T> const T& get(const V& v,const char* key) {
    return std::get<T>(std::get<O>(v.storage()).at(key).storage());
}
bool accepted(const V& value) {return get<bool>(value,"accepted");}

void cut(w::World& world,const w::Profile& profile,factory::excavation::Cell cell,const char* request) {
    const auto& seed=*profile.excavation;
    const auto& state=world.snapshot_ref().state;
    auto point=seed.contact_points.at(cell);
    point[1]=factory::excavation::surface(seed.grid,cell,state.excavation->at(cell))->floor+1;
    const w::ObserveActor observe=[point](const std::string& actor)->std::optional<a::ActorCut> {
        return a::ActorCut{actor,point,1,true,3.0};
    };
    a::Object wire{{"context",V("ore-field")},{"client",V("field-client")},{"actor",V("P")},
        {"request",V(request)},{"action",V("harvest_source")},{"target",V(w::ore_columns::target_id(cell))}};
    const auto start=world.command({"P","field-client"},wire,observe);
    check(start.completed()&&start.result&&std::get<bool>(start.result->at("accepted").storage()),
        "Timed work starts at the addressed native column.");
    for(I tick=0;tick<w::manual_cut_ticks;++tick)
        check(world.tick(observe).error==w::TransactionError::none,"The native clock advances the actual hand stroke.");
    wire.erase("target");wire.at("action")=V("finish_harvest");wire.at("request")=V(std::string(request)+"-finish");
    const auto finish=world.command({"P","field-client"},wire,observe);
    check(finish.completed()&&finish.result&&std::get<bool>(finish.result->at("accepted").storage()),
        "Completed work removes exactly one local bite.");
}

void field_cuts_and_checkpoint() {
    auto content=factory::godot_world::make_arrival_configuration(true,false,{"P"});
    auto binding=factory::godot_world::terrain_surface::parse(factory::godot_world::tests::flat_site(),content->profile);
    check(binding.binding.has_value(),"Ordinary terrain binds the finite native column field.");
    auto& profile=binding.binding->profile;
    auto seed=content->seed;
    profile.excavation=factory::godot_world::arrival_excavation::seed(binding.binding->surface,seed.material.stock.source);
    profile.ore_field=false;
    seed.ore_field.reset();seed.excavation=w::ore_columns::initialize(*profile.excavation,seed.material);
    auto world=w::World::create("ore-field",profile,seed);
    check(world!=nullptr,"The bound material and column seed validates together.");
    const factory::excavation::Cell first{0,0},other{10,-10};
    cut(*world,profile,first,"first");
    check(world->snapshot_ref().state.material.stock.source==4095&&
        world->snapshot_ref().state.excavation->at(first).remaining_units==seed.excavation->at(first).remaining_units-1&&
        world->snapshot_ref().state.excavation->at(other)==seed.excavation->at(other),
        "A local cut debits its column and aggregate once while leaving distant ore intact.");
    cut(*world,profile,other,"other");
    check(world->snapshot_ref().state.material.stock.source==4094&&
        world->snapshot_ref().state.excavation->at(first).remaining_units==seed.excavation->at(first).remaining_units-1&&
        world->snapshot_ref().state.excavation->at(other).remaining_units==seed.excavation->at(other).remaining_units-1,
        "A second actual contact cannot drain its neighbouring reserve.");
    const auto encoded=w::encode_checkpoint(profile,world->snapshot());
    check(std::holds_alternative<V>(encoded),"Column depletion and hand receipts encode in the native checkpoint.");
    const auto saved=std::get<V>(encoded);
    const auto& saved_state=get<O>(saved,"state");
    check(get<I>(saved,"schema")==23&&saved_state.contains("excavation"),
        "The checkpoint records the addressed excavation field.");
    auto missing=std::get<O>(saved.storage());auto missing_state=saved_state;
    missing_state.erase("excavation");missing.at("state")=V(missing_state);
    check(std::holds_alternative<w::CheckpointRefusal>(w::decode_checkpoint(profile,"ore-field",V(missing))),
        "A save cannot silently replace its missing field with pristine ore.");
    const auto decoded=w::decode_checkpoint(profile,"ore-field",saved);
    check(std::holds_alternative<w::Snapshot>(decoded)&&
        std::get<w::Snapshot>(decoded).state.excavation==world->snapshot_ref().state.excavation,
        "Save and rejoin preserve every local remaining quantity and depth.");
    auto corrupt=std::get<O>(saved.storage());auto state=get<O>(saved,"state");
    auto columns=get<A>(V(state),"excavation");auto column=std::get<O>(columns.front().storage());
    column.at("remaining")=V(get<I>(V(column),"remaining")+1);columns.front()=V(column);
    state.at("excavation")=V(columns);corrupt.at("state")=V(state);
    check(std::holds_alternative<w::CheckpointRefusal>(w::decode_checkpoint(profile,"ore-field",V(corrupt))),
        "Editing a single column cannot mint material on restore.");
}

void host_column_route() {
    factory::godot_world::Host host;
    check(accepted(host.initialize_arrival("host-field",{"P"}))&&
        accepted(host.configure_terrain(factory::godot_world::tests::flat_site())),"The Host binds ordinary finite terrain.");
    const auto before=host.projection();const auto sources=get<O>(before,"hand_sources");
    const std::string column="ore-column:10:-10";
    const auto source=sources.at(column);const auto position=get<A>(source,"position");
    const auto bounds=get<A>(source,"contact_bounds");const auto low=std::get<A>(bounds[0].storage());
    const auto high=std::get<A>(bounds[1].storage());
    check(std::abs(std::get<double>(high[0].storage())-std::get<double>(low[0].storage())-.4125)<1e-9,
        "A projected hand target addresses one local cutting column.");
    const auto deposit=get<O>(before,"source_deposit");
    check(get<A>(V(deposit),"cells").size()==1600&&get<A>(V(deposit),"cell_regions").size()==1600&&
        get<bool>(V(deposit),"excavation")&&!sources.contains("opening-copper"),
        "Every visible ore cell carries its native address without a regional alias.");
    check(accepted(host.publish_actor("P",{position[0],V(1.0),position[2]},1)),"A trusted actor reaches the distant column.");
    const O wire{{"context",V("host-field")},{"client",V("P")},{"request",V("column-cut")},
        {"action",V("harvest_source")},{"target",V(column)}};
    check(accepted(factory::godot_world::tests::complete_manual_cut(host,"P",wire)),
        "Ordinary Host input completes the timed physical cut.");
    const auto after=host.projection();
    check(get<I>(get<O>(after,"hand_sources").at(column),"remaining")==get<I>(source,"remaining")-1&&
        get<I>(V(get<O>(after,"stock")),"source")==4095,
        "Projection reports one local and aggregate unit removed.");
    factory::godot_world::Host restored;
    check(accepted(restored.initialize_arrival("host-field",{"P"}))&&
        accepted(restored.configure_terrain(factory::godot_world::tests::flat_site()))&&
        accepted(restored.restore_checkpoint(host.checkpoint())),"A fresh Host restores the excavated worksite.");
    const auto resumed=restored.projection();
    check(!factory::values::typed_difference(V(get<O>(after,"hand_sources")),V(get<O>(resumed,"hand_sources")))&&
        !factory::values::typed_difference(host.terrain_projection(0),restored.terrain_projection(0)),
        "Restored local balances and emitted terrain geometry match exactly.");
}
}
int main() {
    try {field_cuts_and_checkpoint();host_column_route();std::cout<<"ORE_FIELD_PASS "<<checks<<'\n';}
    catch(const std::exception& e) {std::cerr<<"ORE_FIELD_FAIL after "<<checks<<" checks: "<<e.what()<<'\n';return 1;}
}
