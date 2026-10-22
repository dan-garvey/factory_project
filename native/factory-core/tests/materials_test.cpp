#include "factory/materials.hpp"

#include <iostream>
#include <limits>
#include <string>

namespace m = factory::materials;
namespace {
int checks = 0;
int failures = 0;
const m::Path complete{true, true, true, true, true, true};

void check(bool condition, const std::string& label) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << label << '\n'; }
}
m::WorkLot lot(m::WorkId id, m::Quantity remaining) { return {id, {2, 2}, remaining}; }
m::State snapshot(m::Quantity initial, m::Stock stock,
                  std::optional<m::WorkLot> work = {}, m::WorkId next = 1) {
    return {initial, stock, {{"P", {}}, {"Q", {}}}, work, next};
}
m::State fresh(m::Quantity amount) { return snapshot(amount, {amount, 0, 0, 0, 0}); }

void advance(m::State& state, const m::Config& config, const m::Path& path, int count) {
    for (int tick = 0; tick < count; ++tick)
        check(m::step(state, config, path) == m::Error::none, "A valid tick preserves all finite material.");
}
void refusal(m::State state, const m::Config& config, const m::Path& path,
             m::Error error, const std::string& label) {
    const auto before = state;
    check(m::step(state, config, path) == error, label);
    check(state == before, "A refused tick leaves the complete state unchanged.");
}

void processing() {
    const m::Config pair{2, 2, 2};
    auto state = fresh(8);
    advance(state, pair, complete, 3);
    check(state == snapshot(8, {5, 1, 1, 1, 0}),
          "The original three-tick snapshot cannot start a recipe from only one input.");
    advance(state, pair, complete, 4);
    check(state == snapshot(8, {1, 1, 1, 1, 1}, lot(2, 2), 3),
          "The original seven-tick holdings retain the second lot and its full new timer.");
    advance(state, pair, complete, 5);
    check(state == snapshot(8, {0, 1, 1, 2, 1}, lot(2, 0), 3),
          "The original blocked holdings retain one ready whole lot, not duplicated raw stock.");
    const auto blocked = state;
    advance(state, pair, complete, 5);
    check(state == blocked, "Full output preserves the entire blocked state, including serials.");
    for (int tick = 0; tick < 32; ++tick) {
        if (state.stock.output > 0)
            check(m::retrieve(state, pair, complete, "P", 1) == m::Error::none,
                  "Only the named admitted actor receives the finished product.");
        advance(state, pair, complete, 1);
    }
    if (state.stock.output > 0)
        check(m::retrieve(state, pair, complete, "P", 1) == m::Error::none, "The last product is retrievable.");
    auto expected = snapshot(8, {}, {}, 5);
    expected.cargo.at("P").products = 4;
    check(state == expected, "The original eight-input fixture ends as four products and four allocated lots.");

    auto single = fresh(4);
    const m::Config one{1, 1, 2};
    for (int tick = 0; tick < 32; ++tick) {
        if (single.stock.output > 0)
            check(m::retrieve(single, one, complete, "Q", 1) == m::Error::none, "The one-input fixture preserves Q custody.");
        advance(single, one, complete, 1);
    }
    expected = snapshot(4, {}, {}, 5);
    expected.cargo.at("Q").products = 4;
    check(single == expected, "Four one-input units end as four products without another material rule.");

    auto pressure = fresh(20);
    advance(pressure, pair, complete, 12);
    check(pressure == snapshot(20, {11, 2, 1, 2, 1}, lot(2, 0), 3),
          "The original twenty-input backpressure snapshot retains every physical holder.");
    const auto limit = pressure;
    advance(pressure, pair, complete, 4);
    check(pressure == limit, "Backpressure does not discard source stock or allocate more work.");
}

void topology_and_power() {
    const m::Config one{1, 1, 2};
    auto path = complete;
    path.collector_to_belt = false;
    path.belt_to_processor = false;
    auto disconnected = fresh(5);
    advance(disconnected, one, path, 8);
    check(disconnected == snapshot(5, {4, 1, 0, 0, 0}), "Disconnected machines do not route material.");
    auto absent = fresh(5);
    advance(absent, one, {}, 8);
    check(absent == fresh(5), "Absent collection machinery cannot extract finite feed.");

    const m::Config pair{2, 2, 2};
    auto stopped = complete;
    stopped.powered = false;
    auto partial = snapshot(2, {}, lot(1, 1), 2);
    const auto partial_before = partial;
    advance(partial, pair, stopped, 3);
    check(partial == partial_before, "Stopped power preserves positive partial-cycle work exactly.");
    advance(partial, pair, complete, 1);
    check(partial == snapshot(2, {0, 0, 0, 0, 1}, {}, 2), "One remaining tick completes the same lot exactly once.");

    auto ready = snapshot(4, {0, 0, 0, 0, 1}, lot(1, 0), 2);
    const auto before = ready;
    advance(ready, pair, stopped, 5);
    advance(ready, pair, complete, 5);
    check(ready == before, "Both stopped and powered full-output cases preserve ready work.");
    check(m::retrieve(ready, pair, complete, "Q", 1) == m::Error::none, "Q receives the existing output.");
    check(ready.processing == lot(1, 0) && m::validate(ready, pair, complete) == m::Error::none,
          "Ready work remains valid after retrieval and before the next tick.");
    advance(ready, pair, complete, 1);
    check(ready.stock.output == 1 && !ready.processing, "The original ready lot releases once.");
    check(m::retrieve(ready, pair, complete, "P", 1) == m::Error::none, "P receives the released product.");
    auto expected = snapshot(4, {}, {}, 2);
    expected.cargo.at("P").products = expected.cargo.at("Q").products = 1;
    check(ready == expected, "Both individual recipients and the original next serial remain exact.");
}

void refusals() {
    const m::Config one{1, 1, 2}, pair{2, 2, 2};
    auto bad = fresh(8);
    bad.stock.source = -1;
    refusal(bad, one, complete, m::Error::invalid_state, "Negative stock refuses.");
    bad = fresh(8); bad.stock.source = 7;
    refusal(bad, one, complete, m::Error::invalid_state, "Missing material refuses.");
    bad = fresh(8); bad.stock.source = 9;
    refusal(bad, one, complete, m::Error::invalid_state, "Duplicated material refuses.");
    bad = fresh(8); bad.cargo.at("P").raw_units = -1;
    refusal(bad, one, complete, m::Error::invalid_state, "Negative carried raw stock refuses.");
    bad = fresh(8); bad.cargo.at("P").products = -1;
    refusal(bad, one, complete, m::Error::invalid_state, "Negative carried products refuse.");
    bad = fresh(8); bad.cargo.emplace("", m::Cargo{});
    refusal(bad, one, complete, m::Error::invalid_state, "An empty Cargo owner refuses.");
    bad = snapshot(2, {}, lot(0, 1), 2);
    refusal(bad, pair, complete, m::Error::invalid_state, "A lot without a positive identity refuses.");
    bad = snapshot(2, {}, lot(1, 3), 2);
    refusal(bad, pair, complete, m::Error::invalid_state, "Progress beyond the original duration refuses.");
    bad = snapshot(2, {}, lot(1, -1), 2);
    refusal(bad, pair, complete, m::Error::invalid_state, "Negative remaining progress refuses.");
    bad = snapshot(2, {}, m::WorkLot{1, {1, 2}, 1}, 2);
    refusal(bad, pair, complete, m::Error::invalid_state, "A different work recipe refuses.");
    bad = snapshot(2, {}, lot(1, 1), 1);
    refusal(bad, pair, complete, m::Error::invalid_state, "The next serial must exceed current work.");
    bad = snapshot(4, {}, {}, 2);
    bad.cargo.at("P").work_lots.push_back(lot(1, 0));
    bad.cargo.at("Q").work_lots.push_back(lot(1, 0));
    refusal(bad, pair, complete, m::Error::invalid_state, "Two actors cannot own the same work serial.");
    bad = snapshot(4, {}, lot(1, 0), 2);
    bad.cargo.at("P").work_lots.push_back(lot(1, 1));
    refusal(bad, pair, complete, m::Error::invalid_state, "Carried and processing work cannot share an identity.");
    bad = snapshot(2, {0, 2, 0, 0, 0});
    refusal(bad, one, complete, m::Error::invalid_state, "Machine capacity refuses.");
    bad = snapshot(5, {0, 0, 0, 0, 1});
    bad.cargo.at("P").products = 1;
    refusal(bad, pair, complete, m::Error::invalid_state, "Products must use recipe-weighted conservation.");
    refusal(fresh(8), {0, 1, 2}, complete, m::Error::invalid_configuration, "Zero recipe input refuses.");
    refusal(fresh(8), {1, 0, 2}, complete, m::Error::invalid_configuration, "Zero collector capacity refuses.");
    refusal(fresh(8), {1, 1, 0}, complete, m::Error::invalid_configuration, "Zero duration refuses.");
    auto no_processor = complete; no_processor.processor_present = false;
    refusal(fresh(8), one, no_processor, m::Error::invalid_path, "An edge cannot target absent machinery.");
    refusal(snapshot(1, {0, 1, 0, 0, 0}), one, {}, m::Error::invalid_path, "Absent machinery cannot hide stock.");

    for (const auto amount : {-1, 0, 2}) {
        auto output = snapshot(1, {0, 0, 0, 0, 1});
        const auto before = output;
        check(m::retrieve(output, one, complete, "P", amount) == m::Error::unavailable_output, "Nonpositive or unavailable product amounts refuse.");
        check(output == before, "A refused retrieval changes no custody or identity.");
    }
    auto empty = fresh(1);
    const auto before = empty;
    check(m::retrieve(empty, one, complete, "P", 1) == m::Error::unavailable_output && empty == before,
          "Raw stock cannot be retrieved as a product.");
    for (const std::string actor : {"", "not-in-roster"}) {
        auto output = snapshot(1, {0, 0, 0, 0, 1});
        const auto original = output;
        check(m::retrieve(output, one, complete, actor, 1) == m::Error::invalid_actor && output == original,
              "Retrieval never silently creates an actor.");
    }
    auto output = snapshot(1, {0, 0, 0, 0, 2});
    const auto original = output;
    check(m::retrieve(output, one, complete, "P", 1) == m::Error::invalid_state && output == original,
          "Malformed input cannot be repaired or consumed by retrieval.");
}

void integer_boundaries() {
    const auto maximum = std::numeric_limits<m::Quantity>::max();
    const m::Config one{1, 1, 2}, pair{2, 1, 2};
    auto state = fresh(maximum);
    advance(state, one, complete, 1);
    check(state.stock.source == maximum - 1 && state.stock.collector == 1,
          "The largest exact signed raw quantity moves without floating-point conversion.");
    auto bad = fresh(maximum); bad.stock.collector = 1;
    refusal(bad, one, complete, m::Error::quantity_overflow, "Raw sum overflow refuses.");
    bad = snapshot(maximum, {0, 0, 0, 0, 1});
    bad.cargo.at("P").products = maximum;
    refusal(bad, one, complete, m::Error::quantity_overflow, "Product addition overflow refuses.");
    bad = snapshot(maximum, {});
    bad.cargo.at("P").products = maximum / 2 + 1;
    refusal(bad, pair, complete, m::Error::quantity_overflow, "Weighted multiplication overflow refuses.");
    auto large = snapshot(maximum, {0, 0, 0, 0, 1});
    const m::Config large_recipe{maximum, 1, 2};
    check(m::retrieve(large, large_recipe, complete, "P", 1) == m::Error::none &&
          large.cargo.at("P").products == 1 && m::validate(large, large_recipe, complete) == m::Error::none,
          "One product can retain the largest exact recipe weight.");

    auto exhausted = snapshot(2, {0, 0, 0, 2, 0}, {}, maximum);
    refusal(exhausted, pair, complete, m::Error::work_id_overflow, "Serial exhaustion refuses a fresh lot atomically.");
    exhausted = snapshot(4, {0, 0, 0, 2, 0}, lot(1, 1), maximum);
    refusal(exhausted, pair, complete, m::Error::work_id_overflow,
            "A late serial failure rolls back an earlier completion in the same candidate tick.");
    auto last = snapshot(2, {0, 0, 0, 2, 0}, {}, maximum - 1);
    advance(last, pair, complete, 1);
    check(last == snapshot(2, {}, lot(maximum - 1, 2), maximum),
          "The final allocatable serial is preserved exactly with a checked next counter.");
}

void press_work_is_local_and_conserved() {
    const m::Config one{1, 1, 2};
    constexpr m::DropPoint first{8, 1, 0}, first_exit{7, 1, 0};
    constexpr m::DropPoint second{20, 5, 0}, second_exit{19, 5, 0};
    auto state = snapshot(3, {});
    state.dropped_material.emplace(first, m::Cargo{1, 0, {}});
    state.dropped_material.emplace(first_exit, m::Cargo{1, 0, {}});
    state.dropped_material.emplace(second, m::Cargo{1, 0, {}});
    check(m::validate(state, one, {}) == m::Error::none,
          "Two press work points and one blocked output share one conserved material state.");
    check(m::turn_press(state, one, {}, first, first_exit) == m::Error::none &&
          m::turn_press(state, one, {}, second, second_exit) == m::Error::none &&
          state.dropped_material.at(first).work_lots.front().id == 1 &&
          state.dropped_material.at(second).work_lots.front().id == 2,
          "Each physical press starts its own unique lot from its own blank.");
    check(m::turn_press(state, one, {}, first, first_exit) == m::Error::none &&
          m::turn_press(state, one, {}, first, first_exit) == m::Error::none &&
          state.dropped_material.at(first).work_lots.front().remaining_ticks == 0 &&
          state.dropped_material.at(second).work_lots.front().remaining_ticks == 2,
          "A blocked first output retains ready work while the second press remains untouched.");
    const auto stalled = state;
    check(m::turn_press(state, one, {}, first, first_exit) == m::Error::unavailable_output &&
          state == stalled,
          "A further turn cannot overwrite a blocked exit or spend ready work.");
    check(m::pickup_material(state, one, {}, "P", first_exit) == m::Error::none &&
          m::turn_press(state, one, {}, first, first_exit) == m::Error::none &&
          state.dropped_material.at(first_exit).products == 1 &&
          !state.dropped_material.contains(first),
          "Clearing the exit releases exactly the waiting product.");
    check(m::turn_press(state, one, {}, second, second_exit) == m::Error::none &&
          m::turn_press(state, one, {}, second, second_exit) == m::Error::none &&
          state.dropped_material.at(second_exit).products == 1 &&
          !state.dropped_material.contains(second),
          "The second press finishes its distinct WorkLot at its own exit.");
    check(m::pickup_material(state, one, {}, "P", first_exit) == m::Error::none &&
          m::pickup_material(state, one, {}, "Q", second_exit) == m::Error::none &&
          state.cargo.at("P").raw_units == 1 && state.cargo.at("P").products == 1 &&
          state.cargo.at("Q").products == 1 && state.dropped_material.empty() &&
          m::validate(state, one, {}) == m::Error::none,
          "Two actors recover both products and the obstructing raw unit with exact conservation.");
}
}  // namespace

int main() {
    processing();
    topology_and_power();
    refusals();
    integer_boundaries();
    press_work_is_local_and_conserved();
    std::cout << "{\"status\":\"" << (failures == 0 ? "pass" : "fail")
              << "\",\"checks\":" << checks << ",\"failures\":" << failures
              << ",\"evidence\":\"native_logical_material_tests\"}\n";
    return failures == 0 && checks > 0 ? 0 : 1;
}
