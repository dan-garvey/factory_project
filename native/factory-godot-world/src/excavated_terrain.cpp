#include "excavated_terrain.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::godot_world::excavated_terrain {
namespace {
using Point=authority::Point;
using Polygon=std::vector<Point>;
constexpr std::size_t maximum_faces=2000000;
Polygon clip(const Polygon& polygon,unsigned axis,double plane,bool above) {
    Polygon out;
    if (polygon.empty()) return out;
    for (std::size_t i=0;i<polygon.size();++i) {
        const auto& a=polygon[i]; const auto& b=polygon[(i+1)%polygon.size()];
        const bool ia=above ? a[axis]>=plane:a[axis]<=plane;
        const bool ib=above ? b[axis]>=plane:b[axis]<=plane;
        if (ia) out.push_back(a);
        if (ia!=ib) {
            const double t=(plane-a[axis])/(b[axis]-a[axis]);
            Point p{}; for(unsigned j=0;j<3;++j) p[j]=a[j]+t*(b[j]-a[j]);
            p[axis]=plane;
            out.push_back(p);
        }
    }
    return out;
}
Polygon rectangle(Polygon p,double left,double right,double near,double far) {
    p=clip(p,0,left,true); p=clip(p,0,right,false);
    p=clip(p,2,near,true); return clip(p,2,far,false);
}
bool emit(Mesh& mesh,const Polygon& polygon) {
    for(std::size_t i=2;i<polygon.size();++i) {
        const auto& a=polygon[0];const auto& b=polygon[i-1];const auto& c=polygon[i];
        const Point u{b[0]-a[0],b[1]-a[1],b[2]-a[2]},v{c[0]-a[0],c[1]-a[1],c[2]-a[2]};
        const Point n{u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]};
        if(n[0]*n[0]+n[1]*n[1]+n[2]*n[2]<=1e-24) continue;
        if(mesh.faces.size()==maximum_faces) return false;
        mesh.faces.push_back({a,b,c});
    }
    return true;
}
void unique(std::vector<double>& values) {
    std::sort(values.begin(),values.end());
    values.erase(std::unique(values.begin(),values.end()),values.end());
}
std::vector<double> cuts(double low,double high,double origin,double pitch,
        excavation::Integer first,excavation::Integer last) {
    std::vector<double> out{low,high};
    const long double minimum=static_cast<long double>(origin)+first*static_cast<long double>(pitch);
    const long double maximum=static_cast<long double>(origin)+last*static_cast<long double>(pitch);
    if(low>=maximum || high<=minimum) return out;
    const long double start=std::max(static_cast<long double>(first),
        std::floor((static_cast<long double>(low)-origin)/pitch));
    const long double finish=std::min(static_cast<long double>(last),
        std::ceil((static_cast<long double>(high)-origin)/pitch));
    for(auto n=static_cast<excavation::Integer>(start);n<=static_cast<excavation::Integer>(finish);++n) {
        const double at=origin+static_cast<double>(n)*pitch;
        if(at>low && at<high) out.push_back(at);
    }
    unique(out); return out;
}
std::size_t cell_index(const std::vector<double>& axis,double at) {
    return std::min(axis.size()-2,static_cast<std::size_t>(
        std::upper_bound(axis.begin(),axis.end(),at)-axis.begin()-1));
}
}
std::optional<Mesh> build(const terrain_surface::Surface& terrain,
        const world::ore_columns::Seed& seed,const world::ore_columns::Field& field,
        const materials::State& material) {
    if(world::ore_columns::validate(seed,field,material)!=world::ore_columns::Error::none ||
        terrain.axis.size()<2 || terrain.axis.size()>1024 ||
        terrain.heights.size()!=terrain.axis.size()*terrain.axis.size()) return std::nullopt;
    for(std::size_t i=0;i<terrain.axis.size();++i)
        if(!std::isfinite(terrain.axis[i]) || (i && terrain.axis[i]<=terrain.axis[i-1])) return std::nullopt;
    for(double h:terrain.heights) if(!std::isfinite(h)) return std::nullopt;
    std::map<excavation::Cell,double> floors;
    excavation::Cell low{},high{};
    bool first=true;
    for(const auto& [cell,column]:field) if(column.remaining_units<column.initial_units) {
        const auto surface=excavation::surface(seed.grid,cell,column);
        if(!surface || surface->min_x<terrain.axis.front() || surface->max_x>terrain.axis.back() ||
            surface->min_z<terrain.axis.front() || surface->max_z>terrain.axis.back()) return std::nullopt;
        floors.emplace(cell,surface->floor);
        if(first) {low=high=cell;first=false;}
        else {low.x=std::min(low.x,cell.x);low.z=std::min(low.z,cell.z);
            high.x=std::max(high.x,cell.x);high.z=std::max(high.z,cell.z);}
    }
    if(!first && (static_cast<long double>(high.x)-low.x>16384 ||
        static_cast<long double>(high.z)-low.z>16384 ||
        high.x==std::numeric_limits<excavation::Integer>::max() ||
        high.z==std::numeric_limits<excavation::Integer>::max())) return std::nullopt;
    Mesh mesh;
    const auto vertex=[&](std::size_t x,std::size_t z) {
        return Point{terrain.axis[x],terrain.heights[z*terrain.axis.size()+x],terrain.axis[z]};
    };
    const auto& g=seed.grid;
    std::size_t rectangles=0;
    for(std::size_t z=0;z+1<terrain.axis.size();++z) for(std::size_t x=0;x+1<terrain.axis.size();++x) {
        const auto a=vertex(x,z),b=vertex(x+1,z),c=vertex(x+1,z+1),d=vertex(x,z+1);
        const auto xs=first ? std::vector<double>{a[0],c[0]}:cuts(a[0],c[0],g.origin[0],g.pitch,low.x,high.x+1);
        const auto zs=first ? std::vector<double>{a[2],c[2]}:cuts(a[2],c[2],g.origin[2],g.pitch,low.z,high.z+1);
        const std::size_t count=(xs.size()-1)*(zs.size()-1);
        if(count>maximum_faces-rectangles) return std::nullopt;
        rectangles+=count;
        for(const auto& triangle:{Triangle{a,b,c},Triangle{a,c,d}})
            for(std::size_t xi=1;xi<xs.size();++xi) for(std::size_t zi=1;zi<zs.size();++zi) {
                auto polygon=rectangle({triangle.begin(),triangle.end()},xs[xi-1],xs[xi],zs[zi-1],zs[zi]);
                if(first) {if(!emit(mesh,polygon)) return std::nullopt;continue;}
                const long double cx=std::floor(((static_cast<long double>(xs[xi-1])+xs[xi])*.5L-g.origin[0])/g.pitch);
                const long double cz=std::floor(((static_cast<long double>(zs[zi-1])+zs[zi])*.5L-g.origin[2])/g.pitch);
                if(cx<low.x || cx>high.x || cz<low.z || cz>high.z) {
                    if(!emit(mesh,polygon)) return std::nullopt;
                    continue;
                }
                const excavation::Cell cell{static_cast<excavation::Integer>(cx),static_cast<excavation::Integer>(cz)};
                const auto floor=floors.find(cell);
                if(floor==floors.end()) {if(!emit(mesh,polygon)) return std::nullopt;continue;}
                if(!emit(mesh,clip(polygon,1,floor->second,false))) return std::nullopt;
                auto cut=clip(polygon,1,floor->second,true);
                for(auto& p:cut) p[1]=floor->second;
                if(!emit(mesh,cut)) return std::nullopt;
            }
    }
    // Emit each wall from its deeper side. Sampling breaks at every native
    // triangle edge and floor-plane crossing, so sloped bank edges stay exact.
    for(const auto& [cell,floor]:floors) for(const auto delta:{excavation::Cell{-1,0},
            excavation::Cell{1,0},excavation::Cell{0,-1},excavation::Cell{0,1}}) {
        if((delta.x<0 && cell.x==std::numeric_limits<excavation::Integer>::min()) ||
            (delta.z<0 && cell.z==std::numeric_limits<excavation::Integer>::min())) return std::nullopt;
        const excavation::Cell next{cell.x+delta.x,cell.z+delta.z};
        const auto adjacent=floors.find(next);
        const double upper=adjacent==floors.end()?std::numeric_limits<double>::infinity():adjacent->second;
        if(floor>=upper) continue;
        const bool vertical=delta.x!=0;
        const double fixed=vertical?g.origin[0]+(cell.x+(delta.x>0?1:0))*g.pitch:
            g.origin[2]+(cell.z+(delta.z>0?1:0))*g.pitch;
        const double start=vertical?g.origin[2]+cell.z*g.pitch:g.origin[0]+cell.x*g.pitch;
        const double end=start+g.pitch;
        std::vector<double> points{start,end};
        const auto fixed_cell=cell_index(terrain.axis,fixed);
        const double fraction=(fixed-terrain.axis[fixed_cell])/
            (terrain.axis[fixed_cell+1]-terrain.axis[fixed_cell]);
        for(std::size_t i=0;i+1<terrain.axis.size();++i) {
            for(double at:{terrain.axis[i],terrain.axis[i]+fraction*(terrain.axis[i+1]-terrain.axis[i])})
                if(at>start && at<end) points.push_back(at);
        }
        unique(points);
        const auto natural=[&](double at) {
            const auto height=terrain.natural_range(vertical?fixed:at,vertical?at:fixed,0,0);
            return height ? height->second:std::numeric_limits<double>::quiet_NaN();
        };
        std::vector<double> full=points;
        for(std::size_t i=1;i<points.size();++i) {
            const double h0=natural(points[i-1]),h1=natural(points[i]);
            if(!std::isfinite(h0) || !std::isfinite(h1)) return std::nullopt;
            if(h0==h1) continue;
            for(double threshold:{floor,upper}) {
                const double t=(threshold-h0)/(h1-h0);
                if(t>0 && t<1) full.push_back(points[i-1]+t*(points[i]-points[i-1]));
            }
        }
        unique(full);
        const auto point=[&](double at,double y) {return vertical?Point{fixed,y,at}:Point{at,y,fixed};};
        for(std::size_t i=1;i<full.size();++i) {
            const double h0=natural(full[i-1]),h1=natural(full[i]);
            Polygon wall{point(full[i-1],std::min(h0,floor)),point(full[i],std::min(h1,floor)),
                point(full[i],std::min(h1,upper)),point(full[i-1],std::min(h0,upper))};
            if(delta.x>0 || delta.z<0) std::reverse(wall.begin(),wall.end());
            if(!emit(mesh,wall)) return std::nullopt;
        }
    }
    // Standard Godot Vector3/collision vertices are float32. Native queries
    // consume those same emitted coordinates, not a higher-precision surface
    // that the actor physics cannot represent. Quantity/depth math stays in
    // the World; this is solely its geometry projection.
    for (auto& face : mesh.faces) for (auto& point : face) for (double& value : point) {
        value = static_cast<double>(static_cast<float>(value));
        if (!std::isfinite(value)) return std::nullopt;
    }
    std::erase_if(mesh.faces,[](const Triangle& face) {
        const Point a{face[1][0]-face[0][0],face[1][1]-face[0][1],face[1][2]-face[0][2]};
        const Point b{face[2][0]-face[0][0],face[2][1]-face[0][1],face[2][2]-face[0][2]};
        return a[1]*b[2]-a[2]*b[1]==0 && a[2]*b[0]-a[0]*b[2]==0 && a[0]*b[1]-a[1]*b[0]==0;
    });
    mesh.index(terrain.axis);
    return mesh;
}
std::optional<std::pair<double,double>> range(const Mesh& mesh,double x,double z,double half_x,double half_z) {
    return mesh.range(x,z,half_x,half_z);
}
}
