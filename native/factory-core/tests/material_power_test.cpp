#include "factory/materials.hpp"

#include <bit>
#include <iostream>
#include <limits>
#include <stdexcept>

namespace {
namespace m = factory::materials;
int checks{};
constexpr m::Config config{2, 2, 4};
constexpr m::Path line{true, true, true, true, true, true};

void require(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

m::State seed() {
    m::State state;
    state.initial_units = 16;
    state.stock.source = 16;
    state.cargo = {{"P", {}}, {"Q", {}}};
    return state;
}

void tick(m::State& state, m::MachinePower power) {
    require(m::step(state, config, line, power) == m::Error::none,
            "The independently supplied local-power tick must succeed.");
    require(m::validate(state, config, line) == m::Error::none,
            "The complete candidate retains valid finite custody.");
}

void belt_speed_conversion() {
    require(m::belt_speed_subticks(1, 1, false) == 4096 &&
            m::belt_speed_subticks(-1, 1, false) == 4096 &&
            m::belt_speed_subticks(1, 1, true) == 2896,
            "Signed rates use the same magnitude and inclined travel is slower.");
    require(m::belt_speed_subticks(0, 1, false) == 0 && m::belt_speed_subticks(1, 0, false) == 0 &&
            m::belt_speed_subticks(1, std::numeric_limits<m::Quantity>::max(), false) == 0,
            "Stopped and malformed rates cannot move cargo; a sub-subtick rate has no artificial minimum.");
    require(m::belt_speed_subticks(std::numeric_limits<m::Quantity>::min(), 1, false) ==
                std::numeric_limits<m::Quantity>::max() &&
            m::belt_speed_subticks(std::numeric_limits<m::Quantity>::max(), 1, true) == std::numeric_limits<m::Quantity>::max(),
            "The integer speed query saturates only at its representational limit.");
}

void fractional_gear_speed() {
    auto slow = seed();
    slow.stock.source = 14;
    slow.processing = m::WorkLot{1, {2, 4}, 4};
    slow.next_work_id = 2;
    const m::MachinePower half{false, false, true, m::work_subticks_per_tick / 2};
    tick(slow, half);
    require(slow.processing->remaining_ticks == 4 &&
            slow.processing->completed_subticks == m::work_subticks_per_tick / 2,
            "Half speed retains fractional progress on the original workpiece.");
    const auto partial = slow;
    tick(slow, {false, false, false});
    require(slow == partial, "Stopped work retains its fractional progress.");
    tick(slow, half);
    require(slow.processing->remaining_ticks == 3 && slow.processing->completed_subticks == 0,
            "Two half-speed ticks advance one normal unit of work.");
    const m::MachinePower twice{false, false, true, 2 * m::work_subticks_per_tick};
    tick(slow, twice);
    require(slow.processing->remaining_ticks == 1 && slow.processing->completed_subticks == 0,
            "Double speed advances two units of the same workpiece.");
    slow.stock.output = 1;
    slow.stock.source -= 2;
    tick(slow, twice);
    require(slow.processing->remaining_ticks == 0 && slow.processing->completed_subticks == 0 &&
            slow.stock.output == 1, "A full output holds the completed workpiece without duplication.");
    const auto blocked = slow;
    tick(slow, twice);
    require(slow == blocked, "A blocked ready workpiece cannot accumulate extra progress.");
    for (const auto invalid : {m::Quantity{0}, m::Quantity{-1}}) {
        require(m::step(slow, config, line, {false, false, true, invalid}) == m::Error::invalid_path && slow == blocked,
                "A malformed speed is refused without changing work or material custody.");
    }
    auto fast = seed();
    fast.stock.source = 14;
    fast.processing = m::WorkLot{1, {2, 40}, 40};
    fast.next_work_id = 2;
    const m::Config fast_config{2, 2, 40};
    require(m::step(fast, fast_config, line, {false, false, true, 20 * m::work_subticks_per_tick}) == m::Error::none &&
                m::validate(fast, fast_config, line) == m::Error::none,
            "The high-speed work uses its configured recipe and retains custody.");
    require(fast.processing && fast.processing->remaining_ticks == 20,
            "Twenty-times speed advances twenty units of real work in one tick.");
    fast.processing->completed_subticks = m::work_subticks_per_tick - 1;
    require(m::step(fast, fast_config, line, {false, false, true, std::numeric_limits<m::Quantity>::max()}) == m::Error::none &&
                m::validate(fast, fast_config, line) == m::Error::none,
            "Extreme progress remains valid and conserves the original input.");
    require(!fast.processing && fast.stock.output == 1,
            "Extreme speed completes one buffered workpiece without overflowing progress.");
}

void reversed_belt_custody() {
    auto state = seed();
    state.stock.source = 15;
    state.stock.belt = 1;
    const m::DropPoint point{2, 0, 4};
    m::MachinePower reverse{false, true, false};
    reverse.belt_forward = false;
    reverse.reverse_drop = point;
    const auto held = state;
    tick(state, {false, false, false});
    require(state == held, "A stopped belt holds its blank before reverse travel.");
    tick(state, reverse);
    require(state.stock.belt == 0 && state.stock.input == 0 && state.dropped_material.at(point).raw_units == 1,
            "A reversed belt deposits its own blank at the supplied world point.");
    const auto dropped = state;
    tick(state, {false, false, false});
    require(state == dropped, "A stopped line retains loose material.");
    require(m::pickup_material(state, config, line, "Q", point) == m::Error::none &&
            state.dropped_material.empty() && state.cargo.at("Q").raw_units == 1,
            "An admitted actor collects the exact loose stack into canonical cargo.");
    const auto collected = state;
    require(m::pickup_material(state, config, line, "Q", point) == m::Error::unavailable_drop && state == collected,
            "A repeated fresh pickup cannot duplicate material.");
    auto restart = collected;
    restart.stock.source -= 1;
    restart.stock.belt = 1;
    tick(restart, reverse);
    require(restart.dropped_material.at(point).raw_units == 1, "A restarted reverse belt deposits its next blank at the same end.");
}

void legacy_order_and_carried_work() {
    auto state = seed();
    for (int cycle = 0; cycle < 3; ++cycle)
        require(m::step(state, config, line) == m::Error::none,
                "The existing three-argument entry point remains usable.");
    require(state.stock == m::Stock{13, 1, 1, 1, 0} && !state.processing &&
            state.next_work_id == 1,
            "The old entry point retains the literal three-tick order and counts.");
    require(m::step(state, config, line) == m::Error::none &&
            state.stock == m::Stock{12, 1, 1, 2, 0} && !state.processing &&
            state.next_work_id == 1,
            "The belt fills the second input only after the fourth tick's start phase.");
    require(m::step(state, config, line) == m::Error::none &&
            state.stock == m::Stock{11, 1, 1, 1, 0} &&
            state.processing == m::WorkLot{1, {2, 4}, 4} && state.next_work_id == 2,
            "Starting retains a fresh full-duration lot before any later advancement.");

    state = seed();
    state.stock.source = 14;
    state.cargo.at("P").work_lots = {{7, {2, 4}, 3}};
    state.next_work_id = 8;
    const auto carried = state;
    tick(state, {false, false, false});
    tick(state, {false, false, true});
    require(state == carried,
            "An enabled processor never visits a whole lot carried by an actor.");
}

void independent_senders_and_partial_pause() {
    auto state = seed();
    for (int cycle = 0; cycle < 3; ++cycle) tick(state, {true, false, false});
    require(state.stock == m::Stock{13, 2, 1, 0, 0} && !state.processing,
            "An independent collector fills only its finite output and the passive belt buffer.");
    const auto backed_up = state;
    tick(state, {true, false, false});
    require(state == backed_up, "Finite backpressure stops collection without refilling source.");

    tick(state, {false, true, false});
    require(state.stock == m::Stock{13, 2, 0, 1, 0},
            "The belt alone sends one unit into a stopped processor's passive input.");
    tick(state, {true, true, false});
    require(state.stock == m::Stock{12, 2, 1, 1, 0},
            "Collector dispatch follows the earlier belt phase in the same tick.");
    tick(state, {true, true, false});
    require(state.stock == m::Stock{11, 2, 1, 2, 0} && !state.processing &&
            state.next_work_id == 1,
            "Active senders can continue filling buffers without starting the stopped processor.");

    tick(state, {false, false, true});
    require(state.stock == m::Stock{11, 2, 1, 0, 0} &&
            state.processing == m::WorkLot{1, {2, 4}, 4} && state.next_work_id == 2,
            "Processor power starts exactly one original-recipe work lot.");
    tick(state, {false, false, true});
    require(state.processing == m::WorkLot{1, {2, 4}, 3},
            "One processor tick advances its actual positive remaining time.");
    tick(state, {false, true, false});
    require(state.stock == m::Stock{11, 2, 0, 1, 0} &&
            state.processing == m::WorkLot{1, {2, 4}, 3},
            "A belt tick can change raw custody while the same partial lot stays paused.");
    const auto paused = state;
    for (int cycle = 0; cycle < 8; ++cycle) tick(state, {false, true, false});
    require(state == paused, "Unrelated ticks do not spend or reset a paused work timer.");
    for (int cycle = 0; cycle < 3; ++cycle) tick(state, {false, false, true});
    require(state.stock == m::Stock{11, 2, 0, 1, 1} && !state.processing &&
            state.next_work_id == 2,
            "Resuming consumes only the three original remaining ticks and no new serial.");
    require(m::retrieve(state, config, line, "Q", 1) == m::Error::none &&
            state.cargo.at("Q") == m::Cargo{0, 1, {}} &&
            state.cargo.at("P") == m::Cargo{} && state.stock.source == 11,
            "The completed product retains separate actor custody and depleted source.");
}

void ready_work_and_disable() {
    auto state = seed();
    state.stock = {12, 0, 0, 0, 1};
    state.processing = m::WorkLot{7, {2, 4}, 0};
    state.next_work_id = 8;
    require(m::retrieve(state, config, line, "Q", 1) == m::Error::none,
            "The prior output can be collected while ready work still occupies the processor.");
    const auto ready = state;
    tick(state, {false, false, false});
    require(state == ready && state.processing->remaining_ticks == 0,
            "Ready zero-tick work is retained under local processor stop.");
    tick(state, {false, false, true});
    require(state.stock == m::Stock{12, 0, 0, 0, 1} && !state.processing &&
            state.next_work_id == 8 && state.cargo.at("Q").products == 1,
            "Processor power releases the same ready lot once without another identity.");

    auto disabled = line;
    disabled.powered = false;
    const auto before = state;
    require(m::step(state, config, disabled, {true, true, true}) == m::Error::none &&
            state == before, "The existing coarse fixture disable still stops all operations.");
}

void absent_masks_and_exhausted_identity() {
    auto state = seed();
    const m::Path collector_only{true, false, false, false, false, true};
    const auto before = state;
    require(m::step(state, config, collector_only, {true, true, false}) == m::Error::invalid_path &&
            state == before, "A powered absent machine refuses without changing any material.");
    require(m::step(state, config, collector_only) == m::Error::none &&
            state.stock == m::Stock{15, 1, 0, 0, 0},
            "The old entry point still supports an incomplete collector-only route.");

    state = seed();
    state.stock = {14, 0, 0, 2, 0};
    state.next_work_id = std::numeric_limits<m::WorkId>::max();
    tick(state, {true, false, false});
    require(state.stock == m::Stock{13, 1, 0, 2, 0} && !state.processing,
            "A stopped processor does not allocate a serial while another machine runs.");
    const auto exhausted = state;
    require(m::step(state, config, line, {false, false, true}) == m::Error::work_id_overflow &&
            state == exhausted, "An eligible start at serial exhaustion preserves the whole input.");

    auto bad = state;
    ++bad.stock.source;
    const auto original_bad = bad;
    auto disabled = line;
    disabled.powered = false;
    require(m::step(bad, config, disabled, {}) == m::Error::invalid_state && bad == original_bad,
            "A disabled profile never conceals malformed custody.");
}
void multi_slot_belt_lane() {
    const m::Cargo raw{1, 0, {}};
    const m::Cargo product{0, 1, {}};
    const m::Cargo lot{0, 0, {{7, {2, 4}, 3, 123}}};
    m::BeltLane lane{{raw, std::nullopt, product, lot}, 0};
    const auto original = lane;
    auto half = m::advance_belt_lane(lane, m::work_subticks_per_tick / 2, 0);
    require(half && half->candidate.slots == lane.slots && half->candidate.phase == m::work_subticks_per_tick / 2,
            "A half-speed tick retains fractional motion without teleporting items.");
    auto held = m::advance_belt_lane(half->candidate, 0, 0);
    require(held && held->candidate == half->candidate && held->delivered.empty(),
            "A stopped lane retains its material and fractional phase.");
    auto full = m::advance_belt_lane(held->candidate, m::work_subticks_per_tick / 2, 0);
    require(full && full->candidate.slots == std::vector<std::optional<m::Cargo>>{std::nullopt, raw, product, lot},
            "A blocked output propagates backpressure while filling the available gap.");
    auto drain = m::advance_belt_lane(full->candidate, 2 * m::work_subticks_per_tick, 2);
    require(drain && drain->delivered == std::vector<m::Cargo>{lot, product} &&
            drain->candidate.slots == std::vector<std::optional<m::Cargo>>{std::nullopt, std::nullopt, std::nullopt, raw},
            "A faster belt delivers the original whole items in order and preserves remaining custody.");
    auto reverse = m::advance_belt_lane(drain->candidate, -2 * m::work_subticks_per_tick, 1);
    require(reverse && reverse->candidate.slots[1] == raw && reverse->delivered.empty(),
            "A reversed belt moves the same remaining item toward the other endpoint.");
    reverse = m::advance_belt_lane(reverse->candidate, -2 * m::work_subticks_per_tick, 1);
    require(reverse && reverse->delivered == std::vector<m::Cargo>{raw},
            "A reversed belt releases its item only at the selected receiver.");
    auto reversed_fraction = m::advance_belt_lane(half->candidate, -m::work_subticks_per_tick / 2, 1);
    require(reversed_fraction && reversed_fraction->candidate == original && reversed_fraction->delivered.empty(),
            "Changing direction first cancels the retained fractional movement.");
    require(lane == original, "All proposals leave their caller's lane unchanged.");
    auto invalid = lane;
    invalid.slots[0] = m::Cargo{2, 0, {}};
    require(!m::advance_belt_lane(invalid, 1, 1) &&
            !m::advance_belt_lane(lane, m::maximum_work_subticks_per_tick + 1, 1) &&
            !m::advance_belt_lane(lane, 1, -1),
            "Malformed contents, out-of-profile speed and receiver capacity refuse atomically.");
    invalid = lane;
    invalid.slots[0] = lot;
    require(!m::advance_belt_lane(invalid, 1, 1), "Duplicate work identities cannot enter one lane proposal.");
    for (unsigned mask = 0; mask < 16; ++mask) {
        m::BeltLane sample{{std::nullopt, std::nullopt, std::nullopt, std::nullopt}, 0};
        for (std::size_t i = 0; i < sample.slots.size(); ++i)
            if (mask & (1U << i)) sample.slots[i] = raw;
        const auto count = static_cast<std::size_t>(std::popcount(mask));
        for (const auto speed : {-2 * m::work_subticks_per_tick, -m::work_subticks_per_tick,
                                 m::work_subticks_per_tick, 2 * m::work_subticks_per_tick}) {
            for (const m::Quantity capacity : {0, 1, 4}) {
                const auto moved = m::advance_belt_lane(sample, speed, capacity);
                std::size_t retained = 0;
                if (moved) for (const auto& slot : moved->candidate.slots) retained += slot.has_value();
                require(moved && retained + moved->delivered.size() == count &&
                        moved->delivered.size() <= static_cast<std::size_t>(capacity) && sample.phase == 0,
                        "Every occupancy, direction and receiver-capacity combination conserves its units.");
            }
        }
    }
}
void fractional_belt_rates() {
    m::BeltLane lane{{m::Cargo{1, 0, {}}, std::nullopt}, 0};
    for (int tick = 0; tick < 3; ++tick) {
        auto next = m::advance_belt_lane_rate(lane, 1, 3, 1, false, 0);
        require(next.has_value(), "A third-speed belt advances.");
        lane = next->candidate;
    }
    require(!lane.slots.front() && lane.slots.back() && lane.phase == 0 && lane.remainder == 0,
            "Three exact third-speed ticks move one tile without losing the fractional subtick.");
    auto forward = m::advance_belt_lane_rate(lane, 1, 3, 1, false, 0);
    auto backward = m::advance_belt_lane_rate(forward->candidate, 1, 3, -1, false, 0);
    require(backward && backward->candidate == lane,
            "Reversing the same fractional rate restores the original phase and cargo.");
    m::BeltLane tiny{{m::Cargo{1, 0, {}}, std::nullopt}, 0};
    auto slow = m::advance_belt_lane_rate(tiny, 1, 8192, 1, false, 0);
    require(slow && slow->candidate.phase == 0 && slow->candidate.remainder == 4096,
            "A sub-subtick speed does not gain an artificial minimum movement.");
    slow = m::advance_belt_lane_rate(slow->candidate, 1, 8192, 1, false, 0);
    require(slow && slow->candidate.phase == 1 && slow->candidate.remainder == 0,
            "Sub-subtick motion accumulates rather than being discarded.");
    auto invalid = lane;
    invalid.remainder_denominator = 0;
    require(!m::advance_belt_lane_rate(invalid, 1, 3, 1, false, 0),
            "An invalid saved fractional denominator is refused.");
    m::BeltLane long_lane{std::vector<std::optional<m::Cargo>>(21), 0};
    long_lane.slots.front() = m::Cargo{1, 0, {}};
    auto fast = m::advance_belt_lane_rate(long_lane, 20, 1, 1, false, 0);
    require(fast && fast->candidate.slots.back().has_value() && fast->candidate.phase == 0,
            "A twenty-times shaft rate carries cargo twenty tiles in one tick.");
    auto inclined_fast = m::advance_belt_lane_rate(long_lane, 20, 1, 1, true, 0);
    require(inclined_fast && inclined_fast->candidate.slots[14].has_value() && inclined_fast->candidate.phase == 576,
            "The full high rate also controls inclined displacement and retained phase.");
    for (const int direction : {-1, 1}) for (const m::Quantity capacity : {0, 1, 21}) {
        m::BeltLane full{std::vector<std::optional<m::Cargo>>(21, m::Cargo{1, 0, {}}), 0};
        auto first = m::advance_belt_lane(full, direction * 16 * m::work_subticks_per_tick, capacity);
        auto second = m::advance_belt_lane(first->candidate, direction * 5 * m::work_subticks_per_tick,
            capacity - static_cast<m::Quantity>(first->delivered.size()));
        auto extreme = m::advance_belt_lane_rate(full, std::numeric_limits<m::Quantity>::min(), 1, direction, false, capacity);
        require(extreme && second && extreme->candidate.slots == second->candidate.slots &&
                    extreme->delivered.size() == first->delivered.size() + second->delivered.size() &&
                    extreme->candidate.phase == 0,
                "Extreme shaft rates reach the same conserved finite-lane result without unbounded stepping.");
    }
}
}  // namespace

int main() {
    try {
        belt_speed_conversion();
        fractional_gear_speed();
        reversed_belt_custody();
        legacy_order_and_carried_work();
        independent_senders_and_partial_pause();
        ready_work_and_disable();
        absent_masks_and_exhausted_identity();
        multi_slot_belt_lane();
        fractional_belt_rates();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_machine_power\",\"checks\":"
                  << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "material_power_test: " << error.what() << '\n';
        return 1;
    }
}
