#include "factory/authority_boundary.hpp"

#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <utility>

namespace a = factory::authority;
using V = factory::values::Value;
using I = a::Integer;
using O = a::Object;

namespace {
int checks = 0;
void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
    ++checks;
}
bool same(const O& left, const O& right) {
    return !factory::values::typed_difference(V(left), V(right));
}
O intent(const char* actor = "P", const char* request = "peer-a:1") {
    return {{"context", V("world-1")}, {"client", V(actor)}, {"request", V(request)},
            {"action", V("place")}, {"cell", V(V::Array{V(I{0}), V(I{1})})}};
}

void history_and_replay() {
    const a::History empty{"world-1", 0, {}};
    const O first = intent();
    require(a::validate_history(empty, 0) == a::Error::none, "An empty history is valid.");
    require(!a::inspect_request(empty, first, 0).cached, "A new request has no cached result.");
    const a::Outcome accepted{true, "placed", "gear-1", {{"original_cut", V(V::Array{V(0.0), V(1.0), V(2.0)})}}};
    const auto prepared = a::prepare_record(empty, first, accepted, 0);
    require(prepared.error == a::Error::none && prepared.next && prepared.record && !prepared.duplicate,
            "A valid command prepares an uncommitted record.");
    require(empty.order == 0 && empty.records.empty(), "Preparation leaves the original history unchanged.");
    require(prepared.next->order == 1 && prepared.resulting_revision == 1, "The first accepted command has literal order and revision one.");
    const auto& saved = *prepared.next;
    const auto repeated = a::prepare_record(saved, first, {false, "out_of_reach", "", {}}, 12);
    require(repeated.error == a::Error::none && repeated.duplicate && !repeated.next && repeated.record,
            "A retry returns its cached record before evaluating a later refusal.");
    require(same(repeated.record->result, prepared.record->result), "Retry preserves the complete original result and native-cut facts.");
    require(std::get<I>(repeated.record->result.at("revision").storage()) == 1,
            "Retry does not retarget the historical revision to the current world.");
    require(std::get<bool>(repeated.record->result.at("duplicate").storage()) == false,
            "The stored result remains original; delivery alone marks a duplicate.");

    O changed = first;
    changed["cell"] = V(V::Array{V(0.0), V(I{1})});
    require(a::inspect_request(saved, changed, 1).error == a::Error::request_reuse, "Integer and float intents are distinct.");
    changed["cell"] = V(V::Array{V(false), V(I{1})});
    require(a::inspect_request(saved, changed, 1).error == a::Error::request_reuse, "Boolean and integer intents are distinct.");
    changed["cell"] = V(V::Array{V(I{1}), V(I{0})});
    require(a::inspect_request(saved, changed, 1).error == a::Error::request_reuse, "Array order is part of request identity.");
    changed = first;
    changed.emplace("unexpected", V());
    require(a::inspect_request(saved, changed, 1).error == a::Error::request_reuse, "Additional fields cannot reuse a request.");
    changed = first;
    changed["context"] = V("another-world");
    require(a::inspect_request(saved, changed, 1).error == a::Error::wrong_context, "A historical request belongs to its original world.");
    changed = first;
    changed["request"] = V(I{1});
    require(a::inspect_request(saved, changed, 1).error == a::Error::missing_identity, "A numeric request identifier is refused.");
    changed = first;
    changed["action"] = V(false);
    require(a::inspect_request(saved, changed, 1).error == a::Error::invalid_intent, "A boolean action is refused.");
    const auto fresh = a::prepare_record(saved, intent("P", "new-peer:1"), {false, "out_of_reach", "", {}}, 1);
    require(fresh.error == a::Error::none && fresh.next && fresh.next->order == 2 && fresh.resulting_revision == 1,
            "A fresh namespace can record a refusal without changing revision.");
    const auto refused_retry = a::inspect_request(*fresh.next, intent("P", "new-peer:1"), 7);
    require(refused_retry.cached && !std::get<bool>(refused_retry.cached->result.at("accepted").storage()),
            "The original refused result is cached exactly too.");
    const auto spoof = a::prepare_record(saved, intent("Q"), {true, "placed", "gear-2", {{"order", V(I{900})}}}, 1);
    require(spoof.error == a::Error::invalid_outcome && !spoof.next, "Extra facts cannot replace authority envelope fields.");
}

void import_and_bounds() {
    const a::History empty{"world-1", 0, {}};
    const auto first = a::prepare_record(empty, intent(), {true, "placed", "gear-1", {}}, 0);
    const auto encoded = a::encode_history(*first.next, 1);
    require(encoded.error == a::Error::none && encoded.value, "A valid history encodes as native values.");
    const auto decoded = a::decode_history(*encoded.value, 1);
    require(decoded.error == a::Error::none && decoded.history && decoded.history->order == 1,
            "The history subrecord imports with its literal order.");
    require(same(decoded.history->records[0].intent, first.record->intent)
            && same(decoded.history->records[0].result, first.record->result), "Import preserves exact intent and result types.");
    auto object = std::get<O>(encoded.value->storage());
    object["order"] = V(1.0);
    require(a::decode_history(V(object), 1).error == a::Error::invalid_history, "A floating-point authority order is refused.");
    object = std::get<O>(encoded.value->storage());
    object["schema"] = V(true);
    require(a::decode_history(V(object), 1).error == a::Error::invalid_history, "A boolean schema is refused.");
    object = std::get<O>(encoded.value->storage());
    object.emplace("extra", V());
    require(a::decode_history(V(object), 1).error == a::Error::invalid_history, "Unknown history wrapper fields are refused.");
    a::History corrupt = *first.next;
    corrupt.records[0].result["accepted"] = V(I{1});
    require(a::validate_history(corrupt, 1) == a::Error::invalid_history, "Accepted requires an actual boolean.");
    corrupt = *first.next;
    corrupt.records[0].result["duplicate"] = V(true);
    require(a::validate_history(corrupt, 1) == a::Error::invalid_history, "A delivered duplicate is not a stored original receipt.");
    corrupt = *first.next;
    corrupt.records[0].result["revision"] = V(I{2});
    require(a::validate_history(corrupt, 1) == a::Error::invalid_history, "Historical revisions cannot exceed the enclosing world.");
    corrupt = *first.next;
    corrupt.records[0].result["revision"] = V(I{0});
    require(a::validate_history(corrupt, 1) == a::Error::invalid_history, "An accepted command must advance the preceding revision.");
    corrupt = *first.next;
    corrupt.records.push_back(corrupt.records.front());
    corrupt.order = 2;
    corrupt.records.back().result["order"] = V(I{2});
    corrupt.records.back().result["revision"] = V(I{2});
    require(a::validate_history(corrupt, 2) == a::Error::invalid_history, "Repeated request identities cannot appear twice.");
    const auto maximum = std::numeric_limits<I>::max();
    const auto overflow = a::prepare_record(empty, intent(), {true, "placed", "gear-1", {}}, maximum);
    require(overflow.error == a::Error::counter_overflow && !overflow.next, "Revision overflow refuses without a candidate.");
    const auto at_limit = a::prepare_record(empty, intent(), {false, "blocked", "", {}}, maximum);
    require(at_limit.error == a::Error::none && at_limit.next && at_limit.resulting_revision == maximum,
            "A refusal at the maximum revision does not overflow it.");
    V nested;
    for (int n = 0; n < 40; ++n) nested = V(V::Array{std::move(nested)});
    const auto depth = a::prepare_record(empty, intent(), {false, "blocked", "", {{"nested", nested}}}, 0);
    require(depth.error == a::Error::limit && !depth.next, "Over-depth facts cannot be cached.");
    const V too_many_nodes(V::Array(a::maximum_records * 64, V{}));
    const auto breadth = a::prepare_record(empty, intent(),
        {false, "blocked", "", {{"breadth", too_many_nodes}}}, 0);
    require(breadth.error == a::Error::limit && !breadth.next,
        "An oversized Value tree cannot exceed the bounded history node allowance.");
    O missing_action = intent();
    missing_action.erase("action");
    const auto unsupported = a::prepare_record(empty, missing_action, {false, "unsupported_action", "", {}}, 0);
    require(unsupported.error == a::Error::none, "The existing empty-action refusal remains cacheable.");
    auto pair_a = intent("a|b", "c");
    auto pair_b = intent("a", "b|c");
    const auto p = a::prepare_record(empty, pair_a, {false, "blocked", "", {}}, 0);
    require(a::inspect_request(*p.next, pair_b, 0).error == a::Error::none
            && !a::inspect_request(*p.next, pair_b, 0).cached, "Identity pairs cannot collide through delimiter concatenation.");
}

void literal_reach() {
    const a::ActorCut cut{"P", {0, 0, 0}, 3, true, 4.0};
    const auto boundary = a::check_reach("P", cut, {{4, 0, 0}});
    require(boundary.error == a::Error::none && boundary.receipt && boundary.receipt->reachable
            && boundary.receipt->distances_squared == std::vector<double>{16.0}, "Literal four-unit tangency is accepted.");
    const auto vertical = a::check_reach("P", cut, {{0, 5, 0}});
    require(vertical.error == a::Error::out_of_reach && vertical.receipt
            && vertical.receipt->distances_squared == std::vector<double>{25.0}, "Vertical distance participates in reach.");
    const auto beyond = std::nextafter(4.0, std::numeric_limits<double>::infinity());
    require(a::check_reach("P", cut, {{beyond, 0, 0}}).error == a::Error::out_of_reach,
            "There is no reach epsilon beyond the exact boundary.");
    const auto endpoints = a::check_reach("P", cut, {{1, 0, 0}, {5, 0, 0}});
    require(endpoints.error == a::Error::out_of_reach && endpoints.receipt
            && endpoints.receipt->distances_squared == std::vector<double>{1.0, 25.0}, "Both endpoints must be reachable in the original order.");
    const auto reversed = a::check_reach("P", cut, {{5, 0, 0}, {1, 0, 0}});
    require(reversed.error == a::Error::out_of_reach && reversed.receipt
            && reversed.receipt->distances_squared == std::vector<double>{25.0, 1.0}, "Receipt targets retain their supplied canonical order.");
    require(a::check_reach("Q", cut, {{0, 0, 0}}).error == a::Error::wrong_actor, "A bound peer cannot use another actor's cut.");
    auto unavailable = cut;
    unavailable.ready = false;
    require(a::check_reach("P", unavailable, {{0, 0, 0}}).error == a::Error::actor_unready, "Unready actors have no reach.");
    unavailable = cut;
    unavailable.native_epoch = 0;
    require(a::check_reach("P", unavailable, {{0, 0, 0}}).error == a::Error::actor_unready, "A zero observation ordinal is not ready.");
    unavailable = cut;
    unavailable.position[0] = std::numeric_limits<double>::max();
    const auto overflow = a::check_reach("P", unavailable, {{0, 0, 0}});
    require(overflow.error == a::Error::invalid_actor_sample && !overflow.receipt,
            "Overflowed distance cannot publish an infinite cached receipt.");
    unavailable = cut;
    unavailable.position[1] = std::numeric_limits<double>::quiet_NaN();
    require(a::check_reach("P", unavailable, {{0, 0, 0}}).error == a::Error::invalid_actor_sample, "Nonfinite native cuts are refused.");
    require(a::check_reach("P", cut, {}).error == a::Error::limit, "Empty target sets do not silently grant reach.");
    require(a::check_reach("P", cut, std::vector<a::Point>(a::maximum_targets + 1)).error == a::Error::limit,
            "Target vectors have an explicit bound.");
}
} // namespace

int main() {
    try {
        history_and_replay();
        import_and_bounds();
        literal_reach();
        std::cout << "Passed " << checks << " invented authority-boundary checks. No engine or live World was started.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
