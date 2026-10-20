#pragma once

#include "factory/world.hpp"

#include <string>
#include <variant>

namespace factory::world {

enum class CheckpointReason {
    limit, wrong_type, missing_field, unexpected_field, unsupported_schema,
    profile_mismatch, wrong_context, invalid_material, invalid_history, invalid_world,
};

struct CheckpointRefusal {
    CheckpointReason reason{CheckpointReason::invalid_world};
    std::string path{"$"};
};

using CheckpointEncoding = std::variant<values::Value, CheckpointRefusal>;
using CheckpointDecoding = std::variant<Snapshot, CheckpointRefusal>;

// A typed logical World checkpoint, not a file format, native body registration
// record or pose restoration implementation. Store still owns file publication.
// The caller's trusted profile is compared exactly; it is never replaced by
// configuration taken from the incoming value. All schema fields are required,
// unknown fields refuse, and authority integers cannot be JSON-derived floats.
// Neither direction mutates the input or any live owner. Allocation exceptions
// may propagate before a candidate exists. No fresh-seed fallback is provided.
[[nodiscard]] CheckpointEncoding encode_checkpoint(const Profile&, const Snapshot&);
[[nodiscard]] CheckpointDecoding decode_checkpoint(
    const Profile&, const std::string& expected_context, const values::Value&);

}  // namespace factory::world
