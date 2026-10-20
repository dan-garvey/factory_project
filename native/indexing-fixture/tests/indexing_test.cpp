#include "factory/index_workbench.hpp"

#include <initializer_list>
#include <iostream>
#include <limits>
#include <sstream>
#include <vector>

namespace i = factory::indexing;
namespace {
using F = i::Face;
int checks{};
int failures{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

void literal_rotations() {
    const std::array<i::Orientation, 3> positive{{
        {{{F::positive_x, F::positive_z, F::negative_y}}},
        {{{F::negative_z, F::positive_y, F::positive_x}}},
        {{{F::positive_y, F::negative_x, F::positive_z}}},
    }};
    const std::array<i::Orientation, 3> negative{{
        {{{F::positive_x, F::negative_z, F::positive_y}}},
        {{{F::positive_z, F::positive_y, F::negative_x}}},
        {{{F::negative_y, F::positive_x, F::positive_z}}},
    }};
    for (unsigned axis = 0; axis < 3; ++axis) {
        i::Orientation result;
        check(i::rotate({}, static_cast<i::Axis>(axis), 1, result) == i::Error::none && result == positive[axis],
              "Each positive world-axis quarter turn matches its literal right-hand basis.");
        check(i::rotate({}, static_cast<i::Axis>(axis), -1, result) == i::Error::none && result == negative[axis],
              "Each negative world-axis quarter turn matches its literal inverse basis.");
    }
    i::Orientation xz, zx;
    check(i::rotate({}, i::Axis::x, 1, xz) == i::Error::none &&
          i::rotate(xz, i::Axis::z, 1, xz) == i::Error::none &&
          xz == i::Orientation{{{F::positive_y, F::positive_z, F::positive_x}}},
          "A world x then z turn has the exact expected composed basis.");
    check(i::rotate({}, i::Axis::z, 1, zx) == i::Error::none &&
          i::rotate(zx, i::Axis::x, 1, zx) == i::Error::none &&
          zx == i::Orientation{{{F::positive_z, F::negative_x, F::negative_y}}} && xz != zx,
          "World-axis rotations do not commute, even when their counts are equal.");
}

void complete_group() {
    std::vector<i::Orientation> proper;
    for (unsigned x = 0; x < 6; ++x) {
        for (unsigned y = 0; y < 6; ++y) {
            for (unsigned z = 0; z < 6; ++z) {
                const std::array<unsigned, 3> axes{{x / 2, y / 2, z / 2}};
                unsigned inversions{};
                for (unsigned a = 0; a < 3; ++a) for (unsigned b = a + 1; b < 3; ++b) inversions += axes[a] > axes[b];
                const bool distinct = axes[0] != axes[1] && axes[0] != axes[2] && axes[1] != axes[2];
                const bool right_handed = distinct && ((inversions + x % 2 + y % 2 + z % 2) % 2 == 0);
                const i::Orientation pose{{{static_cast<F>(x), static_cast<F>(y), static_cast<F>(z)}}};
                check((i::validate(pose) == i::Error::none) == right_handed,
                      "All 216 signed-axis records agree with independently computed permutation/sign parity.");
                if (right_handed) proper.push_back(pose);
            }
        }
    }
    check(proper.size() == 24, "Exactly twenty-four proper indexed orientations are representable.");
    for (const auto& pose : proper) {
        unsigned images{};
        for (unsigned face = 0; face < 6; ++face) {
            F world{}, local{};
            check(i::world_face(pose, static_cast<F>(face), world) == i::Error::none &&
                  i::local_face(pose, world, local) == i::Error::none && local == static_cast<F>(face),
                  "Each original work face survives a world/local round trip in every proper orientation.");
            images |= 1U << static_cast<unsigned>(world);
        }
        check(images == 0x3f, "A proper orientation exposes six distinct original faces without duplication or omission.");
        for (unsigned axis = 0; axis < 3; ++axis) {
            for (const auto direction : {-1, 1}) {
                i::Orientation turned, back;
                check(i::rotate(pose, static_cast<i::Axis>(axis), direction, turned) == i::Error::none &&
                      i::validate(turned) == i::Error::none &&
                      i::rotate(turned, static_cast<i::Axis>(axis), -direction, back) == i::Error::none && back == pose,
                      "Quarter-turn closure and inverse hold across the entire proper orientation group.");
                auto full = pose;
                for (int step = 0; step < 4; ++step) {
                    check(i::rotate(full, static_cast<i::Axis>(axis), direction, full) == i::Error::none,
                          "Aliased planning supports each valid indexed step without an intermediate invalid pose.");
                }
                check(full == pose, "Four real quarter turns return every starting orientation exactly.");
            }
        }
    }
}

void retained_work() {
    i::Job job{91, {}, 0x30, 0};
    const auto original = job;
    i::Job output{999, {}, i::all_faces, 1};
    const auto sentinel = output;
    check(i::plan_stamp(job, F::positive_y, output) == i::Error::unrequested_face && output == sentinel && job == original,
          "A wrong presented face preserves the original work and every output field.");
    check(i::plan_stamp(job, static_cast<F>(255), output) == i::Error::invalid_face && output == sentinel && job == original,
          "An invalid tool contact normal cannot mark an arbitrary face or change the retained piece.");
    check(i::plan_turn(job, i::Axis::x, -1, job) == i::Error::none &&
          i::plan_stamp(job, F::positive_y, job) == i::Error::none && job.marked == 0x10,
          "The first quarter turn presents and marks the original positive z face.");
    const auto first_mark = job;
    check(i::plan_stamp(job, F::positive_y, output) == i::Error::already_marked && output == sentinel && job == first_mark,
          "A repeated stroke cannot replace the job, clear progress or add a different mark.");
    check(i::plan_turn(job, i::Axis::x, -1, job) == i::Error::none &&
          i::plan_turn(job, i::Axis::x, -1, job) == i::Error::none && job.marked == 0x10,
          "Indexing away from a completed face retains its original mark.");
    check(i::plan_stamp(job, F::positive_y, job) == i::Error::none && job.marked == 0x30 &&
          job.id == 91 && job.required == original.required,
          "The opposite original face completes the same retained work identity and requirements.");
    check(i::release_ready(job) == i::Error::not_home, "Completed work cannot imply that its holder returned home.");
    check(i::release_ready(job, job.orientation) == i::Error::none,
          "A trusted fixture may declare another proper orientation as its own holder home.");
    check(i::plan_turn(job, i::Axis::x, -1, job) == i::Error::none && job.orientation == i::Orientation{} &&
          i::release_ready(job) == i::Error::none && job.id == 91 && job.marked == 0x30,
          "The fourth turn returns home with the same completed original work intact.");
    const auto saved = job;
    auto restored = saved;
    check(i::validate(restored) == i::Error::none && i::release_ready(restored) == i::Error::none && restored == saved,
          "Literal caller-owned metadata resumes without normalization or an invented replacement piece.");
    i::Job maximum{std::numeric_limits<factory::materials::WorkId>::max(), {}, 0x04, 0};
    check(i::plan_stamp(maximum, F::positive_y, maximum) == i::Error::none &&
          maximum.id == std::numeric_limits<factory::materials::WorkId>::max() && maximum.marked == 0x04,
          "Marking preserves even the maximum original identity without allocating or incrementing it.");
}

void refusals() {
    const std::array<i::Orientation, 3> invalid{{
        {{{F::positive_x, F::positive_y, F::negative_z}}},
        {{{F::positive_x, F::positive_x, F::positive_z}}},
        {{{static_cast<F>(255), F::positive_y, F::positive_z}}},
    }};
    const i::Orientation sentinel{{{F::positive_x, F::positive_z, F::negative_y}}};
    for (const auto& bad : invalid) {
        auto output = sentinel;
        F face = F::negative_z;
        check(i::rotate(bad, i::Axis::x, 1, output) == i::Error::invalid_orientation && output == sentinel,
              "Reflections, duplicate axes and malformed faces cannot be normalized into a valid pose.");
        check(i::world_face(bad, F::positive_x, face) == i::Error::invalid_orientation && face == F::negative_z &&
              i::local_face(bad, F::positive_x, face) == i::Error::invalid_orientation && face == F::negative_z,
              "Invalid orientation lookup leaves both local/world face outputs unchanged.");
    }
    for (const auto direction : {0, 2, -2, std::numeric_limits<int>::min(), std::numeric_limits<int>::max()}) {
        auto output = sentinel;
        check(i::rotate({}, i::Axis::x, direction, output) == i::Error::invalid_direction && output == sentinel,
              "Unsupported turns cannot silently skip physical quarter-turn steps.");
    }
    auto orientation = sentinel;
    check(i::rotate({}, static_cast<i::Axis>(255), 1, orientation) == i::Error::invalid_axis && orientation == sentinel,
          "A malformed axis cannot index the holder.");
    F face = F::negative_z;
    check(i::world_face({}, static_cast<F>(6), face) == i::Error::invalid_face && face == F::negative_z &&
          i::local_face({}, static_cast<F>(255), face) == i::Error::invalid_face && face == F::negative_z,
          "Invalid queried faces cannot overwrite the caller's last confirmed face.");
    const std::array<i::Job, 5> bad_jobs{{{0, {}, 0x30, 0}, {-1, {}, 0x30, 0}, {7, {}, 0, 0},
                                        {7, {}, 0x80, 0}, {7, {}, 0x30, 0x01}}};
    const i::Job sentinel_job{999, sentinel, i::all_faces, 1};
    for (const auto& bad : bad_jobs) {
        auto output = sentinel_job;
        check(i::plan_turn(bad, i::Axis::x, 1, output) == i::Error::invalid_job && output == sentinel_job &&
              i::plan_stamp(bad, F::positive_y, output) == i::Error::invalid_job && output == sentinel_job &&
              i::release_ready(bad) == i::Error::invalid_job,
              "Malformed identities, requirements and progress are refused consistently without a fallback job.");
    }
    const i::Job complete{7, {}, 0x04, 0x04};
    check(i::release_ready(complete, invalid[0]) == i::Error::invalid_orientation,
          "The immutable home profile must itself be a proper orientation.");
    check(i::release_ready({7, {}, 0x04, 0}) == i::Error::unfinished,
          "A home holder cannot release an unfinished original piece.");
}

void cli(std::initializer_list<std::string_view> args, int code, std::string_view expected) {
    std::ostringstream output, errors;
    const auto result = i::workbench({args.begin(), args.size()}, output, errors);
    check(result == code && (output.str() + errors.str()).find(expected) != std::string::npos,
          "The actual command parser preserves the expected indexing outcome and explanation.");
}

void command_cases() {
    cli({}, 0, "index_workbench list");
    cli({"list"}, 0, "complete inspection block");
    cli({"opposites"}, 1, "marked none");
    cli({"opposites", "stamp"}, 1, "not part of this job");
    cli({"opposites", "y+"}, 1, "axis is locked");
    cli({"opposites", "x-", "stamp", "stamp"}, 1, "already marked");
    cli({"opposites", "x-", "stamp", "x-", "x-", "stamp", "x-", "release"}, 0, "original workpiece 7 released");
    cli({"opposites", "x+", "stamp", "x+", "x+", "stamp", "x+", "release"}, 0, "Solved:");
    cli({"opposites", "stamp", "x-", "stamp", "stamp", "x-", "x-", "stamp", "x-", "release"}, 0,
        "original workpiece 7 released");
    cli({"corner", "stamp", "z+", "stamp", "x-", "stamp", "x+", "z-", "release"}, 0, "Solved:");
    cli({"corner", "stamp", "z+", "stamp", "x-", "stamp", "x+", "z-"}, 1, "Ready at home");
    cli({"corner", "stamp", "z+", "stamp", "x-", "stamp", "release"}, 1, "Return the holder home");
    cli({"corner", "release"}, 1, "Complete every required face");
    cli({"corner", "release", "y+", "stamp", "z+", "stamp", "x-", "stamp", "x+", "z-", "release"}, 0,
        "original workpiece 7 released");
    cli({"all_faces", "stamp", "x-", "stamp", "x-", "stamp", "x-", "stamp", "x-", "z+", "stamp",
         "z-", "z-", "stamp", "z+", "release"}, 0, "Solved:");
    cli({"opposites", "x-", "stamp", "x-", "x-", "stamp", "x-", "release", "stamp"}, 2, "No actions may follow release");
    cli({"missing"}, 2, "Unknown puzzle");
    for (const auto token : {"x2", "x", "w+", "X+", "", "reset", "new_work"}) {
        cli({"opposites", token}, 2, "Unknown action");
    }
    std::ostringstream output, errors;
    output.setstate(std::ios::badbit);
    const std::array<std::string_view, 1> args{{"list"}};
    check(i::workbench(args, output, errors) == 2, "A failed output stream cannot report a successfully completed fixture.");
}
}  // namespace

int main() {
    literal_rotations();
    complete_group();
    retained_work();
    refusals();
    command_cases();
    std::cout << checks << " indexing fixture checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
