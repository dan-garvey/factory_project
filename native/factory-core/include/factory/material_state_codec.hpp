#pragma once

#include "factory/materials.hpp"
#include "factory/value.hpp"

#include <string>
#include <variant>
#include <vector>

namespace factory::materials {

enum class CodecReason {
    invalid_roster,
    roster_mismatch,
    wrong_type,
    missing_field,
    unexpected_field,
    unsupported_schema,
    invalid_material_state,
};

struct CodecRefusal {
    CodecReason reason{CodecReason::invalid_material_state};
    std::string path{"$"};
    Error material_error{Error::none};
};

using MaterialEncoding = std::variant<values::Value, CodecRefusal>;
using MaterialDecoding = std::variant<State, CodecRefusal>;

[[nodiscard]] const char* codec_reason_name(CodecReason) noexcept;

// Experimental material subrecord version 1, not a complete World checkpoint.
// Config, topology and the expected actor roster are trusted caller context.
// Roster entries must be unique and nonempty; their set must equal State.cargo.
// Other actor-identity policy and input byte/collection limits belong to World.
// Every quantity, serial, recipe parameter and version uses exact integer Values.
// Missing/unknown fields and numeric coercion refuse. Null means no processing
// lot; a lot with zero remaining ticks stays present. Cargo lot order is retained.
// Both directions run canonical material validation without changing inputs.
// Allocation failures may propagate; no live State or file is committed here.
[[nodiscard]] MaterialEncoding encode_material_state(
    const State&, const Config&, const Path&, const std::vector<std::string>& roster);
[[nodiscard]] MaterialDecoding decode_material_state(
    const values::Value&, const Config&, const Path&, const std::vector<std::string>& roster);

// History, prior serial use, entity generations, cache, file publication and
// atomic World import remain the containing authority's responsibilities.

}  // namespace factory::materials
