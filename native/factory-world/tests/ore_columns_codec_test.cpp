#include "factory/ore_columns_codec.hpp"
#include <cstdlib>
#include <iostream>

using namespace factory;
using namespace world::ore_columns;
using V=values::Value;
namespace {
int checks{};
void check(bool ok,const char* why) {
    ++checks;
    if (!ok) { std::cerr<<why<<'\n'; std::exit(1); }
}
}
int main() {
    Seed seed{{{1.0,3.0,2.0},.825,.20625,8,4},
        {{{0,0},{64,64,.123,0}},{{1,0},{32,32,.2,0}},{{-1,0},{0,0,0.0,0}}}};
    materials::State material;
    material.initial_units=96;
    material.stock.source=96;
    auto initial=initialize(seed,material);
    check(initial.has_value(),"Trusted finite seed initializes.");
    auto columns=*initial;
    columns.at({0,0}).remaining_units-=3;
    columns.at({1,0}).work=2;
    material.stock.source-=3;
    material.stock.collector=3;
    auto encoded=encode_field(seed,columns,material);
    check(encoded && decode_field(seed,*encoded,material)==columns,
        "Sloped natural height, removed depth and incomplete work round-trip.");
    check(encode_seed(seed).has_value(),"The immutable seed has an exact Profile identity.");
    auto entries=std::get<V::Array>(encoded->storage());
    auto bad=entries;
    bad.push_back(bad.front());
    check(!decode_field(seed,V(bad),material),"Extra columns are refused.");
    bad=entries; bad[1]=bad.front();
    check(!decode_field(seed,V(bad),material),"Duplicated addressed columns are refused.");
    auto item=std::get<V::Object>(entries[1].storage());
    item["remaining"]=V(V::Integer{64}); bad=entries; bad[1]=V(item);
    check(!decode_field(seed,V(bad),material),"Refilled stock cannot diverge from source custody.");
    item=std::get<V::Object>(entries[1].storage()); item["work"]=V(V::Integer{4});
    bad=entries; bad[1]=V(item);
    check(!decode_field(seed,V(bad),material),"Complete work cannot be banked without producing its bite.");
    item=std::get<V::Object>(entries[1].storage()); item["height"]=V(999.0);
    bad=entries; bad[1]=V(item);
    check(!decode_field(seed,V(bad),material),"Saved mutable stock cannot replace the trusted natural height.");
    item=std::get<V::Object>(entries[1].storage()); item["remaining"]=V(61.0);
    bad=entries; bad[1]=V(item);
    check(!decode_field(seed,V(bad),material),"Fractional stock is not coerced.");
    item=std::get<V::Object>(entries[1].storage()); item["x"]=V(V::Integer{999});
    bad=entries; bad[1]=V(item);
    check(!decode_field(seed,V(bad),material),"Unknown ore cells are refused.");
    auto changed=seed;
    changed.columns.at({0,0}).initial_height+=.2;
    check(values::typed_difference(*encode_seed(seed),*encode_seed(changed)).has_value(),
        "A different natural terrain surface changes trusted Profile identity.");
    changed=seed; --changed.columns.at({0,0}).remaining_units;
    check(!encode_seed(changed),"A depleted profile cannot seed fresh stock.");
    changed=seed; changed.contact_points.emplace(excavation::Cell{0,0},excavation::Point{1.4,3.123,2.4});
    check(encode_seed(changed).has_value() &&
        values::typed_difference(*encode_seed(seed),*encode_seed(changed)).has_value(),
        "Actual natural surface points participate in exact trusted Profile identity.");
    changed.contact_points.at({0,0})[1]=3.0;
    check(!encode_seed(changed),"A surface point below the declared natural maximum is refused.");
    changed=seed; changed.contact_points.emplace(excavation::Cell{99,0},excavation::Point{1.4,3.123,2.4});
    check(!encode_seed(changed),"A surface contact cannot name an unknown column.");
    std::cout<<"ORE-COLUMNS-CODEC-PASS "<<checks<<" checks\n";
}
