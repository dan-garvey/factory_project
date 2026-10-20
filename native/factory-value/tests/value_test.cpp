#include "factory/value.hpp"

#include <cmath>
#include <iostream>
#include <iterator>
#include <limits>
#include <stdexcept>
#include <string>
#include <type_traits>

namespace values = factory::values;
using values::Value;

static_assert(!std::is_convertible_v<bool, Value>);
static_assert(!std::is_convertible_v<Value::Integer, Value>);
static_assert(!std::is_constructible_v<Value, void*>);
static_assert(std::is_constructible_v<Value, const char*>);

namespace {
int checks = 0;
int failures = 0;

void check(bool condition, const std::string& label) {
    ++checks;
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << label << '\n';
    }
}

Value integer(Value::Integer number) { return Value(number); }

bool has_reason(const std::optional<values::Difference>& difference, values::Reason reason) {
    return difference && difference->reason == reason;
}

void scalar_types() {
    check(Value().type() == values::Type::null && Value(nullptr).type() == values::Type::null,
          "Explicit null and default null agree.");
    check(Value("P").type() == values::Type::string,
          "A string literal cannot silently construct a boolean.");
    check(!values::typed_difference(Value(""), Value(std::string{})),
          "An empty string remains an exact string.");
    const Value examples[]{Value(), Value(false), integer(0), Value(0.0), Value("0"),
                           Value(Value::Array{}), Value(Value::Object{})};
    for (std::size_t left = 0; left < std::size(examples); ++left) {
        for (std::size_t right = 0; right < std::size(examples); ++right) {
            check(values::typed_difference(examples[left], examples[right]).has_value() == (left != right),
                  "Typed comparisons distinguish every declared scalar and container kind.");
        }
    }
    check(values::wire_difference(Value(false), integer(0)).has_value(), "A boolean is never an integer count.");
    check(values::wire_difference(Value(true), Value(1.0)).has_value(), "A boolean is never a floating count.");
    check(values::wire_difference(Value("1"), integer(1)).has_value(), "A string cannot impersonate an item quantity.");
    check(values::wire_difference(Value(nullptr), integer(0)).has_value(), "Null cannot impersonate zero.");
    check(has_reason(values::typed_difference(Value(false), Value(true)), values::Reason::different_value),
          "Different boolean values are reported without numeric conversion.");
    for (const double number : {std::numeric_limits<double>::infinity(),
                                -std::numeric_limits<double>::infinity(),
                                std::numeric_limits<double>::quiet_NaN()}) {
        bool rejected = false;
        try { const Value invalid(number); (void)invalid; }
        catch (const std::invalid_argument&) { rejected = true; }
        check(rejected, "Nonfinite plain numbers are refused before they can enter the value layer.");
    }
    bool rejected = false;
    try { const Value invalid(static_cast<const char*>(nullptr)); (void)invalid; }
    catch (const std::invalid_argument&) { rejected = true; }
    check(rejected, "A null string pointer does not become a boolean or an empty string.");
}

void numeric_boundaries() {
    check(!values::wire_difference(integer(4), Value(4.0)), "An exact integral observation agrees across numeric types.");
    check(!values::wire_difference(Value(4.0), integer(4)), "Exact observation comparison is symmetric.");
    check(has_reason(values::typed_difference(integer(4), Value(4.0)), values::Reason::different_type),
          "Authority comparison still rejects integer versus floating representation.");
    check(values::wire_difference(integer(4), Value(4.5)).has_value(), "A fractional number cannot equal an item count.");
    check(values::wire_difference(integer(1), Value(std::nextafter(1.0, 2.0))).has_value(),
          "One floating-point step cannot pass as an exact integer.");
    check(values::wire_difference(Value(0.3), Value(std::nextafter(0.3, 1.0))).has_value(),
          "Observation comparison has no epsilon for nearby floating values.");
    check(!values::wire_difference(integer(0), Value(-0.0)), "Signed floating zero has the exact numerical value zero.");
    check(values::typed_difference(integer(0), Value(-0.0)).has_value(), "Typed zero still retains its scalar kind.");

    constexpr Value::Integer exact_limit = 9007199254740992;
    check(!values::wire_difference(integer(exact_limit), Value(9007199254740992.0)),
          "The exact double integer boundary compares correctly.");
    check(values::wire_difference(integer(exact_limit + 1), Value(9007199254740992.0)).has_value(),
          "A one-unit integer change above the exact-double range is not rounded away.");
    check(values::wire_difference(Value(9007199254740992.0), integer(exact_limit + 1)).has_value(),
          "The one-unit refusal is symmetric.");
    check(values::wire_difference(integer(-exact_limit - 1), Value(-9007199254740992.0)).has_value(),
          "Negative integers also retain one-unit distinctions.");

    const auto maximum = std::numeric_limits<Value::Integer>::max();
    const auto minimum = std::numeric_limits<Value::Integer>::min();
    check(!values::typed_difference(integer(maximum), integer(maximum)), "The largest integer remains exact in typed comparisons.");
    check(values::wire_difference(integer(maximum), Value(9223372036854775808.0)).has_value(),
          "Rounded INT64_MAX cannot match the out-of-range double 2^63.");
    check(!values::wire_difference(integer(minimum), Value(-9223372036854775808.0)),
          "The exactly representable negative integer boundary remains valid.");
    check(values::wire_difference(integer(minimum), Value(-18446744073709551616.0)).has_value(),
          "An out-of-range negative double is refused before conversion.");
    check(values::wire_difference(integer(0), Value(std::numeric_limits<double>::max())).has_value(),
          "A huge finite double cannot be narrowed into an integer.");
}

void containers_and_diagnostics() {
    const Value expected(Value::Object{
        {"inventories", Value(Value::Object{{"P", Value(4.0)}, {"Q", Value(1.0)}})},
        {"parts", Value(Value::Object{{"collector", Value(0.0)}})}
    });
    Value::Object inventory{{"P", integer(4)}, {"Q", integer(1)}};
    const Value actual(Value::Object{
        {"inventories", Value(inventory)},
        {"parts", Value(Value::Object{{"collector", integer(0)}})}
    });
    check(!values::wire_difference(expected, actual), "An invented nested observation permits exact numeric representations.");
    const auto strict = values::typed_difference(expected, actual);
    check(strict && strict->path == "$[\"inventories\"][\"P\"]" && strict->reason == values::Reason::different_type,
          "The same invented fixture remains type-distinct for authority comparison.");
    inventory.insert_or_assign("P", integer(5));
    const Value altered(Value::Object{
        {"inventories", Value(inventory)},
        {"parts", Value(Value::Object{{"collector", integer(0)}})}
    });
    const auto difference = values::wire_difference(expected, altered);
    check(difference && difference->path == "$[\"inventories\"][\"P\"]" &&
          difference->reason == values::Reason::different_value,
          "A changed count produces the first exact nested field path.");
    check(!values::wire_difference(expected, actual), "Changing a builder cannot mutate an already constructed value.");
    check(has_reason(values::typed_difference(expected, actual), values::Reason::different_type),
          "Observation comparison cannot normalize the original authority values in place.");

    const Value array(Value::Array{integer(1), integer(2)});
    check(!values::wire_difference(array, Value(Value::Array{Value(1.0), Value(2.0)})),
          "Array elements allow exact numeric equivalence in their original order.");
    const auto swapped = values::wire_difference(array, Value(Value::Array{integer(2), integer(1)}));
    check(swapped && swapped->path == "$[0]" && swapped->reason == values::Reason::different_value,
          "Reordering an array is a concrete mismatch.");
    const auto shorter = values::wire_difference(array, Value(Value::Array{integer(1)}));
    check(shorter && shorter->reason == values::Reason::array_length && shorter->path == "$",
          "Array length is never silently truncated.");

    const Value object(Value::Object{{"P", integer(4)}});
    const auto missing = values::wire_difference(object, Value(Value::Object{}));
    check(missing && missing->path == "$[\"P\"]" && missing->reason == values::Reason::missing_key &&
          !missing->actual_type && missing->expected_type == values::Type::integer,
          "A missing key identifies the absent side without inventing a value.");
    const auto extra = values::wire_difference(object, Value(Value::Object{{"P", integer(4)}, {"Q", integer(0)}}));
    check(extra && extra->path == "$[\"Q\"]" && extra->reason == values::Reason::unexpected_key && !extra->expected_type,
          "An additional zero-valued key is still an unexpected key.");
    const auto escaped = values::typed_difference(
        Value(Value::Object{{"a\"\\\n", integer(1)}}),
        Value(Value::Object{{"a\"\\\n", integer(2)}}));
    check(escaped && escaped->path == R"($["a\"\\\u000a"])",
          "Diagnostic paths escape quotes, backslashes and control bytes.");

    Value nested = integer(1);
    for (int level = 0; level < 32; ++level) nested = Value(Value::Array{nested});
    check(!values::typed_difference(nested, nested), "The declared depth boundary is inclusive.");
    nested = Value(Value::Array{nested});
    const auto too_deep = values::wire_difference(nested, nested);
    check(too_deep && too_deep->reason == values::Reason::depth_limit,
          "Even equal oversized observations refuse beyond the declared depth.");
    check(has_reason(values::typed_difference(nested, nested), values::Reason::depth_limit),
          "Typed comparison also refuses excessive recursion.");
}
}  // namespace

int main() {
    scalar_types();
    numeric_boundaries();
    containers_and_diagnostics();
    std::cout << "{\"status\":\"" << (failures == 0 ? "pass" : "fail")
              << "\",\"checks\":" << checks << ",\"failures\":" << failures
              << ",\"evidence\":\"native_typed_value_tests\"}\n";
    return failures == 0 && checks > 0 ? 0 : 1;
}
