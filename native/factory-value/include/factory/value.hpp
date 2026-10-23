#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace factory::values {

enum class Type { null, boolean, integer, floating, string, array, object };

class Value {
public:
    using Integer = std::int64_t;
    using Array = std::vector<Value>;
    using Object = std::map<std::string, Value>;
    using Storage = std::variant<std::nullptr_t, bool, Integer, double, std::string, Array, Object>;

    Value() noexcept;
    explicit Value(std::nullptr_t) noexcept;
    explicit Value(bool) noexcept;
    explicit Value(Integer) noexcept;
    explicit Value(double);
    explicit Value(std::string);
    explicit Value(const char*);
    explicit Value(Array);
    explicit Value(Object);
    // A pointer must never silently become a boolean. String literals use the
    // exact non-template overload above; a null string pointer is refused.
    template<class T> Value(T*) = delete;

    [[nodiscard]] Type type() const noexcept;
    [[nodiscard]] const Storage& storage() const noexcept { return data_; }
    // A completed wire value can transfer its root without copying the
    // potentially large nested object. The rvalue qualifier prevents a
    // borrowed authority snapshot from being consumed accidentally.
    [[nodiscard]] Object take_object() &&;

private:
    Storage data_;
};

enum class Reason { different_type, different_value, array_length, missing_key, unexpected_key, depth_limit };

struct Difference {
    std::string path;
    Reason reason;
    std::optional<Type> expected_type;
    std::optional<Type> actual_type;
};

[[nodiscard]] const char* type_name(Type) noexcept;
[[nodiscard]] const char* reason_text(Reason) noexcept;

// Plain values retain their original scalar types. Use this boundary for
// authority, command-cache and checkpoint comparisons after schema validation.
[[nodiscard]] std::optional<Difference> typed_difference(
    const Value& expected, const Value& actual, std::size_t max_depth = 32);

// Observation-only equality: integers and finite floats may agree only when
// their numerical values are exact. Booleans, strings, keys and array order
// remain distinct. This function never converts or mutates either input.
[[nodiscard]] std::optional<Difference> wire_difference(
    const Value& expected, const Value& actual, std::size_t max_depth = 32);

}  // namespace factory::values
