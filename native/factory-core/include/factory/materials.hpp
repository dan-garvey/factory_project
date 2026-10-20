#pragma once

#include <cstdint>
#include <map>
#include <string>

namespace factory::materials {

using Quantity = std::int64_t;

// These are revisable fixture values, supplied by the caller, not game content.
struct Config {
    Quantity input_units_per_product{1};
    Quantity collector_capacity{1};
    Quantity cycle_ticks{2};
};

struct Stock {
    Quantity source{};
    Quantity collector{};
    Quantity belt{};
    Quantity input{};
    Quantity held{};
    Quantity output{};
    bool operator==(const Stock&) const = default;
};

struct State {
    Quantity initial_units{};
    Stock stock;
    std::map<std::string, Quantity> inventories;
    Quantity remaining{};
    bool operator==(const State&) const = default;
};

// The current topology authority supplies these facts. This library does not
// infer transmission, accept client links, or create another mechanical owner.
struct Path {
    bool collector_present{};
    bool belt_present{};
    bool processor_present{};
    bool collector_to_belt{};
    bool belt_to_processor{};
    bool powered{};
};

enum class Error {
    none,
    invalid_configuration,
    invalid_state,
    invalid_path,
    quantity_overflow,
    invalid_actor,
    unavailable_output,
};

[[nodiscard]] const char* error_name(Error error) noexcept;
[[nodiscard]] Error validate(const State&, const Config&, const Path&) noexcept;

// A refusal leaves every field unchanged. One step advances only material work;
// the existing command owner still owns revisions, request identity and replay.
[[nodiscard]] Error step(State&, const Config&, const Path&);

// Call only after the authoritative adapter has admitted this actor and reach
// and has excluded a cached request. This function is not an admission API.
[[nodiscard]] Error retrieve(State&, const Config&, const Path&,
                             const std::string& actor, Quantity amount);

}  // namespace factory::materials
