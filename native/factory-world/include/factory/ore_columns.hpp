#pragma once

#include "factory/excavation.hpp"
#include "factory/materials.hpp"

#include <optional>
#include <string>

namespace factory::world::ore_columns {
// Immutable Profile facts supplied from trusted terrain, never from a save or
// client. All seed columns are pristine; zero-stock cells bind boundary ground.
struct Seed {
    excavation::Grid grid;
    excavation::Columns columns;
    // Optional exact points on the trusted pristine surface. A sloped column's
    // horizontal cutting plane is its maximum height; hand reach uses this
    // actual surface point, lowering it as that column is excavated.
    std::map<excavation::Cell, excavation::Point> contact_points{};
    bool operator==(const Seed&) const = default;
};

// Persisted in the canonical World state. Initial quantities/heights must still
// match Seed. These are addressed source stock, not a second material pool:
// their remaining sum must equal materials::State::stock.source exactly.
using Field = excavation::Columns;

enum class Error {
    none, invalid_seed, invalid_field, invalid_material, invalid_receiver,
    invalid_capacity,
};
[[nodiscard]] Error validate(const Seed&, const Field&, const materials::State&) noexcept;
[[nodiscard]] std::optional<Field> initialize(const Seed&, const materials::State&);

struct Result {
    // Error::none still permits a normal cutting refusal (for example full
    // output or no contact). Only produced_units reports newly owned material.
    Error error{Error::none};
    excavation::Status cutting{excavation::Status::no_work};
    materials::Error material_error{materials::Error::none};
    materials::Quantity produced_units{};
    materials::Quantity work_spent{};
};

// Powered cutting leaves conserved material at the actual cut floor. World
// derives the ground address from the admitted cutting contact.
[[nodiscard]] Result cut_to_ground(const Seed&, Field&, materials::State&,
    const materials::Config&, const materials::Path&, const excavation::Contact&,
    materials::Quantity supplied_work, const materials::DropPoint&);

// Timed hand work uses the same local bite after World admits actor identity,
// actual selected contact and reach. Capacity comes from the material profile.
// No regional ID or distant reserve is a valid substitute for that contact.
[[nodiscard]] Result cut_to_actor(const Seed&, Field&, materials::State&,
    const materials::Config&, const materials::Path&, const excavation::Contact&,
    materials::Quantity supplied_work, const std::string& actor);

// Authoritative geometry for native collision and its presentation adapter.
// Invalid/restored-refilled fields refuse rather than projecting a second mesh.
[[nodiscard]] std::optional<excavation::Surface> surface(
    const Seed&, const Field&, const materials::State&, excavation::Cell);
[[nodiscard]] std::optional<std::vector<excavation::FacePatch>> exposed_faces(
    const Seed&, const Field&, const materials::State&, excavation::Cell);
[[nodiscard]] const char* error_name(Error) noexcept;
}  // namespace factory::world::ore_columns
