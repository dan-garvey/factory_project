#include "factory/excavation.hpp"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string_view>

namespace e = factory::excavation;
namespace {
int checks{};
void check(bool value, const char* why) {
    ++checks;
    if (!value) throw std::runtime_error(why);
}
bool near(double a, double b) { return std::abs(a - b) < 1e-10; }

e::Grid grid() { return {{-3.5, 2.0, 7.25}, 0.825, 0.20625, 4, 4096}; }
e::Contact top(const e::Grid& geometry, const e::Columns& columns, e::Cell cell) {
    const auto bounds = *e::surface(geometry, cell, columns.at(cell));
    return {cell, e::Face::top,
        {(bounds.min_x + bounds.max_x) * 0.5, bounds.floor,
         (bounds.min_z + bounds.max_z) * 0.5},
        {geometry.pitch * 0.5, geometry.pitch * 0.5}};
}
e::Contact side(const e::Grid& geometry, const e::Columns& columns,
                e::Cell cell, e::Face face) {
    const auto bounds = *e::surface(geometry, cell, columns.at(cell));
    const auto depth = geometry.height_step / geometry.units_per_step;
    e::Point point{(bounds.min_x + bounds.max_x) * 0.5,
        bounds.floor - depth * 0.5, (bounds.min_z + bounds.max_z) * 0.5};
    switch (face) {
        case e::Face::west: point[0] = bounds.min_x; break;
        case e::Face::east: point[0] = bounds.max_x; break;
        case e::Face::north: point[2] = bounds.min_z; break;
        case e::Face::south: point[2] = bounds.max_z; break;
        case e::Face::top: throw std::runtime_error("side helper requires a side");
    }
    return {cell, face, point, {geometry.pitch * 0.5, depth * 0.5}};
}
void settle(e::Columns& columns, const e::CutProposal& proposal) {
    check(proposal.changes_column() && columns.at(proposal.cell) == proposal.before,
        "Settlement uses the exact column on which the proposal was based.");
    columns.at(proposal.cell) = proposal.after;
}

void local_depth() {
    const auto geometry = grid();
    e::Columns columns;
    for (e::Integer z = 0; z < 10; ++z)
        for (e::Integer x = 0; x < 10; ++x) {
            const auto units = x + z * 10 < 96 ? 41 : 40;
            columns[{x,z}] = {units,units,0,0};
        }
    check(e::valid(geometry, columns) && e::remaining(columns) == 4096,
        "Locally addressed columns preserve the finite reserve.");
    const auto untouched = columns.at({1,0});
    const auto original = columns;
    const auto contact = top(geometry, columns, {0,0});
    const auto before_surface = *e::surface(geometry, {0,0}, columns.at({0,0}));
    const auto proposal = e::cut(geometry, columns, contact, 4096, 1);
    check(columns == original, "Proposing a cut cannot mutate its supplied authority state.");
    check(proposal.status == e::Status::produced && proposal.produced_units == 1 &&
        proposal.work_spent == 4096, "One full supported bite creates one raw unit.");
    settle(columns, proposal);
    const auto after_surface = *e::surface(geometry, {0,0}, columns.at({0,0}));
    check(near(before_surface.floor - after_surface.floor,
               geometry.height_step / geometry.units_per_step),
        "The exposed floor follows actual removed quantity using caller-bound height units.");
    check(columns.at({1,0}) == untouched && e::remaining(columns) == 4095,
        "An addressed cut cannot drain its neighbouring cell or region.");
    check(e::cut(geometry, columns, contact, 4096, 1).status == e::Status::no_contact,
        "The old shallow contact cannot withdraw newly exposed deeper stock.");
    auto buried = top(geometry, columns, {0,0});
    buried.center[1] -= 3 * geometry.height_step;
    check(e::cut(geometry, columns, buried, 4096, 1).status == e::Status::no_contact,
        "A tool below retained ore cannot tunnel through it.");
    auto small = top(geometry, columns, {0,0});
    small.half_span[0] *= 0.49;
    check(e::cut(geometry, columns, small, 4096, 1).status == e::Status::face_too_small,
        "A small working face cannot drain a larger column footprint.");
    e::Integer produced = 1;
    while (columns.at({0,0}).remaining_units > 0) {
        const auto next = e::cut(geometry, columns, top(geometry,columns,{0,0}), 999999, 999);
        check(next.produced_units == 1 && next.work_spent == 4096,
            "Surplus rate or capacity cannot skip deeper contact in one bite.");
        settle(columns,next);
        produced += next.produced_units;
        check(*e::remaining(columns) + produced == 4096,
            "Every produced raw unit corresponds to one finite stock debit.");
    }
    const auto exhausted_surface = *e::surface(geometry, {0,0}, columns.at({0,0}));
    check(near(exhausted_surface.floor, exhausted_surface.base),
        "Exhaustion reaches the declared source base without erasing the floor.");
    check(e::cut(geometry,columns,top(geometry,columns,{0,0}),4096,1).status == e::Status::exhausted,
        "An exhausted column stays exhausted with more power or output capacity.");
}

void partial_work_and_backpressure() {
    auto geometry = grid();
    e::Columns columns{{{0,0},{4,4,2,0}}};
    const auto contact = top(geometry,columns,{0,0});
    const auto floor = e::surface(geometry,{0,0},columns.at({0,0}))->floor;
    auto first = e::cut(geometry,columns,contact,700,1);
    check(first.status == e::Status::working && first.produced_units == 0 &&
        first.after.remaining_units == 4 && first.after.work == 700,
        "Fractional work accumulates without inventing a chip or lowering collision.");
    settle(columns,first);
    check(e::surface(geometry,{0,0},columns.at({0,0}))->floor == floor,
        "Partial work has not excavated the material yet.");
    const auto blocked = e::cut(geometry,columns,contact,9000,0);
    check(blocked.status == e::Status::receiver_full && !blocked.changes_column() &&
        blocked.after == blocked.before && blocked.work_spent == 0 && blocked.produced_units == 0,
        "Full output preserves both pending work and uncut ore.");
    const auto powerless = e::cut(geometry,columns,contact,0,1);
    check(powerless.status == e::Status::no_work && powerless.after == first.after,
        "Stopped cutting retains work for safe restart.");
    const auto finish = e::cut(geometry,columns,contact,std::numeric_limits<e::Integer>::max(),1);
    check(finish.status == e::Status::produced && finish.work_spent == 3396 &&
        finish.after.work == 0 && finish.produced_units == 1,
        "Finishing spends only missing work; arbitrary excess cannot bank extraction.");
    settle(columns,finish);
    const auto after = columns;
    check(e::cut(geometry,columns,contact,4096,1).status == e::Status::no_contact && columns == after,
        "A second cutter replanned after settlement cannot reuse stale surface contact.");
    e::Columns hand{{{0,0},{4,4,2,0}}};
    auto hand_result = e::cut(geometry,hand,top(geometry,hand,{0,0}),4096,1);
    check(hand_result.after == columns.at({0,0}),
        "Timed hand work and fractional powered work share identical debit semantics.");
}

void exposed_terraces() {
    const auto geometry = grid();
    const e::Column untouched{8,8,0,0};
    e::Columns columns{{{0,0},untouched},{{-1,0},{8,0,0,0}},
        {{1,0},{8,0,0,0}},{{0,-1},{8,0,0,0}},{{0,1},{8,0,0,0}}};
    for (const auto face : {e::Face::west,e::Face::east,e::Face::north,e::Face::south}) {
        const auto contact = side(geometry,columns,{0,0},face);
        const auto proposal = e::cut(geometry,columns,contact,4096,1);
        check(proposal.status == e::Status::produced && proposal.after.remaining_units == 7,
            "Each exposed cardinal side can remove the same top bite.");
        auto deep = contact;
        deep.center[1] -= geometry.height_step;
        check(e::cut(geometry,columns,deep,4096,1).status == e::Status::face_too_small,
            "An exposed lower side cannot excavate underneath the column top.");
    }
    const auto contact = side(geometry,columns,{0,0},e::Face::west);
    columns.at({-1,0}) = untouched;
    check(e::cut(geometry,columns,contact,4096,1).status == e::Status::face_not_exposed,
        "Intact neighbouring rock blocks lateral access.");
    columns.erase({-1,0});
    check(e::cut(geometry,columns,contact,4096,1).status == e::Status::face_not_exposed,
        "Missing terrain data is not treated as a free-air mining face.");
    columns[{-1,0}] = {0,0,-1,0};
    check(e::cut(geometry,columns,contact,4096,1).status == e::Status::produced,
        "A trusted lower zero-stock boundary floor exposes the deposit edge.");
    columns[{-1,0}] = {0,0,0,0};
    check(e::cut(geometry,columns,contact,4096,1).status == e::Status::face_not_exposed,
        "Unmineable surrounding ground still blocks access at equal elevation.");
    const auto before = columns;
    check(e::cut(geometry,columns,top(geometry,columns,{0,0}),4096,0).produced_units == 0 &&
        columns == before, "Infrastructure/output blockage cannot delete underlying stock.");
}

void shared_surface_geometry() {
    const auto geometry = grid();
    e::Columns natural{{{0,0},{4,4,0.12345,0}}};
    check(near(e::surface(geometry,{0,0},natural.at({0,0}))->floor,2.12345),
        "Bound natural terrain retains its measured starting height without H-grid rounding.");
    e::Columns columns{{{0,0},{4,4,0,0}},{{1,0},{4,4,0,0}}};
    auto initial = e::exposed_faces(geometry,columns,{0,0});
    check(initial && initial->size() == 1 && initial->front().face == e::Face::top,
        "Equal-height columns share no internal exposed wall.");
    settle(columns,e::cut(geometry,columns,top(geometry,columns,{0,0}),4096,1));
    const auto lower = e::surface(geometry,{0,0},columns.at({0,0}))->floor;
    const auto higher = e::surface(geometry,{1,0},columns.at({1,0}))->floor;
    auto faces = e::exposed_faces(geometry,columns,{1,0});
    check(faces && faces->size() == 2 && (*faces)[1].face == e::Face::west,
        "Excavation exposes the neighbouring wall and the new floor together.");
    const auto wall = (*faces)[1];
    check(near(wall.center[1]-wall.half_span[1],lower) &&
        near(wall.center[1]+wall.half_span[1],higher),
        "The wall spans precisely the two authoritative floors.");
    check(e::exposed_faces(geometry,columns,{0,0})->size() == 1,
        "The lower cell does not emit an inverted internal wall.");
    check(!e::exposed_faces(geometry,columns,{9,9}),
        "No surface is fabricated for an unknown column.");
}

void invalid_inputs() {
    const auto geometry = grid();
    e::Columns columns{{{0,0},{4,4,0,0}}};
    const auto contact = top(geometry,columns,{0,0});
    for (double bad : {std::numeric_limits<double>::quiet_NaN(),
                      std::numeric_limits<double>::infinity(),
                      -std::numeric_limits<double>::infinity()}) {
        auto broken = geometry;
        broken.pitch = bad;
        check(!e::valid(broken,columns), "Nonfinite pitch is rejected.");
        broken = geometry; broken.height_step = bad;
        check(!e::valid(broken,columns), "Nonfinite depth scale is rejected.");
        auto bad_surface=columns; bad_surface.at({0,0}).initial_height=bad;
        check(!e::valid(geometry,bad_surface), "Nonfinite initial terrain height is rejected.");
        for (unsigned axis=0;axis<3;++axis) {
            broken=geometry; broken.origin[axis]=bad;
            check(!e::valid(broken,columns), "Nonfinite bound origin is rejected.");
            auto malformed=contact; malformed.center[axis]=bad;
            check(e::cut(geometry,columns,malformed,1,1).status == e::Status::invalid_request,
                "Nonfinite working-face contact is rejected.");
        }
        for (unsigned axis=0;axis<2;++axis) {
            auto malformed=contact; malformed.half_span[axis]=bad;
            check(e::cut(geometry,columns,malformed,1,1).status == e::Status::invalid_request,
                "Nonfinite working-face extent is rejected.");
        }
    }
    for (double bad : {0.0,-1.0}) {
        auto broken=geometry; broken.pitch=bad;
        check(!e::valid(broken,columns), "Nonpositive cell width is rejected.");
        broken=geometry; broken.height_step=bad;
        check(!e::valid(broken,columns), "Nonpositive height step is rejected.");
    }
    for (e::Integer bad : {e::Integer{0},e::Integer{-1}}) {
        auto broken=geometry; broken.units_per_step=bad;
        check(!e::valid(broken,columns), "Invalid unit density is rejected.");
        broken=geometry; broken.work_per_unit=bad;
        check(!e::valid(broken,columns), "Invalid cutting-work cost is rejected.");
    }
    for (auto malformed : {e::Column{-1,0,0,0},e::Column{4,-1,0,0},e::Column{4,5,0,0},
                           e::Column{4,4,0,-1},e::Column{4,4,0,4096},e::Column{4,0,0,1}}) {
        e::Columns bad{{{0,0},malformed}};
        check(!e::valid(geometry,bad) &&
            e::cut(geometry,bad,contact,1,1).status==e::Status::invalid_state,
            "Impossible restored quantities/work are rejected without producing a proposal.");
    }
    check(e::cut(geometry,columns,contact,-1,1).status==e::Status::invalid_request &&
        e::cut(geometry,columns,contact,1,-1).status==e::Status::invalid_request,
        "Negative work and receiving capacity do not invert extraction.");
    auto outside=contact; outside.cell={9,9};
    check(e::cut(geometry,columns,outside,1,1).status==e::Status::outside_deposit,
        "An unknown address cannot borrow any local source.");
    auto invalid_face=contact; invalid_face.face=static_cast<e::Face>(100);
    check(e::cut(geometry,columns,invalid_face,1,1).status==e::Status::invalid_request,
        "Unknown face identifiers fail closed.");
    const auto max=std::numeric_limits<e::Integer>::max();
    e::Columns overflow{{{0,0},{max,max,0,0}},{{1,0},{1,1,0,0}}};
    check(!e::remaining(overflow), "Aggregate stock overflow is rejected.");
    auto huge=geometry; huge.origin[0]=std::numeric_limits<double>::max();
    check(!e::valid(huge,columns), "Unrepresentable adjacent coordinates are refused.");
    auto tiny=geometry; tiny.units_per_step=max;
    check(!e::valid(tiny,columns), "A bite below numerical surface resolution is refused.");
    e::Columns too_many;
    for (std::size_t i=0;i<=e::maximum_columns;++i)
        too_many[{static_cast<e::Integer>(i),0}]={0,0,0,0};
    check(!e::valid(geometry,too_many), "Malformed unbounded column collections are refused.");
    auto huge_contact=contact;
    huge_contact.center[0]=std::numeric_limits<double>::max();
    huge_contact.half_span[0]=std::numeric_limits<double>::max();
    check(e::cut(geometry,columns,huge_contact,1,1).status==e::Status::invalid_request,
        "Overflowing face extents cannot cover the entire field.");
    check(std::string_view(e::status_name(e::Status::no_contact))=="no_ore_contact" &&
        std::string_view(e::status_name(static_cast<e::Status>(100)))=="invalid_cut_status",
        "Failures remain distinguishable and unknown statuses are safe.");
}
} // namespace

int main() {
    try {
        local_depth(); partial_work_and_backpressure(); exposed_terraces();
        shared_surface_geometry(); invalid_inputs();
        std::cout << checks << " local excavation checks passed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
