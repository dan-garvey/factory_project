#include "factory/value.hpp"

#include <cmath>
#include <stdexcept>
#include <utility>

namespace factory::values {

Value::Value() noexcept : data_(nullptr) {}
Value::Value(std::nullptr_t) noexcept : data_(nullptr) {}
Value::Value(bool value) noexcept : data_(value) {}
Value::Value(Integer value) noexcept : data_(value) {}
Value::Value(double value) : data_(value) {
    if (!std::isfinite(value)) throw std::invalid_argument("Plain floating-point values must be finite.");
}
Value::Value(std::string value) : data_(std::move(value)) {}
Value::Value(const char* value) : data_(std::string{}) {
    if (value == nullptr) throw std::invalid_argument("A null string pointer is not a string value.");
    data_ = std::string(value);
}
Value::Value(Array value) : data_(std::move(value)) {}
Value::Value(Object value) : data_(std::move(value)) {}
Type Value::type() const noexcept { return static_cast<Type>(data_.index()); }
Value::Object Value::take_object() && { return std::get<Object>(std::move(data_)); }

const char* type_name(Type type) noexcept {
    switch (type) {
        case Type::null: return "null";
        case Type::boolean: return "boolean";
        case Type::integer: return "integer";
        case Type::floating: return "floating point";
        case Type::string: return "string";
        case Type::array: return "array";
        case Type::object: return "dictionary";
    }
    return "unknown type";
}

const char* reason_text(Reason reason) noexcept {
    switch (reason) {
        case Reason::different_type: return "The value types differ.";
        case Reason::different_value: return "The values differ.";
        case Reason::array_length: return "The array lengths differ.";
        case Reason::missing_key: return "The expected dictionary key is missing.";
        case Reason::unexpected_key: return "An unexpected dictionary key is present.";
        case Reason::depth_limit: return "The declared comparison depth was exceeded.";
    }
    return "Unknown comparison result.";
}

namespace {

std::string key_path(const std::string& path, const std::string& key) {
    constexpr char hex[] = "0123456789abcdef";
    std::string result = path + "[\"";
    for (const unsigned char character : key) {
        if (character == '\\' || character == '"') {
            result += '\\';
            result += static_cast<char>(character);
        } else if (character < 0x20) {
            result += "\\u00";
            result += hex[character >> 4];
            result += hex[character & 0xf];
        } else {
            result += static_cast<char>(character);
        }
    }
    return result + "\"]";
}

bool is_number(Type type) noexcept { return type == Type::integer || type == Type::floating; }

bool same_integer_float(Value::Integer integer, double floating) noexcept {
    // Do not round the integer to a double. In particular, INT64_MAX rounds to
    // 2^63 and integers above 2^53 can lose one unit through that conversion.
    constexpr double limit = 9223372036854775808.0;  // Exactly 2^63.
    if (floating < -limit || floating >= limit || std::trunc(floating) != floating) return false;
    return integer == static_cast<Value::Integer>(floating);
}

std::optional<Difference> compare(const Value& expected, const Value& actual,
                                bool wire, std::size_t depth, std::size_t limit,
                                const std::string& path) {
    auto mismatch = [&](Reason reason) -> std::optional<Difference> {
        return Difference{path, reason, expected.type(), actual.type()};
    };
    if (depth > limit) return mismatch(Reason::depth_limit);
    if (expected.type() != actual.type()) {
        if (!wire || !is_number(expected.type()) || !is_number(actual.type())) {
            return mismatch(Reason::different_type);
        }
        const bool same = expected.type() == Type::integer
            ? same_integer_float(std::get<Value::Integer>(expected.storage()), std::get<double>(actual.storage()))
            : same_integer_float(std::get<Value::Integer>(actual.storage()), std::get<double>(expected.storage()));
        return same ? std::nullopt : mismatch(Reason::different_value);
    }
    switch (expected.type()) {
        case Type::null: return std::nullopt;
        case Type::boolean:
            return std::get<bool>(expected.storage()) == std::get<bool>(actual.storage())
                ? std::nullopt : mismatch(Reason::different_value);
        case Type::integer:
            return std::get<Value::Integer>(expected.storage()) == std::get<Value::Integer>(actual.storage())
                ? std::nullopt : mismatch(Reason::different_value);
        case Type::floating:
            return std::get<double>(expected.storage()) == std::get<double>(actual.storage())
                ? std::nullopt : mismatch(Reason::different_value);
        case Type::string:
            return std::get<std::string>(expected.storage()) == std::get<std::string>(actual.storage())
                ? std::nullopt : mismatch(Reason::different_value);
        case Type::array: {
            const auto& left = std::get<Value::Array>(expected.storage());
            const auto& right = std::get<Value::Array>(actual.storage());
            if (left.size() != right.size()) return mismatch(Reason::array_length);
            for (std::size_t index = 0; index < left.size(); ++index) {
                if (auto result = compare(left[index], right[index], wire, depth + 1, limit,
                                          path + '[' + std::to_string(index) + ']')) return result;
            }
            return std::nullopt;
        }
        case Type::object: {
            const auto& left = std::get<Value::Object>(expected.storage());
            const auto& right = std::get<Value::Object>(actual.storage());
            for (const auto& [key, value] : left) {
                const auto found = right.find(key);
                const auto at = key_path(path, key);
                if (found == right.end()) return Difference{at, Reason::missing_key, value.type(), std::nullopt};
                if (auto result = compare(value, found->second, wire, depth + 1, limit, at)) return result;
            }
            for (const auto& [key, value] : right) {
                if (!left.contains(key)) return Difference{key_path(path, key), Reason::unexpected_key,
                                                          std::nullopt, value.type()};
            }
            return std::nullopt;
        }
    }
    throw std::logic_error("Unknown plain value type.");
}

}  // namespace

std::optional<Difference> typed_difference(const Value& expected, const Value& actual, std::size_t max_depth) {
    return compare(expected, actual, false, 0, max_depth, "$");
}

std::optional<Difference> wire_difference(const Value& expected, const Value& actual, std::size_t max_depth) {
    return compare(expected, actual, true, 0, max_depth, "$");
}

}  // namespace factory::values
