#include "factory/recovery.hpp"
#include "factory/transactions.hpp"

#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

namespace {
namespace m = factory::materials;
namespace a = factory::authority;
namespace w = factory::world;
using V = factory::values::Value;
using I = a::Integer;
using O = a::Object;

int checks{};
constexpr m::Config config{2, 2, 4};
constexpr m::Path broken_line{true, false, false, false, false, false};
constexpr m::Path complete_line{true, true, true, true, true, true};

void require(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

// This invented domain has one canonical material State and fixed resolved
// fixture targets. It is not the game World, a Session binder or a second model.
struct Domain {
    m::State material;
    bool operator==(const Domain&) const = default;
};
using Owner = w::TransactionOwner<Domain>;

Owner::Validator validator(m::Path path) {
    return [path](const auto& candidate) {
        const auto& state = candidate.state.material;
        return state.initial_units == 16 && state.cargo.size() == 2 &&
               state.cargo.contains("P") && state.cargo.contains("Q") &&
               m::validate(state, config, path) == m::Error::none;
    };
}

O intent(const char* actor, const char* request, const char* action) {
    return {{"context", V("recovery-fixture")}, {"client", V(actor)},
            {"request", V(request)}, {"action", V(action)},
            {"target", V("fixture-machine")}, {"generation", V(I{1})}};
}

bool same(const O& left, const O& right) {
    return !factory::values::typed_difference(V(left), V(right));
}

void unchanged(const Owner& owner, const Owner::Snapshot& before) {
    const auto after = owner.snapshot();
    require(after.state == before.state && after.revision == before.revision &&
            after.history.context == before.history.context &&
            after.history.order == before.history.order &&
            after.history.records.size() == before.history.records.size(),
            "The complete material State, revision and history envelope stay unchanged.");
    for (std::size_t index = 0; index < before.history.records.size(); ++index) {
        require(same(after.history.records[index].intent, before.history.records[index].intent) &&
                same(after.history.records[index].result, before.history.records[index].result),
                "Every historical typed intent and outcome remains exact.");
    }
}

void integer(const O& object, const char* key, I expected) {
    require(std::get<I>(object.at(key).storage()) == expected,
            "The independently specified receipt integer and its type must match.");
}

Owner::Decision decision(const Owner::Snapshot& current, m::TransferPlan plan) {
    if (const auto* refusal = std::get_if<m::TransferRefusal>(&plan)) {
        return {std::nullopt,
                {false, m::transfer_error_name(refusal->reason), "fixture-machine", {}}};
    }
    auto& transfer = std::get<m::PreparedTransfer>(plan);
    auto candidate = current.state;
    candidate.material = std::move(transfer.candidate);
    O facts{{"raw_moved", V(transfer.facts.moved.raw_units)},
            {"products_moved", V(transfer.facts.moved.products)},
            {"work_count", V(static_cast<I>(transfer.facts.moved.work_lots.size()))}};
    if (!transfer.facts.moved.work_lots.empty()) {
        const auto& lot = transfer.facts.moved.work_lots.front();
        facts.emplace("work_id", V(lot.id));
        facts.emplace("remaining_ticks", V(lot.remaining_ticks));
    }
    return {std::move(candidate), {true, "transferred", "fixture-machine", std::move(facts)}};
}

// These fixed actor/target facts stand in for already admitted World inputs.
// No test claims to authenticate a caller or validate a native target lifetime.
auto recover(const char* actor, m::ResolvedTarget target, int& plans) {
    return [actor = std::string(actor), target = std::move(target), &plans]
           (const auto& current, const O&) {
        ++plans;
        return decision(current, m::prepare_recovery(current.state.material, config,
                                                     {actor, target}));
    };
}

auto insert(const char* actor, m::ResolvedTarget target, m::Insertion contents, int& plans) {
    return [actor = std::string(actor), target = std::move(target), contents, &plans]
           (const auto& current, const O&) {
        ++plans;
        return decision(current, m::prepare_insertion(current.state.material, config,
                                                      {actor, target, contents}));
    };
}

void raw_recovery_and_historical_outcomes() {
    Domain seed;
    seed.material.initial_units = 16;
    seed.material.stock.source = 14;
    seed.material.stock.collector = 2;
    seed.material.cargo = {{"P", {}}, {"Q", {}}};
    auto owner = Owner::create_new("recovery-fixture", seed, validator(broken_line));
    require(owner != nullptr, "The incomplete-line seed is valid without a processor.");
    const m::ResolvedTarget collector{{"fixture-machine", 1}, m::Holder::collector,
                                     broken_line, std::nullopt};
    int plans{};
    const auto first_intent = intent("P", "p-epoch:1", "recover");
    const auto first = owner->apply(first_intent, recover("P", collector, plans));
    require(first.completed() && owner->snapshot().state.material.stock.source == 14 &&
            owner->snapshot().state.material.stock.collector == 0 &&
            owner->snapshot().state.material.cargo.at("P").raw_units == 2 &&
            owner->snapshot().state.material.cargo.at("P").products == 0,
            "Bad-route recovery moves two raw units once without a product or source refill.");
    integer(*first.result, "raw_moved", 2);
    integer(*first.result, "revision", 1);

    const auto refused_intent = intent("P", "p-epoch:2", "recover");
    const auto refused = owner->apply(refused_intent, recover("P", collector, plans));
    require(refused.completed() && !std::get<bool>(refused.result->at("accepted").storage()) &&
            owner->snapshot().revision == 1 && owner->snapshot().history.order == 2,
            "A fresh empty-machine refusal caches history without changing material revision.");

    const auto inserted = owner->apply(intent("P", "p-epoch:3", "insert"),
        insert("P", collector, m::RawInsertion{1}, plans));
    require(inserted.completed() && owner->snapshot().state.material.stock.collector == 1 &&
            owner->snapshot().state.material.cargo.at("P").raw_units == 1,
            "A later distinct insertion changes the conditions of the old refusal.");
    const auto before_refused_retry = owner->snapshot();
    const auto refused_retry = owner->apply(refused_intent, recover("P", collector, plans));
    require(refused_retry.completed() && plans == 3 &&
            !std::get<bool>(refused_retry.result->at("accepted").storage()) &&
            std::get<bool>(refused_retry.result->at("duplicate").storage()) &&
            refused_retry.current_revision == 2,
            "A cached refusal is not re-evaluated against now-available stock.");
    integer(*refused_retry.result, "revision", 1);
    integer(*refused_retry.result, "order", 2);
    unchanged(*owner, before_refused_retry);

    const auto other_actor = owner->apply(intent("Q", "q-epoch:1", "recover"),
                                           recover("Q", collector, plans));
    const auto after_q = owner->snapshot();
    require(other_actor.completed() && plans == 4 && after_q.revision == 3 &&
            after_q.state.material.cargo.at("P").raw_units == 1 &&
            after_q.state.material.cargo.at("Q").raw_units == 1 &&
            after_q.state.material.stock.source == 14,
            "A later actor takes only current machine stock, preserving individual custody.");

    const auto replay = owner->apply(first_intent, recover("P", collector, plans));
    require(replay.completed() && plans == 4 && replay.current_revision == 3,
            "An accepted historical transfer bypasses the real planner after later edits.");
    auto expected = *first.result;
    expected.at("duplicate") = V(true);
    require(same(*replay.result, expected),
            "The whole original transfer receipt changes only its delivery duplicate flag.");
    unchanged(*owner, after_q);

    auto changed_type = first_intent;
    changed_type.at("generation") = V(1.0);
    const auto reuse = owner->apply(changed_type, recover("P", collector, plans));
    require(reuse.history_error == a::Error::request_reuse && !reuse.result && plans == 4,
            "A float generation cannot reuse an integer-valued original intent.");
    unchanged(*owner, after_q);
    require(seed.material.stock.collector == 2 && seed.material.cargo.at("P").raw_units == 0,
            "The owner and every transaction leave the external seed untouched.");
}

void whole_work_and_atomic_validation() {
    Domain seed;
    seed.material.initial_units = 16;
    seed.material.stock = {4, 1, 1, 2, 1};
    seed.material.processing = m::WorkLot{7, {2, 4}, 3};
    seed.material.next_work_id = 8;
    seed.material.cargo = {{"P", {1, 1, {}}}, {"Q", {1, 0, {}}}};
    auto owner = Owner::create_new("recovery-fixture", seed, validator(complete_line));
    require(owner != nullptr, "The positive partial-work seed conserves sixteen raw-equivalent units.");
    const m::ResolvedTarget processor{{"fixture-machine", 1}, m::Holder::processor,
                                     complete_line, m::RecipeSignature{2, 4}};
    int plans{};
    const auto original = intent("P", "work-p:1", "recover");
    const auto recovered = owner->apply(original, recover("P", processor, plans));
    const auto carried = owner->snapshot();
    require(recovered.completed() && !carried.state.material.processing &&
            carried.state.material.stock.input == 0 && carried.state.material.stock.output == 0 &&
            carried.state.material.cargo.at("P") == m::Cargo{3, 2, {{7, {2, 4}, 3}}} &&
            carried.state.material.cargo.at("Q") == seed.material.cargo.at("Q") &&
            carried.state.material.next_work_id == 8,
            "One committed recovery preserves whole work identity, recipe, progress and other custody.");
    integer(*recovered.result, "work_id", 7);
    integer(*recovered.result, "remaining_ticks", 3);
    integer(*recovered.result, "products_moved", 1);

    const auto restored = owner->apply(intent("P", "work-p:2", "insert"),
        insert("P", processor, m::WorkInsertion{7}, plans));
    const auto before_retry = owner->snapshot();
    require(restored.completed() && before_retry.state.material.processing == seed.material.processing &&
            before_retry.state.material.cargo.at("P") == m::Cargo{3, 2, {}} &&
            before_retry.state.material.stock.source == 4 && before_retry.revision == 2,
            "Reinsertion uses the same lot without allocating identity or restarting work.");
    const auto replay = owner->apply(original, recover("P", processor, plans));
    require(replay.completed() && plans == 2 && replay.current_revision == 2,
            "Retry cannot evacuate the reinserted lot a second time.");
    integer(*replay.result, "revision", 1);
    integer(*replay.result, "work_id", 7);
    unchanged(*owner, before_retry);

    const auto invalid = owner->apply(intent("P", "work-p:3", "recover"),
        [&](const auto& current, const O&) {
            auto proposal = decision(current, m::prepare_recovery(current.state.material, config,
                                                                  {"P", processor}));
            require(proposal.candidate.has_value(), "The genuine pure recovery prepares first.");
            ++proposal.candidate->material.stock.source;
            return proposal;
        });
    require(invalid.error == w::TransactionError::invalid_candidate && !invalid.result,
            "The real weighted validator rejects an otherwise prepared nonconserving commit.");
    unchanged(*owner, before_retry);
    require(owner->snapshot().history.order == 2,
            "Rejected candidate preparation adds no cached outcome or hidden order.");
}
}  // namespace

int main() {
    try {
        raw_recovery_and_historical_outcomes();
        whole_work_and_atomic_validation();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_recovery_transactions\","
                     "\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "recovery_transaction_test: " << error.what() << '\n';
        return 1;
    }
}
