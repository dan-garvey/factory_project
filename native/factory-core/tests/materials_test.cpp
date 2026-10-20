#include "factory/materials.hpp"

#include <iostream>
#include <limits>
#include <string>

namespace material = factory::materials;

namespace {
int checks = 0;
int failures = 0;
const material::Path complete{true, true, true, true, true, true};

void check(bool condition, const std::string& label) {
    ++checks;
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << label << '\n';
    }
}

material::State fresh(material::Quantity amount) {
    return {amount, {amount, 0, 0, 0, 0, 0}, {}, 0};
}

void advance(material::State& state, const material::Config& config,
             const material::Path& path, int count) {
    for (int tick = 0; tick < count; ++tick) {
        check(material::step(state, config, path) == material::Error::none,
              "A valid material step succeeds and conserves all input units.");
    }
}

void refusal(material::State state, const material::Config& config,
             const material::Path& path, material::Error expected, const std::string& label) {
    const auto before = state;
    check(material::step(state, config, path) == expected, label);
    check(state == before, "A refused step leaves the entire state unchanged.");
}

void processing() {
    const material::Config config{2, 2, 2};
    auto state = fresh(8);
    advance(state, config, complete, 3);
    check(state.stock == material::Stock{5, 1, 1, 1, 0, 0} && state.remaining == 0,
          "One input cannot begin the two-input recipe, and transport moves one location per tick.");
    advance(state, config, complete, 4);
    check(state.stock == material::Stock{1, 1, 1, 1, 2, 1} && state.remaining == 2,
          "The first product and next held cycle match the full literal seven-tick snapshot.");
    advance(state, config, complete, 5);
    check(state.stock == material::Stock{0, 1, 1, 2, 2, 1} && state.remaining == 0,
          "A blocked output retains the completed two-input held cycle.");
    const auto blocked = state;
    advance(state, config, complete, 5);
    check(state == blocked, "A full path cannot duplicate, destroy or keep extracting feed.");
    for (int tick = 0; tick < 32; ++tick) {
        if (state.stock.output > 0) {
            check(material::retrieve(state, config, complete, "P", 1) == material::Error::none,
                  "A product moves into the named player inventory.");
        }
        advance(state, config, complete, 1);
    }
    if (state.stock.output > 0) {
        check(material::retrieve(state, config, complete, "P", 1) == material::Error::none,
              "The final output can be collected.");
    }
    check(state.stock == material::Stock{} && state.remaining == 0 &&
          state.inventories == std::map<std::string, material::Quantity>{{"P", 4}},
          "Eight raw units end as exactly four products, with every other holder empty.");

    auto one_input = fresh(4);
    const material::Config single{1, 1, 2};
    for (int tick = 0; tick < 32; ++tick) {
        if (one_input.stock.output > 0) {
            check(material::retrieve(one_input, single, complete, "Q", 1) == material::Error::none,
                  "The same rules support a separately declared one-input fixture.");
        }
        advance(one_input, single, complete, 1);
    }
    check(one_input.stock == material::Stock{} && one_input.inventories.at("Q") == 4,
          "Four one-input products are conserved without changing the rule path.");

    auto pressured = fresh(20);
    advance(pressured, config, complete, 12);
    check(pressured.stock == material::Stock{11, 2, 1, 2, 2, 1} && pressured.remaining == 0,
          "Backpressure leaves the exact remaining source and all five physical holders.");
    const auto pressure_limit = pressured;
    advance(pressured, config, complete, 4);
    check(pressured == pressure_limit, "A full path retains source stock instead of discarding it.");
}

void topology_and_power() {
    const material::Config config{1, 1, 2};
    auto disconnected = fresh(5);
    auto path = complete;
    path.collector_to_belt = false;
    path.belt_to_processor = false;
    advance(disconnected, config, path, 8);
    check(disconnected.stock == material::Stock{4, 1, 0, 0, 0, 0},
          "Disconnected machinery does not route stock or manufacture products.");
    auto absent = fresh(5);
    advance(absent, config, {}, 8);
    check(absent == fresh(5), "Without a collector no feed is extracted.");

    material::State ready{4, {0, 0, 0, 0, 2, 1}, {}, 0};
    const material::Config pair{2, 2, 2};
    auto stopped = complete;
    stopped.powered = false;
    material::State partial{2, {0, 0, 0, 0, 2, 0}, {}, 1};
    const auto partial_before = partial;
    advance(partial, pair, stopped, 3);
    check(partial == partial_before, "Stopped power also preserves distinct positive remaining work.");
    advance(partial, pair, complete, 1);
    check(partial.stock == material::Stock{0, 0, 0, 0, 0, 1} && partial.remaining == 0,
          "A single remaining tick completes once after power resumes in this logical fixture.");
    const auto before = ready;
    advance(ready, pair, stopped, 5);
    check(ready == before, "Stopped power preserves literal blocked ready work.");
    advance(ready, pair, complete, 5);
    check(ready == before, "Blocked ready work also stays held while the output is full.");
    check(material::retrieve(ready, pair, complete, "Q", 1) == material::Error::none,
          "Q can collect the original product.");
    advance(ready, pair, complete, 1);
    check(ready.stock == material::Stock{0, 0, 0, 0, 0, 1} && ready.remaining == 0,
          "Released output receives the original completed held work exactly once.");
    check(material::retrieve(ready, pair, complete, "P", 1) == material::Error::none,
          "P can collect the second product.");
    check(ready.inventories == std::map<std::string, material::Quantity>{{"P", 1}, {"Q", 1}},
          "Individual custody retains both named recipients.");
}

void refusals() {
    const material::Config config{1, 1, 2};
    auto invalid = fresh(8);
    invalid.stock.source = -1;
    refusal(invalid, config, complete, material::Error::invalid_state, "Negative raw stock is refused.");
    invalid = fresh(8);
    invalid.stock.source = 7;
    refusal(invalid, config, complete, material::Error::invalid_state, "Missing material is refused.");
    invalid = fresh(8);
    invalid.stock.source = 9;
    refusal(invalid, config, complete, material::Error::invalid_state, "Duplicated material is refused.");
    invalid = fresh(8);
    invalid.inventories["P"] = -1;
    refusal(invalid, config, complete, material::Error::invalid_state, "Negative product custody is refused.");
    invalid = fresh(8);
    invalid.inventories[""] = 0;
    refusal(invalid, config, complete, material::Error::invalid_state, "An empty inventory owner is refused.");
    invalid = fresh(8);
    invalid.remaining = 1;
    refusal(invalid, config, complete, material::Error::invalid_state, "A timer without held work is refused.");
    invalid = {2, {0, 0, 0, 0, 2, 0}, {}, 0};
    refusal(invalid, config, complete, material::Error::invalid_state, "A held batch with the wrong recipe size is refused.");
    invalid = {2, {0, 2, 0, 0, 0, 0}, {}, 0};
    refusal(invalid, config, complete, material::Error::invalid_state, "Holder capacity is enforced.");
    invalid = {5, {0, 0, 0, 0, 0, 1}, {{"P", 1}}, 0};
    refusal(invalid, {2, 2, 2}, complete, material::Error::invalid_state,
            "Products use recipe-weighted units instead of their unweighted item count.");
    invalid = {1, {0, 0, 0, 0, 1, 0}, {}, 3};
    refusal(invalid, config, complete, material::Error::invalid_state, "A timer beyond its declared cycle is refused.");
    refusal(fresh(8), {0, 1, 2}, complete, material::Error::invalid_configuration, "A zero-input recipe is refused.");
    refusal(fresh(8), {1, 0, 2}, complete, material::Error::invalid_configuration, "Zero collector capacity is refused.");
    refusal(fresh(8), {1, 1, 0}, complete, material::Error::invalid_configuration, "A zero-length cycle is refused.");
    auto invalid_path = complete;
    invalid_path.processor_present = false;
    refusal(fresh(8), config, invalid_path, material::Error::invalid_path,
            "An edge cannot connect an absent processor.");
    invalid_path = {};
    invalid = {1, {0, 1, 0, 0, 0, 0}, {}, 0};
    refusal(invalid, config, invalid_path, material::Error::invalid_path,
            "An absent collector cannot hide material.");

    for (const auto amount : {-1, 0, 2}) {
        material::State output{1, {0, 0, 0, 0, 0, 1}, {}, 0};
        const auto before = output;
        check(material::retrieve(output, config, complete, "P", amount) == material::Error::unavailable_output,
              "Unavailable or nonpositive retrieval is refused.");
        check(output == before, "Refused retrieval preserves every field, including inventory keys.");
    }
    auto empty = fresh(1);
    const auto before = empty;
    check(material::retrieve(empty, config, complete, "P", 1) == material::Error::unavailable_output,
          "Raw source stock cannot be retrieved as a product.");
    check(empty == before, "An empty-output refusal does not convert or move raw material.");
    material::State output{1, {0, 0, 0, 0, 0, 1}, {}, 0};
    const auto original = output;
    check(material::retrieve(output, config, complete, "", 1) == material::Error::invalid_actor,
          "An empty retrieval recipient is refused.");
    check(output == original, "Invalid identity leaves output and inventories intact.");
    output.stock.output = 2;
    const auto invalid_output = output;
    check(material::retrieve(output, config, complete, "P", 1) == material::Error::invalid_state,
          "Retrieval also rejects malformed input before any debit.");
    check(output == invalid_output, "Malformed input cannot be repaired or consumed by retrieval.");
}

void integer_boundaries() {
    const auto maximum = std::numeric_limits<material::Quantity>::max();
    const material::Config config{1, 1, 2};
    auto state = fresh(maximum);
    advance(state, config, complete, 1);
    check(state.stock.source == maximum - 1 && state.stock.collector == 1,
          "The exact largest signed quantity moves without overflow or floating-point conversion.");
    auto invalid = fresh(maximum);
    invalid.stock.collector = 1;
    refusal(invalid, config, complete, material::Error::quantity_overflow, "Raw summation overflow is refused.");
    invalid = {maximum, {0, 0, 0, 0, 0, 1}, {{"P", maximum}}, 0};
    refusal(invalid, config, complete, material::Error::quantity_overflow, "Product summation overflow is refused.");
    invalid = {maximum, {}, {{"P", maximum / 2 + 1}}, 0};
    refusal(invalid, {2, 1, 2}, complete, material::Error::quantity_overflow,
            "Recipe-weighted product overflow is refused before multiplication.");
    material::State large_product{maximum, {0, 0, 0, 0, 0, 1}, {}, 0};
    const material::Config large_recipe{maximum, 1, 2};
    check(material::retrieve(large_product, large_recipe, complete, "P", 1) == material::Error::none,
          "One product can represent the exact largest recipe quantity.");
    check(large_product.inventories.at("P") == 1 && large_product.stock.output == 0 &&
          material::validate(large_product, large_recipe, complete) == material::Error::none,
          "Recipe-weighted custody remains exact at the integer boundary.");
}
}  // namespace

int main() {
    processing();
    topology_and_power();
    refusals();
    integer_boundaries();
    std::cout << "{\"status\":\"" << (failures == 0 ? "pass" : "fail")
              << "\",\"checks\":" << checks << ",\"failures\":" << failures
              << ",\"evidence\":\"native_logical_material_tests\"}\n";
    return failures == 0 && checks > 0 ? 0 : 1;
}
