#pragma once

#include "factory/authority_boundary.hpp"

#include <functional>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>

namespace factory::world {

enum class TransactionError {
    none, history, invalid_decision, invalid_candidate, reentrant, preparation_failed,
};

struct Delivery {
    TransactionError error{TransactionError::none};
    authority::Error history_error{authority::Error::none};
    std::unique_ptr<authority::Object> result;
    // Separate from the original historical revision inside a cached result.
    authority::Integer current_revision{};
    Delivery() = default;
    Delivery(TransactionError failure, authority::Error history, std::nullopt_t,
             authority::Integer revision) noexcept
        : error(failure), history_error(history), current_revision(revision) {}
    Delivery(TransactionError failure, authority::Error history, authority::Object value,
             authority::Integer revision)
        : error(failure), history_error(history),
          result(std::make_unique<authority::Object>(std::move(value))),
          current_revision(revision) {}
    [[nodiscard]] bool completed() const noexcept {
        return error == TransactionError::none && bool(result);
    }
};

struct Advance {
    TransactionError error{TransactionError::none};
    bool changed{};
    authority::Integer current_revision{};
};

// Nothing after the pointer swap may allocate or throw while returning delivery.
static_assert(std::is_nothrow_move_constructible_v<Delivery>);

// Unadopted native building block. State must be a complete, deeply owned value:
// copying it must not share mutable world data, and its destructor must not throw.
// The future game instantiation contains the one canonical material State, actor
// kits, topology and identity metadata. This template defines no competing schema.
// Calls are serialized on the owning authority thread; this is not a mutex or a
// hostile callback sandbox. Handler and validator are trusted native domain code.
template<class State>
class TransactionOwner final {
public:
    static_assert(std::is_copy_constructible_v<State>);
    static_assert(std::is_move_constructible_v<State>);
    static_assert(std::is_nothrow_destructible_v<State>);

    struct Snapshot {
        State state;
        authority::History history;
        authority::Integer revision{};
    };

    struct Decision {
        // Present exactly when outcome.accepted is true. A refused command has
        // no replacement State, but its original outcome is still cached.
        std::optional<State> candidate;
        authority::Outcome outcome;
    };

    // Validate the complete candidate: domain conservation, topology, identity
    // generations, roster and operation-specific history relationships belong
    // here. The owner also validates its generic history envelope independently.
    using Validator = std::function<bool(const Snapshot&)>;

    // Fresh initialization only: no import, history reset or fallback path.
    // Invalid input returns null. Allocation and validator exceptions propagate
    // before an owner is returned; caller values remain unchanged.
    [[nodiscard]] static std::unique_ptr<TransactionOwner> create_new(
            std::string context, const State& seed, Validator validator) {
        if (!validator) return nullptr;
        auto initial = std::make_unique<Snapshot>(
            Snapshot{seed, {std::move(context), 0, {}}, 0});
        auto proof = authority::prove_history(initial->history, 0);
        if (!proof || !validator(*initial)) return nullptr;
        return std::unique_ptr<TransactionOwner>(
            new TransactionOwner(std::move(initial), std::move(validator), std::move(*proof)));
    }

    // Explicit import of a complete already decoded snapshot. Validate before
    // constructing an owner; preserve every saved revision, request and outcome.
    // There is no fallback to create_new when this path refuses.
    [[nodiscard]] static std::unique_ptr<TransactionOwner> restore(
            const Snapshot& saved, Validator validator) {
        if (!validator) return nullptr;
        auto proof = authority::prove_history(saved.history, saved.revision);
        if (!proof || !validator(saved)) return nullptr;
        auto initial = std::make_unique<Snapshot>(saved);
        return std::unique_ptr<TransactionOwner>(
            new TransactionOwner(std::move(initial), std::move(validator), std::move(*proof)));
    }

    TransactionOwner(const TransactionOwner&) = delete;
    TransactionOwner& operator=(const TransactionOwner&) = delete;
    TransactionOwner(TransactionOwner&&) = delete;
    TransactionOwner& operator=(TransactionOwner&&) = delete;
    ~TransactionOwner() = default;

    // Return an owned copy. No public method exposes a mutable live borrow.
    // Copy failures propagate without modifying the owner.
    [[nodiscard]] Snapshot snapshot() const { return *current_; }
    // Read only during the owning thread's current operation. A later command
    // or tick may replace this snapshot.
    [[nodiscard]] const Snapshot& snapshot_ref() const noexcept { return *current_; }
    [[nodiscard]] authority::Integer current_revision() const noexcept {
        return current_->revision;
    }

    // Authority-thread stepping only. This is not a command or client clock.
    // A null candidate is an unchanged step. A changed candidate increments the
    // revision while retaining every historical request and original outcome.
    template<class Step>
    [[nodiscard]] Advance advance(Step&& step) noexcept {
        return advance(std::forward<Step>(step), validator_);
    }

    // A trusted domain step may carry a computed validation witness into its
    // complete candidate validator. Generic history checks and the atomic
    // pointer swap remain here; callers must still validate their full domain.
    template<class Step, class CandidateValidator>
    [[nodiscard]] Advance advance(Step&& step, CandidateValidator&& validate_candidate) noexcept {
        if (applying_) return {TransactionError::reentrant, false, current_->revision};
        Active guard(applying_);
        try {
            auto candidate = std::invoke(std::forward<Step>(step), std::as_const(*current_));
            if (!candidate) return {TransactionError::none, false, current_->revision};
            if (current_->revision == std::numeric_limits<authority::Integer>::max())
                return {TransactionError::invalid_candidate, false, current_->revision};
            auto next = std::make_unique<Snapshot>(Snapshot{
                std::move(*candidate), current_->history, current_->revision + 1});
            if (authority::validate_history(next->history, next->revision) != authority::Error::none ||
                !std::invoke(std::forward<CandidateValidator>(validate_candidate), std::as_const(*next)))
                return {TransactionError::invalid_candidate, false, current_->revision};
            Advance result{TransactionError::none, true, next->revision};
            current_.swap(next);
            return result;
        } catch (...) {
            return {TransactionError::preparation_failed, false, current_->revision};
        }
    }

    // A trusted system step keeps the exact request history. The current
    // owner already validated it on create, restore or the last transaction;
    // increasing only the revision cannot invalidate any recorded revision.
    // Temporarily transfer that history to the candidate so its validator can
    // read the exact log when needed. Rejection or an exception restores the
    // original before returning, without copying the log.
    template<class Step, class CandidateValidator>
    [[nodiscard]] Advance advance_retaining_history(
            Step&& step, CandidateValidator&& validate_candidate) noexcept {
        static_assert(std::is_nothrow_swappable_v<authority::History>);
        if (applying_) return {TransactionError::reentrant, false, current_->revision};
        Active guard(applying_);
        try {
            auto candidate = std::invoke(std::forward<Step>(step), std::as_const(*current_));
            if (!candidate) return {TransactionError::none, false, current_->revision};
            if (current_->revision == std::numeric_limits<authority::Integer>::max())
                return {TransactionError::invalid_candidate, false, current_->revision};
            auto next = std::make_unique<Snapshot>(Snapshot{
                std::move(*candidate), {}, current_->revision + 1});
            struct HistoryTransfer {
                Snapshot& prior;
                Snapshot& candidate;
                bool committed{};
                HistoryTransfer(Snapshot& old_snapshot, Snapshot& new_snapshot) noexcept
                    : prior(old_snapshot), candidate(new_snapshot) {
                    using std::swap;
                    swap(prior.history, candidate.history);
                }
                ~HistoryTransfer() noexcept {
                    if (committed) return;
                    using std::swap;
                    swap(prior.history, candidate.history);
                }
            } transfer(*current_, *next);
            if (!std::invoke(std::forward<CandidateValidator>(validate_candidate),
                             std::as_const(*next)))
                return {TransactionError::invalid_candidate, false, current_->revision};
            Advance result{TransactionError::none, true, next->revision};
            current_.swap(next);
            transfer.committed = true;
            return result;
        } catch (...) {
            return {TransactionError::preparation_failed, false, current_->revision};
        }
    }

    // Session must already bind the actor/request to its authenticated caller.
    // The handler receives only const current facts and runs only for a fresh
    // valid request. It derives targets and applies current native/reach/rule
    // admission before returning an uncommitted State and outcome. Neither this
    // API nor the generic history helper accepts a client pose as authority.
    template<class Handler>
    [[nodiscard]] Delivery apply(const authority::Object& intent, Handler&& handler) noexcept {
        return apply(intent, std::forward<Handler>(handler), validator_);
    }

    // A domain owner may supply a validator for a trusted command plan. The
    // generic appended-history envelope is still checked here before commit.
    template<class Handler, class CandidateValidator>
    [[nodiscard]] Delivery apply(const authority::Object& intent, Handler&& handler,
                                 CandidateValidator&& validate_candidate) noexcept {
        if (applying_) return failure(TransactionError::reentrant);
        Active guard(applying_);
        try {
            const auto lookup = authority::inspect_validated_request(current_->history, intent);
            if (lookup.error != authority::Error::none)
                return failure(TransactionError::history, lookup.error);
            if (lookup.cached) {
                auto result = lookup.cached->result;
                result.at("duplicate") = values::Value(true);
                return {TransactionError::none, authority::Error::none,
                        std::move(result), current_->revision};
            }

            Decision decision = std::invoke(std::forward<Handler>(handler),
                                            std::as_const(*current_), intent);
            if (decision.outcome.accepted != decision.candidate.has_value())
                return failure(TransactionError::invalid_decision);

            auto prepared = authority::prepare_record_tail(current_->history, intent,
                decision.outcome, current_->revision);
            if (prepared.error != authority::Error::none)
                return failure(TransactionError::history, prepared.error);
            if (!prepared.record)
                return failure(TransactionError::invalid_decision);

            State next_state = decision.candidate
                ? std::move(*decision.candidate) : current_->state;
            auto next = std::make_unique<Snapshot>(Snapshot{
                std::move(next_state), {},
                prepared.resulting_revision});
            struct HistoryAppend {
                Snapshot& prior;
                Snapshot& candidate;
                bool appended{};
                bool committed{};
                HistoryAppend(Snapshot& old_snapshot, Snapshot& new_snapshot) noexcept
                    : prior(old_snapshot), candidate(new_snapshot) {
                    using std::swap;
                    swap(prior.history, candidate.history);
                }
                ~HistoryAppend() noexcept {
                    if (committed) return;
                    if (appended) {
                        candidate.history.records.pop_back();
                        --candidate.history.order;
                    }
                    using std::swap;
                    swap(prior.history, candidate.history);
                }
            } append(*current_, *next);
            next->history.records.push_back(std::move(*prepared.record));
            ++next->history.order;
            append.appended = true;
            authority::HistoryProof next_proof;
            if (!authority::validate_history_append(next->history, next->revision, proof_, next_proof)) {
                // The exceptional path may need the full scan to preserve the
                // public history error category, including cumulative limits.
                const auto error = authority::validate_history(next->history, next->revision);
                return failure(TransactionError::history,
                    error == authority::Error::none ? authority::Error::invalid_history : error);
            }
            if (!std::invoke(std::forward<CandidateValidator>(validate_candidate),
                             std::as_const(*next)))
                return failure(TransactionError::invalid_candidate);

            // Prepare delivery before the only commit. Stored duplicate remains
            // false, and every returned map is owned independently of history.
            Delivery delivery{TransactionError::none, authority::Error::none,
                              next->history.records.back().result, next->revision};
            static_assert(std::is_nothrow_swappable_v<authority::HistoryProof>);
            using std::swap;
            swap(proof_, next_proof);
            current_.swap(next);
            append.committed = true;
            return delivery;
        } catch (...) {
            // Preparation, handler and validator failures publish no result or
            // partial State/history. Diagnostics are a bounded category only.
            return failure(TransactionError::preparation_failed);
        }
    }

private:
    class Active {
    public:
        explicit Active(bool& flag) noexcept : flag_(flag) { flag_ = true; }
        ~Active() noexcept { flag_ = false; }
        Active(const Active&) = delete;
        Active& operator=(const Active&) = delete;
    private:
        bool& flag_;
    };

    TransactionOwner(std::unique_ptr<Snapshot> initial, Validator validator,
                     authority::HistoryProof proof) noexcept
        : current_(std::move(initial)), validator_(std::move(validator)), proof_(std::move(proof)) {}

    [[nodiscard]] Delivery failure(TransactionError error,
            authority::Error history_error = authority::Error::none) const noexcept {
        return {error, history_error, std::nullopt, current_->revision};
    }

    std::unique_ptr<Snapshot> current_;
    Validator validator_;
    authority::HistoryProof proof_;
    bool applying_{};
};

}  // namespace factory::world
