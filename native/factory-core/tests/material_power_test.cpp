#include "factory/materials.hpp"

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
    for (const auto invalid : {m::Quantity{0}, m::maximum_work_subticks_per_tick + 1}) {
        require(m::step(slow, config, line, {false, false, true, invalid}) == m::Error::invalid_path && slow == blocked,
                "A malformed speed is refused without changing work or material custody.");
    }
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
}  // namespace

int main() {
    try {
        fractional_gear_speed();
        legacy_order_and_carried_work();
        independent_senders_and_partial_pause();
        ready_work_and_disable();
        absent_masks_and_exhausted_identity();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_machine_power\",\"checks\":"
                  << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "material_power_test: " << error.what() << '\n';
        return 1;
    }
}
