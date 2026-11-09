#include "native/factory-godot-world/src/excavated_terrain.hpp"
#include <cmath>
#include <bit>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>

using namespace factory;
namespace terrain=godot_world::excavated_terrain;
namespace {
int checks{};
void check(bool ok,const char* why) {++checks;if(!ok){std::cerr<<why<<'\n';std::exit(1);}}
bool near(double a,double b){return std::abs(a-b)<1e-6;}
std::uint32_t word(std::ifstream& input) {
    std::array<unsigned char,4> bytes{};
    input.read(reinterpret_cast<char*>(bytes.data()),bytes.size());
    check(bool(input),"The captured terrain sample file must be complete.");
    return std::uint32_t(bytes[0]) | (std::uint32_t(bytes[1])<<8) |
        (std::uint32_t(bytes[2])<<16) | (std::uint32_t(bytes[3])<<24);
}
void measure_actual_surface(const char* path) {
    std::ifstream input(path,std::ios::binary);
    check(bool(input),"Open the explicit captured actual-site float32 samples.");
    const auto width=word(input);
    check(width>=2 && width<=1024,"Captured terrain dimensions are bounded.");
    godot_world::terrain_surface::Surface ground;
    for(std::uint32_t z=0;z<width;++z) for(std::uint32_t x=0;x<width;++x) {
        const double px=std::bit_cast<float>(word(input));
        const double py=std::bit_cast<float>(word(input));
        const double pz=std::bit_cast<float>(word(input));
        if(z==0) ground.axis.push_back(px);
        check(px==ground.axis[x] && (z>=ground.axis.size() || pz==ground.axis[z]),
            "Samples retain the source lattice rather than an invented height surface.");
        ground.heights.push_back(py);
    }
    check(input.peek()==std::char_traits<char>::eof(),"Captured samples have no trailing payload.");
    // Explicit proposal measurement: preserve the physical 16.5 m field while
    // using the reconciled 2H cutting pitch. This does not adopt content constants.
    world::ore_columns::Seed seed;
    seed.grid={{-.825,0,-.825},.4125,.20625,1,4096};
    for(int z=0;z<40;++z) for(int x=0;x<40;++x) {
        const excavation::Cell cell{x-4,z-32};
        const auto bounds=excavation::surface(seed.grid,cell,{0,0,0,0});
        check(bounds.has_value(),"Proposal cell bounds are valid.");
        const auto height=ground.natural_range((bounds->min_x+bounds->max_x)/2,
            (bounds->min_z+bounds->max_z)/2,seed.grid.pitch/2,seed.grid.pitch/2);
        check(height.has_value(),"The captured actual site covers every proposal cell.");
        const auto units=4096/1600+(z*40+x<4096%1600?1:0);
        seed.columns.emplace(cell,excavation::Column{units,units,height->second,0});
    }
    for(const std::string mode: {"pristine","fully_excavated","checkerboard"}) {
        auto field=seed.columns;
        materials::State material;material.initial_units=4096;
        for(auto& [cell,column]:field) {
            if(mode=="fully_excavated" || (mode=="checkerboard" && (cell.x+cell.z)%2==0))
                column.remaining_units=0;
            material.stock.source+=column.remaining_units;
        }
        material.stock.collector=4096-material.stock.source;
        const auto mesh=terrain::build(ground,seed,field,material);
        check(mesh.has_value(),"The proposed full-size actual-site geometry is admitted.");
        std::cout<<"{\"scope\":\"captured actual surface, proposed 40x40 columns\",\"mode\":\""<<mode
            <<"\",\"triangles\":"<<mesh->faces.size()<<",\"packed_vertex_bytes\":"<<mesh->faces.size()*36
            <<",\"native_pages\":"<<(mesh->faces.size()+4095)/4096<<"}\n";
    }
}
}
int main(int argc,char** argv) {
    if(argc==2) {measure_actual_surface(argv[1]);return 0;}
    check(argc==1,"Use no arguments for checks, or one actual-site sample file for geometry measurement.");
    godot_world::terrain_surface::Surface ground;
    ground.axis={-2,-1,0,1,2,3};
    ground.heights.assign(36,0);
    world::ore_columns::Seed seed{{{0,0,0},1,.25,1,1},
        {{{0,0},{8,8,0,0}},{{1,0},{8,8,0,0}}}};
    materials::State material;material.initial_units=16;material.stock.source=16;
    auto field=seed.columns;
    auto original=terrain::build(ground,seed,field,material);
    check(original && original->faces.size()==50,"Pristine stock preserves the existing natural triangles.");
    for (double point : {-.4,-.50625,-.6125,-.71875})
        check(original->range(point,point,0,0).has_value(),"A native point query on a shared triangle diagonal never invents a hole.");
    field.at({0,0}).remaining_units=4;material.stock.source=12;material.stock.collector=4;
    auto pit=terrain::build(ground,seed,field,material);
    check(pit.has_value(),"A finite removed column produces a terrain mesh.");
    bool exact_float=true;
    for(const auto& face:pit->faces) for(const auto& point:face) for(double value:point)
        exact_float=exact_float && value==static_cast<double>(static_cast<float>(value));
    check(exact_float,"Native and scene collision consume exactly representable float32 triangle coordinates.");
    const auto inside=terrain::range(*pit,.5,.5,.1,.1);
    check(inside && near(inside->first,-1) && near(inside->second,-1),"The native floor query sees exactly the removed depth.");
    const auto outside=terrain::range(*pit,1.5,.5,.1,.1);
    check(outside && near(outside->first,0) && near(outside->second,0),"The untouched neighbouring stock retains its natural floor.");
    const auto wall=terrain::range(*pit,1,.5,.01,.1);
    check(wall && near(wall->first,-1) && near(wall->second,0),"A footprint crossing the lip sees the retained rock and wall.");
    const auto boundary=terrain::range(*pit,0,.5,0,.1);
    check(boundary && near(boundary->first,-1) && near(boundary->second,0),"The mesh explicitly includes a vertical wall at the cut boundary.");
    field.at({1,0}).remaining_units=6;material.stock.source=10;material.stock.collector=6;
    auto terrace=terrain::build(ground,seed,field,material);
    auto step=terrain::range(*terrace,1,.5,0,.1);
    check(step && near(step->first,-1) && near(step->second,-.5),"Adjacent cuts create a real terrace step instead of closing the pit.");
    field.at({1,0}).remaining_units=4;material.stock.source=8;material.stock.collector=8;
    auto level=terrain::build(ground,seed,field,material);
    auto join=terrain::range(*level,1,.5,.1,.1);
    check(join && near(join->first,-1) && near(join->second,-1),"Equal-depth columns share an open floor without an internal wall.");
    for(std::size_t z=0;z<ground.axis.size();++z) for(std::size_t x=0;x<ground.axis.size();++x)
        ground.heights[z*ground.axis.size()+x]=ground.axis[x]*.2+ground.axis[z]*.1;
    seed.columns.at({0,0}).initial_height=.3;
    seed.columns.at({1,0}).initial_height=.5;
    field=seed.columns;material.stock.source=16;material.stock.collector=0;
    auto natural=terrain::build(ground,seed,field,material);
    auto slope=terrain::range(*natural,.5,.5,0,0);
    check(slope && near(slope->first,.15) && near(slope->second,.15),"Pristine sloped terrain is not flattened to a column seed height.");
    --field.at({0,0}).remaining_units;--material.stock.source;++material.stock.collector;
    auto shallow=terrain::build(ground,seed,field,material);
    auto cut_top=terrain::range(*shallow,.9,.9,0,0);
    auto lower_natural=terrain::range(*shallow,.01,.01,0,0);
    check(cut_top && near(cut_top->second,.05),"Cut plane clips only the natural ground above it.");
    check(lower_natural && near(lower_natural->second,.003),"Lower natural ground is not raised by the cut plane.");
    for(double x:{.1,.2,.4,.7,.9}) for(double z:{.1,.3,.6,.8}) {
        const auto p=terrain::range(*shallow,x,z,0,0);
        check(p && near(p->first,std::min(.2*x+.1*z,.05)) && near(p->second,p->first),
            "Projected floor agrees with the exact clipped native triangle at sample points.");
    }
    check(!terrain::range(*shallow,100,100,.1,.1),"Uncovered terrain does not invent a floor.");
    check(!terrain::range(*shallow,0,0,-1,1),"Invalid query extents refuse.");
    ++material.stock.source;
    check(!terrain::build(ground,seed,field,material),"A material/column mismatch cannot produce independent geometry.");
    --material.stock.source;ground.axis[2]=ground.axis[1];
    check(!terrain::build(ground,seed,field,material),"Malformed producer axes refuse before clipping.");
    ground.axis={-2,-1,0,1,2,3}; ground.heights.assign(36,1e100);
    check(!terrain::build(ground,seed,field,material),"Unrepresentable collision coordinates refuse instead of emitting infinite vertices.");
    std::cout<<"EXCAVATED-TERRAIN-PASS "<<checks<<" checks\n";
}
