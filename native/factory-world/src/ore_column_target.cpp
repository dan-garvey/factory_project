#include "factory/ore_column_target.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <limits>
#include <set>

namespace factory::world::ore_columns {
namespace {
using Cell = excavation::Cell;
using Face = excavation::Face;
using Point = authority::Point;
using Integer = materials::Quantity;
using Value = values::Value;
using Object = authority::Object;
constexpr std::string_view prefix="ore-column:";

template<class T> const T* field(const Object& object,const char* name) {
    const auto at=object.find(name);
    return at==object.end()?nullptr:std::get_if<T>(&at->second.storage());
}
std::optional<Integer> integer(std::string_view text) noexcept {
    if(text.empty()||text.front()=='+') return std::nullopt;
    const auto digits=text.front()=='-'?text.substr(1):text;
    if(digits.empty()||(digits.size()>1&&digits.front()=='0')||text=="-0") return std::nullopt;
    Integer value{};
    const auto parsed=std::from_chars(text.data(),text.data()+text.size(),value);
    if(parsed.ec!=std::errc{}||parsed.ptr!=text.data()+text.size()) return std::nullopt;
    return value;
}
bool finite(const Point& point) {
    return std::all_of(point.begin(),point.end(),[](double n){return std::isfinite(n);});
}
bool valid_seed(const Seed& seed) {
    const auto total=excavation::remaining(seed.columns);
    if(!total) return false;
    materials::State pristine;
    pristine.initial_units=*total; pristine.stock.source=*total;
    return validate(seed,seed.columns,pristine)==Error::none;
}
std::optional<Cell> neighbour(Cell cell,Face face) {
    switch(face) {
        case Face::west: if(cell.x==std::numeric_limits<Integer>::min()) return {}; --cell.x; break;
        case Face::east: if(cell.x==std::numeric_limits<Integer>::max()) return {}; ++cell.x; break;
        case Face::north: if(cell.z==std::numeric_limits<Integer>::min()) return {}; --cell.z; break;
        case Face::south: if(cell.z==std::numeric_limits<Integer>::max()) return {}; ++cell.z; break;
        case Face::top: return {};
    }
    return cell;
}
bool x_side(Face face) {return face==Face::west||face==Face::east;}
double midpoint(double a,double b) {
    return static_cast<double>((static_cast<long double>(a)+b)*.5L);
}
double tolerance(const excavation::Grid& grid,const excavation::Surface& surface) {
    const auto scale=std::max({1.0,std::abs(surface.min_x),std::abs(surface.max_x),
        std::abs(surface.min_z),std::abs(surface.max_z),std::abs(surface.floor)});
    return std::max(std::min(grid.pitch,grid.height_step/grid.units_per_step)*1e-9,
        scale*64*std::numeric_limits<double>::epsilon());
}
std::optional<excavation::Contact> cutting_contact(const Seed& seed,Cell cell,
        const excavation::Column& column,Face face) {
    const auto bounds=excavation::surface(seed.grid,cell,column);
    if(!bounds||column.remaining_units<=0) return {};
    auto after=column; --after.remaining_units; after.work=0;
    const auto next=excavation::surface(seed.grid,cell,after);
    if(!next) return {};
    excavation::Contact result{cell,face,
        {midpoint(bounds->min_x,bounds->max_x),bounds->floor,midpoint(bounds->min_z,bounds->max_z)},
        {seed.grid.pitch*.5,seed.grid.pitch*.5}};
    if(face==Face::top) return result;
    result.center[1]=midpoint(bounds->floor,next->floor);
    result.half_span[1]=(bounds->floor-next->floor)*.5;
    switch(face) {
        case Face::west: result.center[0]=bounds->min_x; break;
        case Face::east: result.center[0]=bounds->max_x; break;
        case Face::north: result.center[2]=bounds->min_z; break;
        case Face::south: result.center[2]=bounds->max_z; break;
        default: return {};
    }
    return result;
}
bool facing_actor(const excavation::Contact& contact,const Point& actor,double epsilon) {
    switch(contact.face) {
        case Face::top: return actor[1]>=contact.center[1]-epsilon;
        case Face::west: return actor[0]<=contact.center[0]+epsilon;
        case Face::east: return actor[0]>=contact.center[0]-epsilon;
        case Face::north: return actor[2]<=contact.center[2]+epsilon;
        case Face::south: return actor[2]>=contact.center[2]-epsilon;
    }
    return false;
}
Point nearest_point(const Seed& seed,const excavation::Contact& contact,const Point& actor) {
    const auto supplied=seed.contact_points.find(contact.cell);
    if(contact.face==Face::top && supplied!=seed.contact_points.end()) {
        auto point=supplied->second;
        point[1]=std::min(point[1],contact.center[1]);
        return point;
    }
    auto result=contact.center;
    const auto first=contact.face==Face::top?0:(x_side(contact.face)?2:0);
    const auto second=contact.face==Face::top?2:1;
    result[first]=std::clamp(actor[first],contact.center[first]-contact.half_span[0],
        contact.center[first]+contact.half_span[0]);
    result[second]=std::clamp(actor[second],contact.center[second]-contact.half_span[1],
        contact.center[second]+contact.half_span[1]);
    return result;
}
// Open horizontal interiors avoid treating a ray ending on a wall as passing
// through the wall, while any segment inside retained ground still refuses.
std::optional<std::array<long double,2>> segment_interval(const Point& from,
        const Point& to,const excavation::Surface& bounds,double epsilon) {
    long double begin=0,end=1;
    for(unsigned axis:{0U,2U}) {
        const long double low=(axis==0?bounds.min_x:bounds.min_z)+epsilon;
        const long double high=(axis==0?bounds.max_x:bounds.max_z)-epsilon;
        const long double start=from[axis],delta=static_cast<long double>(to[axis])-start;
        if(delta==0) {if(start<=low||start>=high) return {}; continue;}
        const auto a=(low-start)/delta,b=(high-start)/delta;
        begin=std::max(begin,std::min(a,b)); end=std::min(end,std::max(a,b));
        if(begin>=end) return {};
    }
    return std::array<long double,2>{begin,end};
}
bool near_segment(const Seed& seed,Cell cell,const Point& actor,const Point& reach) {
    // Conservative horizontal rejection before constructing exact surfaces.
    // One whole cell of padding preserves boundary and rounding cases.
    const auto& g=seed.grid;
    for(unsigned axis:{0U,2U}) {
        const long double index=axis==0?cell.x:cell.z;
        const long double first=(std::min(actor[axis],reach[axis])-g.origin[axis])/g.pitch;
        const long double last=(std::max(actor[axis],reach[axis])-g.origin[axis])/g.pitch;
        if(index+2<first || index-1>last) return false;
    }
    return true;
}
std::optional<std::set<Cell>> required_cells(const Seed& seed,const Point& actor,
        const Point& reach,Cell target,Face face) {
    std::set<Cell> result{target};
    if(face!=Face::top) {
        const auto adjacent=neighbour(target,face);
        if(!adjacent||!seed.columns.contains(*adjacent)) return {};
        result.insert(*adjacent);
    }
    for(const auto& [cell,column]:seed.columns) {
        if(!near_segment(seed,cell,actor,reach)) continue;
        const auto bounds=excavation::surface(seed.grid,cell,column);
        if(!bounds) return {};
        if(segment_interval(actor,reach,*bounds,tolerance(seed.grid,*bounds))) result.insert(cell);
        if(result.size()>maximum_contact_columns) return {};
    }
    return result;
}
bool clear_segment(const Seed& seed,const Field& field,const Point& actor,const Point& reach) {
    for(const auto& [cell,column]:field) {
        if(!near_segment(seed,cell,actor,reach)) continue;
        const auto bounds=excavation::surface(seed.grid,cell,column);
        if(!bounds) return false;
        const auto epsilon=tolerance(seed.grid,*bounds);
        const auto interval=segment_interval(actor,reach,*bounds,epsilon);
        if(!interval) continue;
        const auto dy=static_cast<long double>(reach[1])-actor[1];
        const auto y0=actor[1]+dy*(*interval)[0],y1=actor[1]+dy*(*interval)[1];
        if(std::min(y0,y1)<bounds->floor-epsilon) return false;
    }
    return true;
}
Value point_value(const Point& point) {
    return Value(Value::Array{Value(point[0]),Value(point[1]),Value(point[2])});
}
Value cell_value(Cell cell) {return Value(Value::Array{Value(cell.x),Value(cell.z)});}
std::optional<Point> point_field(const Object& object,const char* key) {
    const auto* array=field<Value::Array>(object,key);
    if(!array||array->size()!=3) return {};
    Point result{};
    for(std::size_t axis=0;axis<3;++axis) {
        const auto* n=std::get_if<double>(&(*array)[axis].storage());
        if(!n||!std::isfinite(*n)) return {};
        result[axis]=*n;
    }
    return result;
}
std::optional<Cell> cell_field(const Object& object,const char* key) {
    const auto* array=field<Value::Array>(object,key);
    if(!array||array->size()!=2) return {};
    const auto* x=std::get_if<Integer>(&(*array)[0].storage());
    const auto* z=std::get_if<Integer>(&(*array)[1].storage());
    if(!x||!z) return {};
    return Cell{*x,*z};
}
} // namespace

std::string target_id(Cell cell) {
    return std::string(prefix)+std::to_string(cell.x)+":"+std::to_string(cell.z);
}
std::optional<Cell> target_cell(std::string_view target) noexcept {
    if(!target.starts_with(prefix)||target.size()>prefix.size()+41) return {};
    target.remove_prefix(prefix.size());
    const auto separator=target.find(':');
    if(separator==std::string_view::npos) return {};
    const auto x=integer(target.substr(0,separator)),z=integer(target.substr(separator+1));
    if(!x||!z) return {};
    return Cell{*x,*z};
}

namespace {
TargetResult resolve_validated(const Seed& seed,const Field& field,
        std::string_view id,const Point& actor) {
    if(!finite(actor)) return {TargetError::invalid_actor,{}};
    const auto cell=target_cell(id);
    if(!cell||!field.contains(*cell)||field.at(*cell).initial_units<=0)
        return {TargetError::unknown_target,{}};
    const auto& before=field.at(*cell);
    if(before.remaining_units==0) return {TargetError::exhausted,{}};
    const auto bounds=*excavation::surface(seed.grid,*cell,before);
    std::optional<Target> best;
    long double best_distance=std::numeric_limits<long double>::infinity();
    bool complex=false;
    // Cut admission only reads its target and the selected exposure neighbour.
    // The complete immutable field was validated before entering this helper.
    Field local{{*cell,before}};
    for(const auto face:{Face::west,Face::east,Face::north,Face::south})
        if(const auto next=neighbour(*cell,face);next && field.contains(*next))
            local.emplace(*next,field.at(*next));
    for(const auto face:{Face::top,Face::west,Face::east,Face::north,Face::south}) {
        const auto cutting=cutting_contact(seed,*cell,before,face);
        if(!cutting||!facing_actor(*cutting,actor,tolerance(seed.grid,bounds))||
            excavation::cut(seed.grid,local,*cutting,0,1).status!=excavation::Status::no_work) continue;
        const auto reach=nearest_point(seed,*cutting,actor);
        if(!clear_segment(seed,field,actor,reach)) continue;
        const auto required=required_cells(seed,actor,reach,*cell,face);
        if(!required) {complex=true; continue;}
        long double distance=0;
        for(unsigned axis=0;axis<3;++axis) {
            const auto delta=static_cast<long double>(actor[axis])-reach[axis]; distance+=delta*delta;
        }
        if(distance>=best_distance) continue;
        best_distance=distance;
        best=Target{*cutting,before,bounds.floor,reach,{}};
        for(const auto needed:*required) best->columns.push_back({needed,field.at(needed).remaining_units});
    }
    if(!best) return {complex?TargetError::contact_too_complex:TargetError::occluded,{}};
    return {TargetError::none,std::move(best)};
}
} // namespace

TargetResult resolve_target(const Seed& seed,const Field& field,const materials::State& material,
        std::string_view id,const Point& actor) {
    if(validate(seed,field,material)!=Error::none) return {TargetError::invalid_state,{}};
    return resolve_validated(seed,field,id,actor);
}

std::vector<TargetResult> resolve_targets(const Seed& seed,const Field& field,
        const materials::State& material,const std::vector<std::string>& ids,const Point& actor) {
    if(validate(seed,field,material)!=Error::none)
        return std::vector<TargetResult>(ids.size(),{TargetError::invalid_state,{}});
    std::vector<TargetResult> results;
    results.reserve(ids.size());
    for(const auto& id:ids) results.push_back(resolve_validated(seed,field,id,actor));
    return results;
}

Object contact_facts(const Target& target) {
    Value::Array columns;
    for(const auto& witness:target.columns) columns.emplace_back(Object{
        {"cell",cell_value(witness.cell)},{"remaining",Value(witness.remaining)}});
    return {{"ore_cell",cell_value(target.cutting.cell)},
        {"ore_remaining_before",Value(target.before.remaining_units)},
        {"ore_work_before",Value(target.before.work)},
        {"ore_floor_before",Value(target.floor_before)},
        {"ore_face",Value(static_cast<Integer>(target.cutting.face))},
        {"ore_cut_center",point_value(target.cutting.center)},
        {"ore_contact_point",point_value(target.reach_point)},
        {"ore_contact_columns",Value(std::move(columns))}};
}

std::optional<Target> historical_contact(const Seed& seed,std::string_view id,
        const Point& actor,const Object& facts) {
    if(!valid_seed(seed)||!finite(actor)) return {};
    const auto cell=target_cell(id),recorded_cell=cell_field(facts,"ore_cell");
    if(!cell||!recorded_cell||*cell!=*recorded_cell||!seed.columns.contains(*cell)) return {};
    const auto* remaining=field<Integer>(facts,"ore_remaining_before");
    const auto* work=field<Integer>(facts,"ore_work_before");
    const auto* floor=field<double>(facts,"ore_floor_before");
    const auto* face=field<Integer>(facts,"ore_face");
    const auto* witnesses=field<Value::Array>(facts,"ore_contact_columns");
    const auto center=point_field(facts,"ore_cut_center"),reach=point_field(facts,"ore_contact_point");
    if(!remaining||!work||!floor||!face||*face<0||*face>4||!center||!reach||
        !witnesses||witnesses->size()>maximum_contact_columns) return {};
    auto before=seed.columns.at(*cell); before.remaining_units=*remaining; before.work=*work;
    const auto bounds=excavation::surface(seed.grid,*cell,before);
    const auto cutting=cutting_contact(seed,*cell,before,static_cast<Face>(*face));
    if(!bounds||!cutting||*floor!=bounds->floor||*center!=cutting->center||
        !facing_actor(*cutting,actor,tolerance(seed.grid,*bounds))||*reach!=nearest_point(seed,*cutting,actor)) return {};
    const auto required=required_cells(seed,actor,*reach,*cell,cutting->face);
    if(!required||required->size()!=witnesses->size()) return {};
    Target result{*cutting,before,*floor,*reach,{}};
    Field observed;
    auto expected=required->begin();
    for(const auto& encoded:*witnesses) {
        const auto* object=std::get_if<Object>(&encoded.storage());
        if(!object||object->size()!=2) return {};
        const auto witness=cell_field(*object,"cell");
        const auto* count=field<Integer>(*object,"remaining");
        if(!witness||!count||*witness!=*expected) return {};
        auto column=seed.columns.at(*witness); column.remaining_units=*count;
        if(*witness==*cell) {if(*count!=before.remaining_units) return {}; column.work=before.work;}
        if(!excavation::surface(seed.grid,*witness,column)) return {};
        observed.emplace(*witness,column); result.columns.push_back({*witness,*count}); ++expected;
    }
    if(excavation::cut(seed.grid,observed,*cutting,0,1).status!=excavation::Status::no_work||
        !clear_segment(seed,observed,actor,*reach)) return {};
    return result;
}

const char* target_error_name(TargetError error) noexcept {
    switch(error) {
        case TargetError::none: return "none";
        case TargetError::invalid_state: return "invalid_ore_columns";
        case TargetError::unknown_target: return "unknown_target";
        case TargetError::exhausted: return "unavailable_source";
        case TargetError::invalid_actor: return "invalid_actor_sample";
        case TargetError::occluded: return "ore_contact_blocked";
        case TargetError::contact_too_complex: return "ore_contact_too_complex";
    }
    return "invalid_ore_target_error";
}
} // namespace factory::world::ore_columns
