#include "factory/authority_boundary.hpp"

#include <cmath>
#include <initializer_list>
#include <limits>
#include <set>
#include <utility>

namespace factory::authority {
namespace {
using Value = values::Value;

const Value* field(const Object& object, const char* name) {
    const auto at = object.find(name);
    return at == object.end() ? nullptr : &at->second;
}

template<class T> const T* as(const Value* value) {
    return value ? std::get_if<T>(&value->storage()) : nullptr;
}

bool identity(const std::string& value) {
    return !value.empty() && value.size() <= 128 && value.find('\0') == std::string::npos;
}

bool exact_fields(const Object& object, std::initializer_list<const char*> names) {
    if (object.size() != names.size()) return false;
    for (const auto* name : names) if (!object.contains(name)) return false;
    return true;
}

struct Budget {
    std::size_t nodes{};
    std::size_t bytes{};
    bool node(std::size_t depth) {
        return depth <= 32 && ++nodes <= 100000;
    }
    bool text(const std::string& value) {
        constexpr std::size_t total = 4 * 1024 * 1024;
        if (value.size() > 1024 * 1024 || value.size() > total - bytes) return false;
        bytes += value.size();
        return true;
    }
    bool object(const Object& value, std::size_t depth) {
        if (!node(depth)) return false;
        for (const auto& [key, item] : value) {
            if (!text(key) || !accept(item, depth + 1)) return false;
        }
        return true;
    }
    bool accept(const Value& value, std::size_t depth) {
        if (const auto* object_value = as<Object>(&value)) return object(*object_value, depth);
        if (!node(depth)) return false;
        if (const auto* string = as<std::string>(&value)) return text(*string);
        if (const auto* array = as<Value::Array>(&value)) {
            for (const auto& item : *array) if (!accept(item, depth + 1)) return false;
        }
        return true;
    }
};

Error intent_error(const History& history, const Object& intent) {
    const auto* context = as<std::string>(field(intent, "context"));
    if (!context || *context != history.context) return Error::wrong_context;
    const auto* actor = as<std::string>(field(intent, "client"));
    const auto* request = as<std::string>(field(intent, "request"));
    if (!actor || !request || !identity(*actor) || !identity(*request)) return Error::missing_identity;
    const auto* action = field(intent, "action");
    if (action && !as<std::string>(action)) return Error::invalid_intent;
    return Error::none;
}

bool same(const Object& a, const Object& b) {
    return !values::typed_difference(Value(a), Value(b));
}

Error validate(const History& history, Integer revision, Budget& budget) {
    if (revision < 0 || !identity(history.context) || history.order < 0
        || history.records.size() > maximum_records
        || history.order != static_cast<Integer>(history.records.size())) return Error::invalid_history;
    // Count the exact encoded wrapper as well as the retained records. This
    // keeps an accepted encoded history within the same decode depth/budget.
    budget.nodes = 5; // root, schema, context, order and records array
    budget.bytes = 25; // schema/context/order/records keys
    if (!budget.text(history.context)) return Error::limit;
    std::set<std::pair<std::string, std::string>> identities;
    Integer previous_revision = 0;
    for (std::size_t index = 0; index < history.records.size(); ++index) {
        const auto& record = history.records[index];
        if (!budget.node(2) || !budget.text("intent") || !budget.object(record.intent, 3)
            || !budget.text("result") || !budget.object(record.result, 3)) return Error::limit;
        if (intent_error(history, record.intent) != Error::none) return Error::invalid_history;
        const auto& actor = *as<std::string>(field(record.intent, "client"));
        const auto& request = *as<std::string>(field(record.intent, "request"));
        if (!identities.emplace(actor, request).second) return Error::invalid_history;
        const auto* accepted = as<bool>(field(record.result, "accepted"));
        const auto* duplicate = as<bool>(field(record.result, "duplicate"));
        const auto* reason = as<std::string>(field(record.result, "reason"));
        const auto* entity = as<std::string>(field(record.result, "entity"));
        const auto* result_context = as<std::string>(field(record.result, "context"));
        const auto* result_actor = as<std::string>(field(record.result, "client"));
        const auto* result_request = as<std::string>(field(record.result, "request"));
        const auto* result_revision = as<Integer>(field(record.result, "revision"));
        const auto* result_order = as<Integer>(field(record.result, "order"));
        if (!accepted || !duplicate || *duplicate || !reason || reason->empty() || !entity
            || !result_context || *result_context != history.context
            || !result_actor || *result_actor != actor || !result_request || *result_request != request
            || !result_revision || *result_revision < previous_revision || *result_revision > revision
            || !result_order || *result_order != static_cast<Integer>(index + 1)) return Error::invalid_history;
        if (*accepted && *result_revision == previous_revision) return Error::invalid_history;
        previous_revision = *result_revision;
    }
    return Error::none;
}

bool finite(const Point& point) {
    for (const auto value : point) if (!std::isfinite(value)) return false;
    return true;
}
} // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_history: return "invalid_history";
        case Error::wrong_context: return "wrong_context";
        case Error::missing_identity: return "missing_identity";
        case Error::invalid_intent: return "invalid_intent";
        case Error::request_reuse: return "request_reuse";
        case Error::invalid_outcome: return "invalid_outcome";
        case Error::limit: return "limit";
        case Error::counter_overflow: return "counter_overflow";
        case Error::wrong_actor: return "wrong_actor";
        case Error::actor_unready: return "actor_unready";
        case Error::invalid_actor_sample: return "invalid_actor_sample";
        case Error::out_of_reach: return "out_of_reach";
    }
    return "unknown";
}

Error validate_history(const History& history, Integer current_revision) {
    Budget budget;
    return validate(history, current_revision, budget);
}

Lookup inspect_request(const History& history, const Object& intent, Integer current_revision) {
    if (const auto error = validate_history(history, current_revision); error != Error::none) return {error, {}};
    Budget budget;
    if (!budget.object(intent, 0)) return {Error::limit, {}};
    if (const auto error = intent_error(history, intent); error != Error::none) return {error, {}};
    const auto& actor = *as<std::string>(field(intent, "client"));
    const auto& request = *as<std::string>(field(intent, "request"));
    for (const auto& record : history.records) {
        if (*as<std::string>(field(record.intent, "client")) == actor
            && *as<std::string>(field(record.intent, "request")) == request) {
            return same(record.intent, intent) ? Lookup{Error::none, record}
                                               : Lookup{Error::request_reuse, {}};
        }
    }
    return {};
}

Preparation prepare_record(const History& history, const Object& intent,
                           const Outcome& outcome, Integer current_revision) {
    const auto lookup = inspect_request(history, intent, current_revision);
    if (lookup.error != Error::none) return {lookup.error, {}, {}, false, 0};
    if (lookup.cached) return {Error::none, {}, lookup.cached, true, current_revision};
    if (history.records.size() == maximum_records) return {Error::limit, {}, {}, false, 0};
    if (history.order == std::numeric_limits<Integer>::max()
        || (outcome.accepted && current_revision == std::numeric_limits<Integer>::max())) {
        return {Error::counter_overflow, {}, {}, false, 0};
    }
    Budget facts;
    if (outcome.reason.empty()) return {Error::invalid_outcome, {}, {}, false, 0};
    if (!facts.text(outcome.reason) || !facts.text(outcome.entity)
        || !facts.object(outcome.facts, 0)) return {Error::limit, {}, {}, false, 0};
    for (const auto* reserved : {"accepted", "reason", "entity", "context", "revision", "order", "duplicate", "client", "request"}) {
        if (outcome.facts.contains(reserved)) return {Error::invalid_outcome, {}, {}, false, 0};
    }
    const Integer next_revision = current_revision + (outcome.accepted ? 1 : 0);
    Object result = outcome.facts;
    result.emplace("accepted", Value(outcome.accepted));
    result.emplace("reason", Value(outcome.reason));
    result.emplace("entity", Value(outcome.entity));
    result.emplace("context", Value(history.context));
    result.emplace("revision", Value(next_revision));
    result.emplace("order", Value(history.order + 1));
    result.emplace("duplicate", Value(false));
    result.emplace("client", *field(intent, "client"));
    result.emplace("request", *field(intent, "request"));
    Record record{intent, std::move(result)};
    History next = history;
    ++next.order;
    next.records.push_back(record);
    if (const auto error = validate_history(next, next_revision); error != Error::none) return {error, {}, {}, false, 0};
    return {Error::none, std::move(next), std::move(record), false, next_revision};
}

EncodedHistory encode_history(const History& history, Integer current_revision) {
    if (const auto error = validate_history(history, current_revision); error != Error::none) return {error, {}};
    Value::Array records;
    records.reserve(history.records.size());
    for (const auto& record : history.records) {
        records.emplace_back(Object{{"intent", Value(record.intent)}, {"result", Value(record.result)}});
    }
    return {Error::none, Value(Object{{"schema", Value(Integer{1})}, {"context", Value(history.context)},
                                      {"order", Value(history.order)}, {"records", Value(std::move(records))}})};
}

DecodedHistory decode_history(const Value& value, Integer current_revision) {
    Budget budget;
    if (!budget.accept(value, 0)) return {Error::limit, {}};
    const auto* object = as<Object>(&value);
    if (!object || !exact_fields(*object, {"schema", "context", "order", "records"})) return {Error::invalid_history, {}};
    const auto* schema = as<Integer>(field(*object, "schema"));
    const auto* context = as<std::string>(field(*object, "context"));
    const auto* order = as<Integer>(field(*object, "order"));
    const auto* records = as<Value::Array>(field(*object, "records"));
    if (!schema || *schema != 1 || !context || !order || !records || records->size() > maximum_records) return {Error::invalid_history, {}};
    History history{*context, *order, {}};
    history.records.reserve(records->size());
    for (const auto& item : *records) {
        const auto* record = as<Object>(&item);
        if (!record || !exact_fields(*record, {"intent", "result"})) return {Error::invalid_history, {}};
        const auto* intent = as<Object>(field(*record, "intent"));
        const auto* result = as<Object>(field(*record, "result"));
        if (!intent || !result) return {Error::invalid_history, {}};
        history.records.push_back({*intent, *result});
    }
    if (const auto error = validate_history(history, current_revision); error != Error::none) return {error, {}};
    return {Error::none, std::move(history)};
}

ReachResult check_reach(const std::string& bound_actor, const ActorCut& cut,
                        const std::vector<Point>& targets) {
    if (!identity(bound_actor) || cut.actor != bound_actor) return {Error::wrong_actor, {}};
    if (!cut.ready || cut.native_epoch < 1) return {Error::actor_unready, {}};
    const double squared_reach = cut.build_reach * cut.build_reach;
    if (!finite(cut.position) || !std::isfinite(cut.build_reach) || cut.build_reach <= 0
        || !std::isfinite(squared_reach)) return {Error::invalid_actor_sample, {}};
    if (targets.empty() || targets.size() > maximum_targets) return {Error::limit, {}};
    std::vector<double> distances;
    distances.reserve(targets.size());
    bool reachable = true;
    for (const auto& target : targets) {
        if (!finite(target)) return {Error::invalid_actor_sample, {}};
        double squared = 0;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const double delta = cut.position[axis] - target[axis];
            squared += delta * delta;
        }
        if (!std::isfinite(squared)) return {Error::invalid_actor_sample, {}};
        distances.push_back(squared);
        reachable = reachable && squared <= squared_reach;
    }
    ReachReceipt receipt{cut, targets, std::move(distances), reachable};
    return {reachable ? Error::none : Error::out_of_reach, std::move(receipt)};
}

} // namespace factory::authority
