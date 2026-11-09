#pragma once
#include "factory/ore_columns.hpp"
#include "factory/value.hpp"

namespace factory::world::ore_columns {
// The trusted seed is included in Profile identity, never reconstructed from
// the saved field. Saved mutable columns contain only remaining stock and work.
[[nodiscard]] std::optional<values::Value> encode_seed(const Seed&);
[[nodiscard]] std::optional<values::Value> encode_field(
    const Seed&, const Field&, const materials::State&);
[[nodiscard]] std::optional<Field> decode_field(
    const Seed&, const values::Value&, const materials::State&);
}
