#include "factory/ore_column_target.hpp"

#include <iostream>
#include <limits>
#include <stdexcept>

namespace o=factory::world::ore_columns;
namespace e=factory::excavation;
namespace m=factory::materials;
using V=factory::values::Value;
using O=V::Object;
namespace {
int checks{};
void check(bool value,const char* why) {++checks; if(!value) throw std::runtime_error(why);}
struct Fixture {
    o::Seed seed;
    o::Field field;
    m::State material;
    Fixture() {
        seed.grid={{0,0,0},1,1,4,4096};
        for(e::Integer x=0;x<4;++x) for(e::Integer z=0;z<4;++z)
            seed.columns[{x,z}]={80,80,0,0};
        field=seed.columns; material.initial_units=1280; material.stock.source=1280;
        material.cargo.emplace("bin",m::Cargo{});
    }
    void lower(e::Cell cell,e::Integer quantity) {
        field.at(cell).remaining_units-=quantity; material.stock.source-=quantity;
        material.cargo.at("bin").raw_units+=quantity;
    }
    o::TargetResult select(e::Cell cell,e::Point actor) const {
        return o::resolve_target(seed,field,material,o::target_id(cell),actor);
    }
};
void identities_and_top() {
    for(e::Cell cell: {e::Cell{0,0},e::Cell{-2,3},
            e::Cell{std::numeric_limits<e::Integer>::min(),std::numeric_limits<e::Integer>::max()}})
        check(o::target_cell(o::target_id(cell))==cell,"Signed exact cell IDs round-trip canonically.");
    for(const auto* bad:{"ore","ore-region-1","ore-column:","ore-column:+1:0",
            "ore-column:01:0","ore-column:-0:0","ore-column:1:2:3","ore-column:1 :2",
            "ore-column:9223372036854775808:0"})
        check(!o::target_cell(bad),"Generic, aliased and malformed ore target IDs refuse.");
    Fixture f;
    const e::Point actor{.5,1,.5};
    const auto first=f.select({0,0},actor);
    check(first.target&&first.target->cutting.face==e::Face::top&&
        first.target->reach_point==e::Point{.5,0,.5},"Top contact derives from the actual native surface.");
    check(first.target->columns.size()==1,"A vertical hand stroke records only its local column.");
    const auto facts=o::contact_facts(*first.target);
    check(facts.size()==o::contact_fact_count &&
        bool(o::historical_contact(f.seed,o::target_id({0,0}),actor,facts)),
        "Compact local facts validate against immutable seed geometry.");
    f.lower({0,0},1);
    const auto next=f.select({0,0},actor);
    check(next.target&&next.target->floor_before==-.25&&next.target->before.remaining_units==79,
        "The next stroke follows the actually excavated local floor.");
    check(bool(o::historical_contact(f.seed,o::target_id({0,0}),actor,facts)),
        "An old receipt validates its own surface, without pretending current state is its historical field.");
    check(f.select({90,0},actor).error==o::TargetError::unknown_target,
        "A distant unknown address cannot consume another source.");
    check(f.select({0,0},{.5,-1,.5}).error==o::TargetError::occluded,
        "An actor below retained ground cannot reach up through the same intact column.");
    check(f.select({0,0},{std::numeric_limits<double>::quiet_NaN(),1,0}).error==o::TargetError::invalid_actor,
        "Nonfinite native observations cannot create target geometry.");
}
void terrain_occlusion_and_sides() {
    Fixture f;
    f.lower({0,0},4); f.lower({2,0},4);
    const e::Point actor{.5,-.1,.5};
    check(f.select({2,0},actor).error==o::TargetError::occluded,
        "An intervening retained column blocks reach to another lowered floor.");
    const auto side=f.select({1,0},actor);
    check(side.target&&side.target->cutting.face==e::Face::west&&
        side.target->columns.size()==2&&side.target->reach_point==e::Point{1,-.1,.5},
        "A lower adjacent terrace exposes the actual upper side bite.");
    auto facts=o::contact_facts(*side.target);
    check(bool(o::historical_contact(f.seed,o::target_id({1,0}),actor,facts)),
        "Side receipt retains precisely the lower neighbour needed for exposure.");
    auto witnesses=std::get<V::Array>(facts.at("ore_contact_columns").storage());
    auto changed=std::get<O>(witnesses.front().storage()); changed.at("remaining")=V(e::Integer{80});
    witnesses.front()=V(changed); facts.at("ore_contact_columns")=V(witnesses);
    check(!o::historical_contact(f.seed,o::target_id({1,0}),actor,facts),
        "A receipt claiming intact neighbouring ground cannot certify side exposure.");
    f.lower({1,0},4);
    const auto reachable=f.select({2,0},actor);
    check(reachable.target&&reachable.target->cutting.face==e::Face::top&&
        reachable.target->columns.size()==3,
        "Clearing the intervening ground makes the same local pit floor reachable.");
    check(bool(o::historical_contact(f.seed,o::target_id({2,0}),actor,o::contact_facts(*reachable.target))),
        "The receipt checks every column intersected by the clear segment.");
}
void supplied_surface_point() {
    Fixture f;
    f.seed.contact_points.emplace(e::Cell{0,0},e::Point{.9,0,.8});
    const e::Point actor{.5,1,.5};
    auto target=f.select({0,0},actor);
    check(target.target && target.target->reach_point==e::Point{.9,0,.8},
        "A supplied natural maximum supplies real hand contact instead of a hovering nearest plane point.");
    auto facts=o::contact_facts(*target.target);
    check(bool(o::historical_contact(f.seed,o::target_id({0,0}),actor,facts)),
        "Historical contact is bound to the same immutable natural surface point.");
    facts.at("ore_contact_point")=V(V::Array{V(.5),V(0.0),V(.5)});
    check(!o::historical_contact(f.seed,o::target_id({0,0}),actor,facts),
        "A receipt cannot substitute a closer synthetic contact on a sloped cutting plane.");
    f.lower({0,0},1);
    target=f.select({0,0},actor);
    check(target.target && target.target->reach_point==e::Point{.9,-.25,.8},
        "After removal the real contact follows the local exposed floor.");
    f.seed.contact_points.at({0,0})[0]=1.1;
    check(f.select({0,0},actor).error==o::TargetError::invalid_state,
        "A trusted point outside its addressed column cannot admit a cut.");
}
void receipt_refusals() {
    Fixture f; const e::Point actor{.5,1,.5};
    const auto target=*f.select({0,0},actor).target;
    const auto original=o::contact_facts(target);
    const auto valid=[&](const O& facts){return bool(o::historical_contact(f.seed,o::target_id({0,0}),actor,facts));};
    for(const auto* key: {"ore_cell","ore_remaining_before","ore_work_before","ore_floor_before",
            "ore_face","ore_cut_center","ore_contact_point","ore_contact_columns"}) {
        auto facts=original; facts.erase(key);
        check(!valid(facts),"A missing local receipt fact refuses.");
    }
    auto facts=original; facts.at("ore_floor_before")=V(-1.0);
    check(!valid(facts),"A fictitious lower contact floor does not match finite before-stock.");
    facts=original; facts.at("ore_remaining_before")=V(e::Integer{81});
    check(!valid(facts),"Before-stock cannot exceed the trusted column reserve.");
    facts=original; facts.at("ore_work_before")=V(e::Integer{4096});
    check(!valid(facts),"A supposedly completed partial bite cannot sit in uncut stock.");
    facts=original; facts.at("ore_face")=V(e::Integer{99});
    check(!valid(facts),"Unknown working-face enumerations refuse.");
    facts=original; facts.at("ore_cut_center")=V(V::Array{V(4.5),V(0.0),V(.5)});
    check(!valid(facts),"A contact center cannot be moved outside the addressed cell.");
    facts=original; facts.at("ore_contact_point")=V(V::Array{V(.5),V(-1.0),V(.5)});
    check(!valid(facts),"A reach point beneath the exposed surface refuses.");
    facts=original; auto witnesses=std::get<V::Array>(facts.at("ore_contact_columns").storage());
    witnesses.push_back(witnesses.front()); facts.at("ore_contact_columns")=V(witnesses);
    check(!valid(facts),"Duplicate or unnecessary obstruction witnesses cannot hide another column.");
    check(!o::historical_contact(f.seed,o::target_id({1,0}),actor,original),
        "The receipt cannot be retargeted to another ore column.");
    f.lower({0,0},80);
    check(f.select({0,0},actor).error==o::TargetError::exhausted,
        "An exhausted selected column cannot borrow the rest of the deposit.");
    ++f.material.stock.source;
    check(f.select({0,0},actor).error==o::TargetError::invalid_state,
        "Local projection refuses a mismatch with canonical source stock.");
}
void bounded_receipt() {
    o::Seed seed; seed.grid.work_per_unit=4096;
    for(e::Integer x=0;x<140;++x) seed.columns[{x,0}]={1,1,0,0};
    m::State state; state.initial_units=state.stock.source=140;
    check(o::resolve_target(seed,seed.columns,state,o::target_id({139,0}),{.5,1000,.5}).error==
        o::TargetError::contact_too_complex,"A far-reaching segment cannot dump an unbounded terrain snapshot into history.");
}
void batch_contacts_preserve_admission() {
    Fixture f;
    f.lower({0,0},4); f.lower({2,0},4);
    const e::Point actor{.5,-.1,.5};
    const std::vector<std::string> ids{o::target_id({0,0}),o::target_id({1,0}),
        o::target_id({2,0}),o::target_id({90,0}),"ore"};
    const auto batch=o::resolve_targets(f.seed,f.field,f.material,ids,actor);
    check(batch.size()==ids.size(),"Projection keeps every requested candidate in order.");
    for(std::size_t i=0;i<ids.size();++i) {
        const auto single=o::resolve_target(f.seed,f.field,f.material,ids[i],actor);
        check(batch[i].error==single.error && bool(batch[i].target)==bool(single.target),
            "Batch admission preserves local, occluded and unknown refusals.");
        if(single.target)
            check(!factory::values::typed_difference(V(o::contact_facts(*batch[i].target)),
                V(o::contact_facts(*single.target))),"Batch contact preserves exact history witnesses.");
    }
    f.field.at({3,3}).work=4096;
    for(const auto& result:o::resolve_targets(f.seed,f.field,f.material,ids,actor))
        check(result.error==o::TargetError::invalid_state,
            "A corrupt column away from the reach segment still invalidates the whole batch.");
}
} // namespace
int main() {
    try {
        identities_and_top(); terrain_occlusion_and_sides(); supplied_surface_point(); receipt_refusals(); bounded_receipt(); batch_contacts_preserve_admission();
        std::cout<<checks<<" ore-column target and receipt checks passed.\n";
    } catch(const std::exception& error) {
        std::cerr<<"Failed after "<<checks<<" checks: "<<error.what()<<'\n'; return 1;
    }
}
