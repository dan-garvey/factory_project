#include "factory/transactions.hpp"

#include <iostream>
#include <new>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace a = factory::authority;
namespace w = factory::world;
using V = factory::values::Value;
using I = a::Integer;
using O = a::Object;

namespace {
int checks{};
void require(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

// An invented marker domain, not another material model or gameplay fixture.
struct Marker {
    I value{};
    std::vector<std::string> labels;
    bool operator==(const Marker&) const = default;
};
using Owner = w::TransactionOwner<Marker>;

O intent(const char* request) {
    return {{"context", V("world-1")}, {"client", V("P")},
            {"request", V(request)}, {"action", V("mark")}, {"slot", V(I{0})}};
}

bool same(const O& left, const O& right) {
    return !factory::values::typed_difference(V(left), V(right));
}

bool same_history(const a::History& left, const a::History& right) {
    if (left.context != right.context || left.order != right.order ||
        left.records.size() != right.records.size()) return false;
    for (std::size_t n = 0; n < left.records.size(); ++n)
        if (!same(left.records[n].intent, right.records[n].intent) ||
            !same(left.records[n].result, right.records[n].result)) return false;
    return true;
}

void unchanged(const Owner& owner, const Owner::Snapshot& before) {
    const auto after = owner.snapshot();
    require(after.state == before.state && after.revision == before.revision &&
            same_history(after.history, before.history),
            "Failure preserves the complete original State, history and revision.");
}

Owner::Decision accepted(I marker, const char* label = "committed") {
    return {Marker{marker, {label}},
            {true, "marked", "marker-1", {{"original_fact", V(I{71})}}}};
}

bool valid(const Owner::Snapshot& candidate) {
    return candidate.state.value >= 0 && candidate.state.value <= 10;
}

void creation_and_detached_reads() {
    Marker seed{0, {"seed"}};
    require(!Owner::create_new("world-1", seed, {}),
            "Fresh creation requires a complete validator.");
    require(!Owner::create_new("", seed, valid),
            "An invalid context does not create an owner.");
    require(!Owner::create_new("world-1", Marker{-1, {}}, valid),
            "An invalid initial domain State does not create an owner.");
    auto owner = Owner::create_new("world-1", seed, valid);
    require(owner != nullptr, "A valid fresh State creates an owner.");
    seed.labels[0] = "external change";
    auto copy = owner->snapshot();
    require(copy.revision == 0 && copy.history.order == 0 &&
            copy.history.records.empty() && copy.state.labels[0] == "seed",
            "Fresh state and empty history are independently owned.");
    copy.state.value = 9;
    copy.state.labels.clear();
    copy.history.context = "changed copy";
    require(owner->snapshot().state == Marker{0, {"seed"}} &&
            owner->snapshot().history.context == "world-1",
            "Mutating an exported snapshot cannot mutate the owner.");

    bool caught{};
    try {
        (void)Owner::create_new("world-1", seed, [](const auto&) -> bool {
            throw std::runtime_error("invented creation failure");
        });
    } catch (const std::runtime_error&) { caught = true; }
    require(caught && seed.labels[0] == "external change",
            "Initial validator exceptions propagate without rewriting caller state.");
}

void commit_refusal_and_historical_retry() {
    int validator_calls{};
    auto owner = Owner::create_new("world-1", Marker{}, [&](const auto& snapshot) {
        ++validator_calls;
        return valid(snapshot);
    });
    int handler_calls{};
    const auto first = owner->apply(intent("peer-1:1"), [&](const auto&, const auto&) {
        ++handler_calls;
        return accepted(1, "first");
    });
    require(first.completed() && first.current_revision == 1 &&
            std::get<I>(first.result->at("order").storage()) == 1,
            "The accepted State and first history record commit together.");
    require(owner->snapshot().state == Marker{1, {"first"}},
            "The committed domain State matches the accepted candidate.");

    const auto refused = owner->apply(intent("peer-1:2"), [&](const auto&, const auto&) {
        ++handler_calls;
        return Owner::Decision{std::nullopt, {false, "blocked", "", {}}};
    });
    const auto after_refusal = owner->snapshot();
    require(refused.completed() && !std::get<bool>(refused.result->at("accepted").storage()) &&
            after_refusal.state == Marker{1, {"first"}} && after_refusal.revision == 1 &&
            after_refusal.history.order == 2,
            "A new gameplay refusal caches its outcome without changing State or revision.");

    const auto second = owner->apply(intent("peer-1:3"), [&](const auto&, const auto&) {
        ++handler_calls;
        return accepted(2, "second");
    });
    require(second.completed() && second.current_revision == 2 && handler_calls == 3,
            "A later accepted command advances the current revision.");
    const auto before_retry = owner->snapshot();
    const auto validation_before_retry = validator_calls;
    const auto must_not_run = [&](const auto&, const auto&) -> Owner::Decision {
        ++handler_calls;
        throw std::runtime_error("A cached request must not invoke current rules.");
    };
    auto replay = owner->apply(intent("peer-1:1"), must_not_run);
    require(replay.completed() && handler_calls == 3 &&
            validator_calls == validation_before_retry && replay.current_revision == 2 &&
            std::get<I>(replay.result->at("revision").storage()) == 1 &&
            std::get<I>(replay.result->at("original_fact").storage()) == 71 &&
            std::get<bool>(replay.result->at("duplicate").storage()),
            "Replay bypasses current rules and retains its historical revision and facts.");
    auto expected = *first.result;
    expected["duplicate"] = V(true);
    require(same(expected, *replay.result),
            "The entire delivered historical outcome differs only by the duplicate flag.");
    unchanged(*owner, before_retry);
    replay.result->at("original_fact") = V(I{900});
    const auto stored = owner->snapshot();
    require(std::get<I>(stored.history.records[0].result.at("original_fact").storage()) == 71 &&
            !std::get<bool>(stored.history.records[0].result.at("duplicate").storage()),
            "Mutating a delivered map cannot alter the stored original result.");

    const auto refused_retry = owner->apply(intent("peer-1:2"), must_not_run);
    require(refused_retry.completed() && handler_calls == 3 &&
            !std::get<bool>(refused_retry.result->at("accepted").storage()) &&
            std::get<I>(refused_retry.result->at("revision").storage()) == 1,
            "Refused history is also replayed without current admission or State mutation.");

    auto reused = intent("peer-1:1");
    reused["slot"] = V(0.0);
    const auto mismatch = owner->apply(reused, must_not_run);
    require(mismatch.error == w::TransactionError::history && !mismatch.result &&
            mismatch.history_error == a::Error::request_reuse && handler_calls == 3,
            "Numeric type changes cannot reuse an original command identity.");
    auto foreign = intent("new:1");
    foreign["context"] = V("foreign-world");
    const auto wrong_context = owner->apply(foreign, must_not_run);
    require(wrong_context.history_error == a::Error::wrong_context && handler_calls == 3,
            "A foreign context is refused before the trusted handler.");
    unchanged(*owner, before_retry);
}

void failed_preparation_is_atomic() {
    bool validator_throws{};
    auto owner = Owner::create_new("world-1", Marker{}, [&](const auto& snapshot) {
        if (validator_throws) throw std::runtime_error("invented validator failure");
        return valid(snapshot);
    });
    const auto before = owner->snapshot();
    const auto rejected = owner->apply(intent("invalid:1"), [](const auto&, const auto&) {
        return accepted(-1);
    });
    require(rejected.error == w::TransactionError::invalid_candidate && !rejected.result,
            "Domain validation rejects the complete candidate before committing history.");
    unchanged(*owner, before);
    const auto missing = owner->apply(intent("invalid:2"), [](const auto&, const auto&) {
        return Owner::Decision{std::nullopt, {true, "marked", "marker-1", {}}};
    });
    require(missing.error == w::TransactionError::invalid_decision && !missing.result,
            "An accepted result without replacement State cannot commit.");
    unchanged(*owner, before);
    const auto extra = owner->apply(intent("invalid:3"), [](const auto&, const auto&) {
        return Owner::Decision{Marker{1, {}}, {false, "blocked", "", {}}};
    });
    require(extra.error == w::TransactionError::invalid_decision && !extra.result,
            "A refused result cannot smuggle in replacement State.");
    unchanged(*owner, before);
    const auto spoof = owner->apply(intent("invalid:4"), [](const auto&, const auto&) {
        auto decision = accepted(1);
        decision.outcome.facts.emplace("order", V(I{99}));
        return decision;
    });
    require(spoof.error == w::TransactionError::history &&
            spoof.history_error == a::Error::invalid_outcome && !spoof.result,
            "Invalid history facts cannot commit an otherwise valid State candidate.");
    unchanged(*owner, before);
    const auto thrown = owner->apply(intent("invalid:5"), [](const auto&, const auto&) -> Owner::Decision {
        throw std::bad_alloc();
    });
    require(thrown.error == w::TransactionError::preparation_failed && !thrown.result,
            "A handler allocation failure publishes neither result nor partial State.");
    unchanged(*owner, before);
    validator_throws = true;
    const auto validation_exception = owner->apply(intent("invalid:6"), [](const auto&, const auto&) {
        return accepted(1);
    });
    validator_throws = false;
    require(validation_exception.error == w::TransactionError::preparation_failed &&
            !validation_exception.result, "A validator exception cannot split State from history.");
    unchanged(*owner, before);
}

struct CopyFault {
    static inline bool fail{};
    I marker{};
    CopyFault() = default;
    CopyFault(const CopyFault& other) : marker(other.marker) {
        if (fail) throw std::bad_alloc();
    }
    CopyFault(CopyFault&&) noexcept = default;
    CopyFault& operator=(const CopyFault&) = default;
    CopyFault& operator=(CopyFault&&) noexcept = default;
};

void refused_state_copy_failure() {
    using FaultOwner = w::TransactionOwner<CopyFault>;
    auto owner = FaultOwner::create_new("world-1", CopyFault{}, [](const auto&) { return true; });
    CopyFault::fail = true;
    const auto delivery = owner->apply(intent("fault:1"), [](const auto&, const auto&) {
        return FaultOwner::Decision{std::nullopt, {false, "blocked", "", {}}};
    });
    CopyFault::fail = false;
    const auto after = owner->snapshot();
    require(delivery.error == w::TransactionError::preparation_failed && !delivery.result &&
            after.state.marker == 0 && after.revision == 0 && after.history.records.empty() &&
            after.history.order == 0,
            "State copying after history preparation can fail without committing either half.");
}

void advance_with_domain_witness() {
    int ordinary_calls{};
    auto owner = Owner::create_new("world-1", Marker{}, [&](const auto& candidate) {
        ++ordinary_calls;
        return valid(candidate);
    });
    require(owner != nullptr && ordinary_calls == 1,
            "The ordinary domain validator admits the initial State once.");
    const auto initial = owner->snapshot();
    int witness_calls{};
    const auto reject = owner->advance([](const auto&) -> std::optional<Marker> {
        return Marker{1, {"candidate"}};
    }, [&](const auto& candidate) {
        ++witness_calls;
        return valid(candidate) && candidate.state.value == 2;
    });
    require(reject.error == w::TransactionError::invalid_candidate && witness_calls == 1 &&
            ordinary_calls == 1, "A trusted step validator can reject before the atomic swap.");
    unchanged(*owner, initial);
    const auto accepted_step = owner->advance([](const auto&) -> std::optional<Marker> {
        return Marker{2, {"witnessed"}};
    }, [&](const auto& candidate) {
        ++witness_calls;
        return valid(candidate) && candidate.state.value == 2;
    });
    const auto accepted_state = owner->snapshot();
    require(accepted_step.error == w::TransactionError::none && accepted_step.changed &&
            accepted_state.state == Marker{2, {"witnessed"}} && accepted_state.revision == 1 &&
            accepted_state.history.order == 0 && accepted_state.history.records.empty() &&
            witness_calls == 2 && ordinary_calls == 1,
            "A witnessed step retains generic history and revision semantics.");
    const auto empty_step = owner->advance([](const auto&) -> std::optional<Marker> {
        return std::nullopt;
    }, [&](const auto&) {
        ++witness_calls;
        return false;
    });
    require(empty_step.error == w::TransactionError::none && !empty_step.changed &&
            witness_calls == 2, "An unchanged step does not invoke candidate validation.");
    const auto throwing_step = owner->advance([](const auto&) -> std::optional<Marker> {
        return Marker{3, {"throwing"}};
    }, [](const auto&) -> bool { throw std::bad_alloc(); });
    require(throwing_step.error == w::TransactionError::preparation_failed,
            "A trusted validator exception cannot commit a partial step.");
    unchanged(*owner, accepted_state);
    const auto ordinary_reject = owner->advance([](const auto&) -> std::optional<Marker> {
        return Marker{11, {"invalid"}};
    });
    require(ordinary_reject.error == w::TransactionError::invalid_candidate && ordinary_calls == 2,
            "Ordinary steps still use the stored complete validator.");
    unchanged(*owner, accepted_state);
}

void nested_writes_are_refused() {
    auto owner = Owner::create_new("world-1", Marker{}, valid);
    int inner_calls{};
    const auto outer = owner->apply(intent("outer:1"), [&](const auto& snapshot, const auto&) {
        const auto inner = owner->apply(intent("inner:1"), [&](const auto&, const auto&) {
            ++inner_calls;
            return accepted(9);
        });
        require(inner.error == w::TransactionError::reentrant && !inner.result &&
                inner_calls == 0 && snapshot.revision == 0,
                "Nested writes are refused before handler invocation or commit.");
        return accepted(1);
    });
    const auto after = owner->snapshot();
    require(outer.completed() && after.state.value == 1 && after.revision == 1 &&
            after.history.records.size() == 1 && after.history.order == 1,
            "The outer transaction commits once without caching a nested write.");
}
}  // namespace

int main() {
    try {
        creation_and_detached_reads();
        commit_refusal_and_historical_retry();
        failed_preparation_is_atomic();
        refused_state_copy_failure();
        advance_with_domain_witness();
        nested_writes_are_refused();
        std::cout << "{\"status\":\"pass\",\"evidence\":\"invented_native_transactions\","
                     "\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "transactions_test: " << error.what() << '\n';
        return 1;
    }
}
