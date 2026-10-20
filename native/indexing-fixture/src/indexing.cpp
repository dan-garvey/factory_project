#include "factory/indexing.hpp"

namespace factory::indexing {
namespace {
using Vector = std::array<int, 3>;
bool valid(Face face) noexcept { return static_cast<unsigned>(face) < 6; }
Face opposite(Face face) noexcept { return static_cast<Face>(static_cast<unsigned>(face) ^ 1U); }
Vector vector(Face face) noexcept {
    Vector result{};
    const auto value = static_cast<unsigned>(face);
    result[value / 2] = value % 2 == 0 ? 1 : -1;
    return result;
}
Face face(const Vector& v) noexcept {
    for (unsigned axis = 0; axis < 3; ++axis) {
        if (v[axis]) return static_cast<Face>(axis * 2 + (v[axis] < 0 ? 1 : 0));
    }
    return static_cast<Face>(255);
}
Vector cross(const Vector& a, const Vector& b) noexcept {
    return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}
}  // namespace

const char* face_name(Face face) noexcept {
    switch (face) {
        case Face::positive_x: return "X+";
        case Face::negative_x: return "X-";
        case Face::positive_y: return "Y+";
        case Face::negative_y: return "Y-";
        case Face::positive_z: return "Z+";
        case Face::negative_z: return "Z-";
    }
    return "?";
}

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_orientation: return "invalid_orientation";
        case Error::invalid_axis: return "invalid_axis";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_face: return "invalid_face";
        case Error::invalid_job: return "invalid_job";
        case Error::unrequested_face: return "unrequested_face";
        case Error::already_marked: return "already_marked";
        case Error::unfinished: return "unfinished";
        case Error::not_home: return "not_home";
    }
    return "unknown";
}

const char* explanation(Error error) noexcept {
    switch (error) {
        case Error::none: return "The operation is valid.";
        case Error::invalid_orientation: return "The holder orientation is not a proper indexed rotation.";
        case Error::invalid_axis: return "Choose a real holder axis.";
        case Error::invalid_direction: return "Index one positive or negative quarter turn at a time.";
        case Error::invalid_face: return "The contact normal must name one of the six faces.";
        case Error::invalid_job: return "The retained job identity or required face marks are invalid.";
        case Error::unrequested_face: return "The contacted face is not part of this job.";
        case Error::already_marked: return "The contacted face is already marked. Present another required face.";
        case Error::unfinished: return "Complete every required face before releasing the piece.";
        case Error::not_home: return "All required faces are complete. Return the holder home before release.";
    }
    return "Unknown indexing refusal.";
}

Error validate(const Orientation& orientation) noexcept {
    for (const auto face : orientation.positive_axes) if (!valid(face)) return Error::invalid_orientation;
    return cross(vector(orientation.positive_axes[0]), vector(orientation.positive_axes[1])) ==
           vector(orientation.positive_axes[2]) ? Error::none : Error::invalid_orientation;
}

Error validate(const Job& job) noexcept {
    if (job.id <= 0 || job.required == 0 || (job.required & ~all_faces) != 0 ||
        (job.marked & ~job.required) != 0) return Error::invalid_job;
    return validate(job.orientation);
}

Error rotate(const Orientation& orientation, Axis axis, int direction, Orientation& output) noexcept {
    const auto error = validate(orientation);
    if (error != Error::none) return error;
    if (static_cast<unsigned>(axis) > 2) return Error::invalid_axis;
    if (direction != 1 && direction != -1) return Error::invalid_direction;
    Orientation next;
    for (std::size_t i = 0; i < next.positive_axes.size(); ++i) {
        const auto v = vector(orientation.positive_axes[i]);
        Vector turned{};
        switch (axis) {
            case Axis::x: turned = {v[0], -direction * v[2], direction * v[1]}; break;
            case Axis::y: turned = {direction * v[2], v[1], -direction * v[0]}; break;
            case Axis::z: turned = {-direction * v[1], direction * v[0], v[2]}; break;
        }
        next.positive_axes[i] = face(turned);
    }
    const auto next_error = validate(next);
    if (next_error != Error::none) return next_error;
    output = next;
    return Error::none;
}

Error world_face(const Orientation& orientation, Face local, Face& output) noexcept {
    const auto error = validate(orientation);
    if (error != Error::none) return error;
    if (!valid(local)) return Error::invalid_face;
    const auto value = static_cast<unsigned>(local);
    const auto image = orientation.positive_axes[value / 2];
    output = value % 2 == 0 ? image : opposite(image);
    return Error::none;
}

Error local_face(const Orientation& orientation, Face world, Face& output) noexcept {
    const auto error = validate(orientation);
    if (error != Error::none) return error;
    if (!valid(world)) return Error::invalid_face;
    for (unsigned axis = 0; axis < 3; ++axis) {
        const auto image = orientation.positive_axes[axis];
        if (image == world) { output = static_cast<Face>(axis * 2); return Error::none; }
        if (opposite(image) == world) { output = static_cast<Face>(axis * 2 + 1); return Error::none; }
    }
    return Error::invalid_orientation;
}

Error plan_turn(const Job& job, Axis axis, int direction, Job& output) noexcept {
    const auto error = validate(job);
    if (error != Error::none) return error;
    auto next = job;
    const auto turn_error = rotate(job.orientation, axis, direction, next.orientation);
    if (turn_error != Error::none) return turn_error;
    output = next;
    return Error::none;
}

Error plan_stamp(const Job& job, Face world_contact_normal, Job& output) noexcept {
    const auto error = validate(job);
    if (error != Error::none) return error;
    Face exposed{};
    const auto face_error = local_face(job.orientation, world_contact_normal, exposed);
    if (face_error != Error::none) return face_error;
    const unsigned bit = 1U << static_cast<unsigned>(exposed);
    if ((job.required & bit) == 0) return Error::unrequested_face;
    if ((job.marked & bit) != 0) return Error::already_marked;
    auto next = job;
    next.marked = static_cast<FaceMask>(job.marked | bit);
    output = next;
    return Error::none;
}

Error release_ready(const Job& job, const Orientation& home) noexcept {
    const auto error = validate(job);
    if (error != Error::none) return error;
    const auto home_error = validate(home);
    if (home_error != Error::none) return home_error;
    if (job.marked != job.required) return Error::unfinished;
    return job.orientation == home ? Error::none : Error::not_home;
}
}  // namespace factory::indexing
