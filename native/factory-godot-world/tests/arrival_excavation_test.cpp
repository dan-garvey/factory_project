#include "factory/terrain_surface.hpp"
#include "factory/ore_column_target.hpp"
#include "native/factory-godot-world/src/excavated_terrain.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

using namespace factory;
using V=values::Value;
namespace {
int checks{};
void check(bool okay,const char* why) {++checks;if(!okay) throw std::runtime_error(why);}
}
int main() {
    try {
        world::Profile profile;
        profile.ore_field=true;
        profile.initial_units=4096;
        V::Array axis,heights;
        for(double n:{-32.,-16.,0.,16.,32.}) axis.emplace_back(n);
        for(double z:{-32.,-16.,0.,16.,32.}) for(double x:{-32.,-16.,0.,16.,32.})
            heights.emplace_back(x*.1+z*.05);
        const auto binding=godot_world::terrain_surface::parse({{"axis",V(axis)},
            {"heights",V(heights)},{"obstacles",V(V::Array{})}},profile);
        check(binding.binding.has_value(),"An ordinary trusted terrain binds local excavation.");
        const auto& terrain=binding.binding->surface;
        const auto& adopted=binding.binding->profile;
        check(adopted.excavation && !adopted.ore_field && adopted.collector_faces.empty(),
            "Production terrain retires regional extraction and predefined collector faces.");
        const auto& seed=*adopted.excavation;
        check(seed.columns.size()==1764 && seed.contact_points.size()==1764,
            "The 40 by 40 field plus a zero-stock boundary has real surface contacts.");
        check(seed.grid.pitch==.4125&&40*seed.grid.pitch==16.5,
            "The finer two-H cutting cells preserve the authored 16.5 metre field width.");
        check(excavation::remaining(seed.columns)==4096 && seed.grid.work_per_unit==4*4096 && seed.grid.units_per_step==4,
            "Binding preserves the complete opening reserve and supplied-work scale.");
        std::size_t stocked=0;
        for(const auto& [cell,column]:seed.columns) {
            stocked+=column.initial_units>0;
            const auto& contact=seed.contact_points.at(cell);
            const auto sample=terrain.natural_range(contact[0],contact[2],0,0);
            check(sample && std::abs(sample->second-contact[1])<1e-10,
                "Each hand contact lies on an actual emitted natural triangle.");
        }
        check(stocked==1600,"Exactly 1600 columns carry the finite ore.");
        check(seed.columns.at({12,-16}).initial_units==16 && seed.columns.at({0,0}).initial_units==2 &&
            std::abs(16*seed.grid.height_step/seed.grid.units_per_step-.825)<1e-10,
            "The same finite reserve supplies shallow edges and a deeper 0.825 metre core for extended tooling.");
        materials::State material;material.initial_units=4096;material.stock.source=4096;
        auto columns=seed.columns;
        const excavation::Cell cell{0,0};
        const auto point=seed.contact_points.at(cell);
        const authority::Point actor{point[0],point[1]+1,point[2]};
        const auto target=world::ore_columns::resolve_target(seed,columns,material,
            world::ore_columns::target_id(cell),actor);
        check(target.target && target.target->reach_point==point,
            "Native hand selection uses the bound natural point on an ordinary slope.");
        auto mesh=godot_world::excavated_terrain::build(terrain,seed,columns,material);
        check(mesh.has_value(),"Pristine native terrain geometry is available before any cut.");
        --columns.at(cell).remaining_units;--material.stock.source;++material.stock.collector;
        auto pit=godot_world::excavated_terrain::build(terrain,seed,columns,material);
        const auto bounds=*excavation::surface(seed.grid,cell,columns.at(cell));
        const double x=(bounds.min_x+bounds.max_x)/2,z=(bounds.min_z+bounds.max_z)/2;
        const auto floor=pit->range(x,z,.01,.01);
        check(floor && std::abs(floor->second-bounds.floor)<1e-6,
            "One removed local unit exposes the same lowered floor to native queries.");
        auto active=terrain;active.excavated=std::make_shared<godot_world::terrain_surface::Mesh>(*pit);
        check(active.range(x,z,.01,.01)==floor &&
            active.natural_range(x,z,.01,.01)!=floor,
            "All Surface consumers use derived faces while the pristine producer stays immutable.");
        check(std::abs(active.range(24,24,.1,.1)->second-terrain.range(24,24,.1,.1)->second)<1e-6,
            "Excavating ore cannot flatten or replace distant natural terrain.");
        V::Array bank_heights;
        for (int row=0;row<4;++row) for(double h:{-.02,-.02,-1.65,-1.65}) bank_heights.emplace_back(h);
        const auto bank=godot_world::terrain_surface::parse({{"axis",V(V::Array{V(-128.),V(7.),V(8.),V(128.)})},
            {"heights",V(bank_heights)},{"obstacles",V(V::Array{})}},profile);
        check(bank.binding.has_value(),"A sharp natural bank also binds exact native contact points.");
        std::cout<<"ARRIVAL-EXCAVATION-PASS "<<checks<<" checks\n";
    } catch(const std::exception& e) {std::cerr<<"Failed after "<<checks<<": "<<e.what()<<'\n';return 1;}
}
