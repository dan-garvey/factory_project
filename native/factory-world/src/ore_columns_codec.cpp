#include "factory/ore_columns_codec.hpp"

namespace factory::world::ore_columns {
namespace {
using V=values::Value;
using Object=V::Object;
using Array=V::Array;
using Integer=V::Integer;
template<class T> const T* field(const Object& o,const char* key) {
    const auto it=o.find(key);
    return it==o.end() ? nullptr : std::get_if<T>(&it->second.storage());
}
}
std::optional<V> encode_seed(const Seed& seed) {
    const auto total=excavation::remaining(seed.columns);
    if (!total) return std::nullopt;
    materials::State pristine; pristine.initial_units=*total; pristine.stock.source=*total;
    if (validate(seed,seed.columns,pristine)!=Error::none) return std::nullopt;
    Array columns;
    for (const auto& [cell,column]:seed.columns) {
        if (column.remaining_units!=column.initial_units || column.work!=0) return std::nullopt;
        columns.emplace_back(Object{{"x",V(cell.x)},{"z",V(cell.z)},
            {"initial",V(column.initial_units)},{"height",V(column.initial_height)}});
    }
    const auto& g=seed.grid;
    Array contacts;
    for (const auto& [cell,point]:seed.contact_points)
        contacts.emplace_back(Object{{"x",V(cell.x)},{"z",V(cell.z)},
            {"point",V(Array{V(point[0]),V(point[1]),V(point[2])})}});
    return V(Object{{"origin",V(Array{V(g.origin[0]),V(g.origin[1]),V(g.origin[2])})},
        {"pitch",V(g.pitch)},{"height_step",V(g.height_step)},
        {"units_per_step",V(g.units_per_step)},{"work_per_unit",V(g.work_per_unit)},
        {"columns",V(std::move(columns))},{"contact_points",V(std::move(contacts))}});
}
std::optional<V> encode_field(const Seed& seed,const Field& columns,const materials::State& material) {
    if (validate(seed,columns,material)!=Error::none) return std::nullopt;
    Array encoded;
    for (const auto& [cell,column]:columns)
        encoded.emplace_back(Object{{"x",V(cell.x)},{"z",V(cell.z)},
            {"remaining",V(column.remaining_units)},{"work",V(column.work)}});
    return V(std::move(encoded));
}
std::optional<Field> decode_field(const Seed& seed,const V& value,const materials::State& material) {
    const auto* columns=std::get_if<Array>(&value.storage());
    if (!columns || columns->size()!=seed.columns.size() || columns->size()>excavation::maximum_columns)
        return std::nullopt;
    Field result;
    for (const auto& value:*columns) {
        const auto* entry=std::get_if<Object>(&value.storage());
        if (!entry || entry->size()!=4) return std::nullopt;
        const auto* x=field<Integer>(*entry,"x");
        const auto* z=field<Integer>(*entry,"z");
        const auto* remaining=field<Integer>(*entry,"remaining");
        const auto* work=field<Integer>(*entry,"work");
        if (!x || !z || !remaining || !work) return std::nullopt;
        const excavation::Cell cell{*x,*z};
        const auto initial=seed.columns.find(cell);
        if (initial==seed.columns.end()) return std::nullopt;
        auto column=initial->second;
        column.remaining_units=*remaining;
        column.work=*work;
        if (!result.emplace(cell,column).second) return std::nullopt;
    }
    return validate(seed,result,material)==Error::none ? std::optional<Field>{std::move(result)} : std::nullopt;
}
}
