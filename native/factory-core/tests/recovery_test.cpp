#include "factory/recovery.hpp"

#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>

namespace m = factory::materials;
namespace {
int checks = 0;
const m::Config config{2, 2, 4};
const m::Path complete{true, true, true, true, true, true};

void require(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
m::WorkLot lot(m::WorkId id, m::Quantity remaining) { return {id, {2, 4}, remaining}; }
m::State snapshot(m::Quantity initial, m::Stock stock = {},
                  std::optional<m::WorkLot> work = {}, m::WorkId next = 1) {
    return {initial, stock, {{"P", {}}, {"Q", {}}}, work, next};
}
m::ResolvedTarget target(m::Holder holder, m::Path path = complete) {
    const char* id = holder == m::Holder::collector ? "collector-1"
        : holder == m::Holder::belt ? "belt-1" : holder == m::Holder::processor ? "processor-1" : "source";
    return {{id, 1}, holder, path,
        holder == m::Holder::processor ? std::optional<m::RecipeSignature>{m::RecipeSignature{2, 4}} : std::nullopt};
}
const m::PreparedTransfer& planned(const m::TransferPlan& value) {
    const auto* result = std::get_if<m::PreparedTransfer>(&value);
    require(result != nullptr, "The transfer must produce a complete candidate.");
    return *result;
}
void refused(const m::TransferPlan& plan, m::TransferError reason) {
    const auto* result = std::get_if<m::TransferRefusal>(&plan);
    require(result && result->reason == reason, "The transfer must return the expected refusal and no candidate.");
}
void recovery_refusal(m::State& state, m::RecoverySelection selection, m::TransferError reason) {
    const auto before = state;
    refused(m::prepare_recovery(state, config, selection), reason);
    require(state == before, "Refused recovery must preserve complete material state.");
}
void insertion_refusal(m::State& state, m::InsertionSelection selection, m::TransferError reason) {
    const auto before = state;
    refused(m::prepare_insertion(state, config, selection), reason);
    require(state == before, "Refused insertion must preserve complete material state.");
}
void advance(m::State& state, int ticks) {
    for (int tick = 0; tick < ticks; ++tick)
        require(m::step(state, config, complete) == m::Error::none, "A literal fixture tick must succeed.");
}

void raw_bad_route() {
    // Invented pure fixture facts: no belt or processor exists. Power stays on.
    const m::Path incomplete{true, false, false, false, false, true};
    auto original = snapshot(16, {14, 2, 0, 0, 0});
    const auto before = original;
    const auto collector = target(m::Holder::collector, incomplete);
    const auto plan = m::prepare_recovery(original, config, {"P", collector});
    const auto& result = planned(plan);
    auto expected = snapshot(16, {14, 0, 0, 0, 0});
    expected.cargo.at("P").raw_units = 2;
    require(original == before && result.candidate == expected,
            "Bad-route recovery moves two raw units without a press, reset, source refill or input mutation.");
    require(result.facts.moved == m::Cargo{2, 0, {}} &&
            result.facts.actor == "P" && result.facts.affected_entity == m::EntityRef{"collector-1", 1} &&
            result.facts.holder == m::Holder::collector &&
            result.facts.direction == m::TransferDirection::machine_to_actor,
            "The receipt names the exact typed move, actor and stable target.");
    recovery_refusal(expected, {"Q", collector}, m::TransferError::nothing_to_recover);
    insertion_refusal(expected, {"P", target(m::Holder::source, incomplete), m::RawInsertion{1}},
                      m::TransferError::unsupported_source);

    // World supplies these facts after a separate rebuild; this plan creates no belt.
    const m::Path rebuilt{true, true, false, true, false, true};
    const auto insert = m::prepare_insertion(expected, config,
        {"P", target(m::Holder::belt, rebuilt), m::RawInsertion{1}});
    auto inserted = planned(insert).candidate;
    auto wanted = snapshot(16, {14, 0, 1, 0, 0});
    wanted.cargo.at("P").raw_units = 1;
    require(inserted == wanted && planned(insert).facts.moved == m::Cargo{1, 0, {}},
            "One explicitly selected carried raw unit returns to an eligible holder, never to the seam.");
    const auto returned = m::prepare_recovery(inserted, config, {"Q", target(m::Holder::belt, rebuilt)});
    wanted.stock.belt = 0;
    wanted.cargo.at("Q").raw_units = 1;
    require(planned(returned).candidate == wanted, "P and Q raw custody remains separate.");
}

void combined_processor_contents() {
    auto original = snapshot(16, {4, 1, 1, 2, 1}, lot(7, 3), 8);
    original.cargo.at("P") = {1, 1, {}};
    original.cargo.at("Q") = {1, 0, {}};
    const auto before = original;
    require(m::validate(original, config, complete) == m::Error::none, "The combined literal fixture is valid.");
    const auto plan = m::prepare_recovery(original, config, {"P", target(m::Holder::processor)});
    auto expected = snapshot(16, {4, 1, 1, 0, 0}, {}, 8);
    expected.cargo.at("P") = {3, 2, {lot(7, 3)}};
    expected.cargo.at("Q") = {1, 0, {}};
    require(planned(plan).candidate == expected && original == before,
            "Processor recovery atomically moves input raw, one whole partial lot and one product.");
    require(planned(plan).facts.moved == m::Cargo{2, 1, {lot(7, 3)}},
            "The receipt does not flatten raw, work or products into one plate count.");
    require(expected.stock.source == 4 && expected.stock.collector == 1 && expected.stock.belt == 1 &&
            expected.next_work_id == 8, "Unselected holders and the allocation counter remain unchanged.");
}

void partial_progress() {
    auto original = snapshot(2, {}, lot(7, 3), 8);
    const auto plan = m::prepare_recovery(original, config, {"P", target(m::Holder::processor)});
    auto carried = planned(plan).candidate;
    auto expected = snapshot(2, {}, {}, 8);
    expected.cargo.at("P").work_lots = {lot(7, 3)};
    require(carried == expected, "Positive partial-cycle work retains its original identity and three ticks.");
    advance(carried, 12);
    require(carried == expected, "Powered ticks cannot advance or reset a carried work lot.");
    const auto insertion = m::prepare_insertion(carried, config,
        {"P", target(m::Holder::processor), m::WorkInsertion{7}});
    auto resumed = planned(insertion).candidate;
    require(resumed == original && planned(insertion).facts.moved == m::Cargo{0, 0, {lot(7, 3)}},
            "Reinsertion restores the original complete state without allocating or restarting work.");
    advance(resumed, 1);
    require(resumed == snapshot(2, {}, lot(7, 2), 8), "The first resumed tick advances only the original lot.");
    advance(resumed, 2);
    require(resumed == snapshot(2, {0, 0, 0, 0, 1}, {}, 8), "Exactly the saved remaining ticks finish the lot once.");
    require(m::retrieve(resumed, config, complete, "Q", 1) == m::Error::none, "Q can receive the completed product.");
    expected = snapshot(2, {}, {}, 8);
    expected.cargo.at("Q").products = 1;
    require(resumed == expected, "Recovery and continuation conserve exact per-player final custody.");
}

void blocked_ready() {
    auto original = snapshot(4, {0, 0, 0, 0, 1}, lot(9, 0), 10);
    const auto plan = m::prepare_recovery(original, config, {"P", target(m::Holder::processor)});
    auto expected = snapshot(4, {}, {}, 10);
    expected.cargo.at("P") = {0, 1, {lot(9, 0)}};
    require(planned(plan).candidate == expected, "Zero remaining work is recovered as a whole ready lot, not lost.");

    // A free processing slot may be reoccupied while its separate output is full.
    auto carried = snapshot(4, {0, 0, 0, 0, 1}, {}, 10);
    carried.cargo.at("P").work_lots = {lot(9, 0)};
    const auto insert = m::prepare_insertion(carried, config,
        {"P", target(m::Holder::processor), m::WorkInsertion{9}});
    auto resumed = planned(insert).candidate;
    require(resumed == original, "A ready lot can return without clearing or replacing the existing output.");
    advance(resumed, 4);
    require(resumed == original, "A full output still blocks the same ready lot after reinsertion.");
    require(m::retrieve(resumed, config, complete, "Q", 1) == m::Error::none, "Q clears only the existing output.");
    require(resumed.processing == lot(9, 0), "Retrieval does not consume the ready lot.");
    advance(resumed, 1);
    require(!resumed.processing && resumed.stock.output == 1 && resumed.next_work_id == 10,
            "The original ready lot releases once without a replacement identity.");
    require(m::retrieve(resumed, config, complete, "P", 1) == m::Error::none, "P receives the second product.");
    expected = snapshot(4, {}, {}, 10);
    expected.cargo.at("P").products = expected.cargo.at("Q").products = 1;
    require(resumed == expected, "The two products remain separately owned after ready-work continuation.");
}

void refusal_controls() {
    auto state = snapshot(2);
    state.cargo.at("P").raw_units = 2;
    insertion_refusal(state, {"P", target(m::Holder::belt), m::RawInsertion{2}}, m::TransferError::insufficient_capacity);
    for (const auto amount : {-1, 0})
        insertion_refusal(state, {"P", target(m::Holder::collector), m::RawInsertion{amount}}, m::TransferError::invalid_amount);
    insertion_refusal(state, {"P", target(m::Holder::collector), m::RawInsertion{3}}, m::TransferError::unavailable_cargo);
    insertion_refusal(state, {"Q", target(m::Holder::collector), m::RawInsertion{1}}, m::TransferError::unavailable_cargo);
    insertion_refusal(state, {"not-in-roster", target(m::Holder::collector), m::RawInsertion{1}}, m::TransferError::unknown_actor);
    recovery_refusal(state, {"not-in-roster", target(m::Holder::collector)}, m::TransferError::unknown_actor);
    auto invalid = target(m::Holder::collector);
    invalid.entity.id.clear();
    insertion_refusal(state, {"P", invalid, m::RawInsertion{1}}, m::TransferError::invalid_target);
    invalid = target(m::Holder::collector); invalid.entity.generation = 0;
    insertion_refusal(state, {"P", invalid, m::RawInsertion{1}}, m::TransferError::invalid_target);
    invalid = target(m::Holder::collector, {});
    insertion_refusal(state, {"P", invalid, m::RawInsertion{1}}, m::TransferError::invalid_target);

    auto input = snapshot(3, {0, 0, 0, 1, 0});
    input.cargo.at("P").raw_units = 2;
    insertion_refusal(input, {"P", target(m::Holder::processor), m::RawInsertion{2}}, m::TransferError::insufficient_capacity);
    const auto insert = m::prepare_insertion(input, config, {"P", target(m::Holder::processor), m::RawInsertion{1}});
    auto expected = snapshot(3, {0, 0, 0, 2, 0});
    expected.cargo.at("P").raw_units = 1;
    require(planned(insert).candidate == expected, "Raw input capacity is exact and does not start a cycle.");

    auto work = snapshot(2, {}, {}, 4);
    work.cargo.at("P").work_lots = {lot(3, 2)};
    insertion_refusal(work, {"Q", target(m::Holder::processor), m::WorkInsertion{3}}, m::TransferError::unavailable_cargo);
    insertion_refusal(work, {"P", target(m::Holder::processor), m::WorkInsertion{99}}, m::TransferError::unavailable_cargo);
    insertion_refusal(work, {"P", target(m::Holder::collector), m::WorkInsertion{3}}, m::TransferError::invalid_target);
    auto incompatible = target(m::Holder::processor);
    incompatible.accepts_work = m::RecipeSignature{2, 5};
    insertion_refusal(work, {"P", incompatible, m::WorkInsertion{3}}, m::TransferError::incompatible_work_recipe);
    incompatible.accepts_work.reset();
    insertion_refusal(work, {"P", incompatible, m::WorkInsertion{3}}, m::TransferError::incompatible_work_recipe);
    work.initial_units = 4; work.processing = lot(2, 0);
    insertion_refusal(work, {"P", target(m::Holder::processor), m::WorkInsertion{3}}, m::TransferError::occupied_target);
    work.processing = lot(3, 2);
    insertion_refusal(work, {"P", target(m::Holder::processor), m::WorkInsertion{3}}, m::TransferError::invalid_material_state);

    auto products = snapshot(2);
    products.cargo.at("P").products = 1;
    insertion_refusal(products, {"P", target(m::Holder::collector), m::RawInsertion{1}}, m::TransferError::unavailable_cargo);
    recovery_refusal(products, {"P", target(m::Holder::source)}, m::TransferError::unsupported_source);
    recovery_refusal(products, {"P", target(m::Holder::processor)}, m::TransferError::nothing_to_recover);
    auto overflow = snapshot(std::numeric_limits<m::Quantity>::max(),
                             {std::numeric_limits<m::Quantity>::max(), 0, 0, 0, 0});
    overflow.cargo.at("P").raw_units = 1;
    recovery_refusal(overflow, {"P", target(m::Holder::collector)}, m::TransferError::quantity_overflow);
}

void exhausted_serial_transfer() {
    const auto maximum = std::numeric_limits<m::WorkId>::max();
    const auto original = snapshot(2, {}, lot(maximum - 1, 2), maximum);
    const auto recovered = m::prepare_recovery(original, config, {"P", target(m::Holder::processor)});
    const auto& carried = planned(recovered).candidate;
    require(carried.next_work_id == maximum && carried.cargo.at("P").work_lots == std::vector<m::WorkLot>{lot(maximum - 1, 2)},
            "Recovery does not allocate even when the work counter is exhausted.");
    const auto inserted = m::prepare_insertion(carried, config,
        {"P", target(m::Holder::processor), m::WorkInsertion{maximum - 1}});
    require(planned(inserted).candidate == original, "Reinsertion preserves the last valid work serial exactly.");
}

void selected_whole_lot_and_large_raw() {
    auto carried = snapshot(6, {}, {}, 9);
    carried.cargo.at("P").work_lots = {lot(2, 1), lot(7, 3), lot(8, 0)};
    const auto insertion = m::prepare_insertion(carried, config,
        {"P", target(m::Holder::processor), m::WorkInsertion{7}});
    auto resumed = planned(insertion).candidate;
    auto expected = snapshot(6, {}, lot(7, 3), 9);
    expected.cargo.at("P").work_lots = {lot(2, 1), lot(8, 0)};
    require(resumed == expected, "Selecting a middle work serial preserves both other whole lots and their order.");
    advance(resumed, 1);
    expected.processing = lot(7, 2);
    require(resumed == expected, "Only the inserted lot advances; other carried work keeps its own progress.");

    const auto maximum = std::numeric_limits<m::Quantity>::max();
    const m::Config large{2, maximum, 4};
    const auto source = snapshot(maximum, {0, maximum, 0, 0, 0});
    const auto plan = m::prepare_recovery(source, large, {"P", target(m::Holder::collector)});
    auto wanted = snapshot(maximum);
    wanted.cargo.at("P").raw_units = maximum;
    require(planned(plan).candidate == wanted && planned(plan).facts.moved.raw_units == maximum,
            "Recovery preserves the exact largest raw quantity without floating-point conversion.");
}
}  // namespace

int main() {
    try {
        raw_bad_route();
        combined_processor_contents();
        partial_progress();
        blocked_ready();
        refusal_controls();
        exhausted_serial_transfer();
        selected_whole_lot_and_large_raw();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks
                  << ",\"evidence\":\"native_logical_recovery_tests\",\"live_worlds\":0}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Recovery fixture failed: " << error.what() << '\n';
        return 1;
    }
}
