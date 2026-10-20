#pragma once

#include "factory/value.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace factory::authority {

using Integer = std::int64_t;
using Object = values::Value::Object;
using Point = std::array<double, 3>;

// Operational bounds for this first adapter, not permanent game requirements.
inline constexpr std::size_t maximum_records = 4096;
inline constexpr std::size_t maximum_targets = 32;

enum class Error {
    none, invalid_history, wrong_context, missing_identity, invalid_intent,
    request_reuse, invalid_outcome, limit, counter_overflow,
    wrong_actor, actor_unready, invalid_actor_sample, out_of_reach,
};

struct Record {
    Object intent;
    Object result;
};

// The future sole World owns this value alongside its canonical material state.
// There is no independent live cache, mutation method, file or Session here.
struct History {
    std::string context;
    Integer order{};
    std::vector<Record> records;
};

struct Lookup {
    Error error{Error::none};
    std::optional<Record> cached;
};

struct Outcome {
    bool accepted{};
    std::string reason;
    std::string entity;
    // Additional immutable facts, such as original reach or blocker receipts.
    // These cannot replace the authoritative envelope fields.
    Object facts;
};

struct Preparation {
    Error error{Error::none};
    std::optional<History> next;
    std::optional<Record> record;
    bool duplicate{};
    Integer resulting_revision{};
};

[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] Error validate_history(const History&, Integer current_revision);

// Call before any current admission or rule evaluation. A retry returns the
// original stored result; no current pose, topology or recipe is an input.
[[nodiscard]] Lookup inspect_request(const History&, const Object& intent,
                                     Integer current_revision);

// Pure preparation, never a commit. The owning World must validate and commit
// the material/topology candidate and this history candidate together.
// Refused new commands are cached too. Allocation failures leave inputs intact.
[[nodiscard]] Preparation prepare_record(const History&, const Object& intent,
                                         const Outcome&, Integer current_revision);

struct EncodedHistory {
    Error error{Error::none};
    std::optional<values::Value> value;
};
struct DecodedHistory {
    Error error{Error::none};
    std::optional<History> history;
};

// A versioned native-value subrecord, not a complete world/Store checkpoint.
// Operation-specific history, identity generations and custody need World checks.
[[nodiscard]] EncodedHistory encode_history(const History&, Integer current_revision);
[[nodiscard]] DecodedHistory decode_history(const values::Value&, Integer current_revision);

struct ActorCut {
    std::string actor;
    Point position{};
    Integer native_epoch{};
    bool ready{};
    double build_reach{};
};
struct ReachReceipt {
    ActorCut cut;
    std::vector<Point> targets;
    std::vector<double> distances_squared;
    bool reachable{};
};
struct ReachResult {
    Error error{Error::none};
    std::optional<ReachReceipt> receipt;
};

// Authority-internal inputs only: Session binds the actor, the registered native
// producer supplies the cut, and World derives targets from canonical topology.
// This is not a pose setter, registration API or acceptance of client targets.
// All targets must pass literal scalar 3D distance, with no reach epsilon.
[[nodiscard]] ReachResult check_reach(const std::string& bound_actor,
                                      const ActorCut&, const std::vector<Point>&);

}  // namespace factory::authority
