#include "factory/godot_value.hpp"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <limits>
#include <string_view>
#include <utility>

namespace factory::godot_values {
namespace {
static_assert(sizeof(void*) == 8, "This adapter has only the recorded 64-bit engine ABI.");
constexpr std::size_t max_depth = 32;
constexpr std::size_t max_nodes = 100000;
constexpr std::size_t max_string_bytes = 1024 * 1024;
constexpr std::size_t max_total_string_bytes = 4 * 1024 * 1024;

struct Budget {
    std::size_t nodes = max_nodes;
    std::size_t strings = max_total_string_bytes;
    void enter(std::size_t depth) {
        if (depth > max_depth || nodes == 0) throw Error(ErrorCode::limit, "The plain-value nesting or node limit was exceeded.");
        --nodes;
    }
    void string(std::size_t bytes) {
        if (bytes > max_string_bytes || bytes > strings) throw Error(ErrorCode::limit, "The plain-value string limit was exceeded.");
        strings -= bytes;
    }
    void children(std::int64_t count) const {
        if (count < 0 || static_cast<std::uint64_t>(count) > nodes) throw Error(ErrorCode::limit, "The engine container exceeds the remaining node limit.");
    }
};

// These are explicit adapter string limits, not game rules. Reject a value
// rather than let an engine decoder normalize or truncate it.
void validate_string(std::string_view input) {
    for (std::size_t i = 0; i < input.size();) {
        const auto first = static_cast<unsigned char>(input[i++]);
        if (first == 0) throw Error(ErrorCode::invalid_string, "Embedded null bytes are outside this adapter's string profile.");
        if (first < 0x80) continue;
        unsigned scalar = 0, count = 0, minimum = 0;
        if (first >= 0xc2 && first <= 0xdf) { scalar = first & 0x1f; count = 1; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { scalar = first & 0x0f; count = 2; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { scalar = first & 7; count = 3; minimum = 0x10000; }
        else throw Error(ErrorCode::invalid_string, "The plain string is not valid UTF-8.");
        if (count > input.size() - i) throw Error(ErrorCode::invalid_string, "The UTF-8 sequence is incomplete.");
        for (unsigned j = 0; j < count; ++j) {
            const auto next = static_cast<unsigned char>(input[i++]);
            if ((next & 0xc0) != 0x80) throw Error(ErrorCode::invalid_string, "The UTF-8 continuation is invalid.");
            scalar = (scalar << 6) | (next & 0x3f);
        }
        if (scalar < minimum || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff))
            throw Error(ErrorCode::invalid_string, "The UTF-8 sequence is not a Unicode scalar.");
    }
}

template<class Function>
Function required(GDExtensionInterfaceGetProcAddress lookup, const char* name) {
    const auto address = lookup ? lookup(name) : nullptr;
    if (!address) throw Error(ErrorCode::missing_symbol, std::string("The required engine interface is unavailable: ") + name + '.');
    return reinterpret_cast<Function>(address);
}
}  // namespace

namespace detail {
struct Api;

struct NativeStorage {
    // The exported API records 24 bytes for a single-precision Variant and
    // 40 for double precision. Overallocate opaque storage; never use its size
    // as an engine-array stride. Every operation receives one aligned pointer.
    alignas(std::max_align_t) std::array<std::byte, 40> bytes{};
    std::shared_ptr<Api> api;
    bool initialized = false;
    explicit NativeStorage(std::shared_ptr<Api> functions) : api(std::move(functions)) {}
    ~NativeStorage();
    void* get() noexcept { return bytes.data(); }
};

struct Builtin {
    alignas(std::max_align_t) std::array<std::byte, 8> bytes{};
    GDExtensionPtrDestructor destroy = nullptr;
    bool initialized = false;
    explicit Builtin(GDExtensionPtrDestructor destructor) : destroy(destructor) {}
    ~Builtin() { if (initialized) destroy(bytes.data()); }
    Builtin(const Builtin&) = delete;
    Builtin& operator=(const Builtin&) = delete;
    void* get() noexcept { return bytes.data(); }
};

struct Api : std::enable_shared_from_this<Api> {
    GDExtensionInterfaceVariantNewNil nil;
    GDExtensionInterfaceVariantNewCopy copy;
    GDExtensionInterfaceVariantDestroy destroy;
    GDExtensionInterfaceVariantGetType type;
    GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
    GDExtensionInterfaceGetVariantToTypeConstructor to_type;
    GDExtensionInterfaceVariantConstruct construct;
    GDExtensionInterfaceVariantCall call;
    GDExtensionInterfaceVariantSet set;
    GDExtensionInterfaceVariantSetIndexed set_indexed;
    GDExtensionInterfaceVariantGet get;
    GDExtensionInterfaceVariantGetIndexed indexed;
    GDExtensionInterfaceStringNewWithUtf8CharsAndLen2 string_new;
    GDExtensionInterfaceStringToUtf8Chars string_utf8;
    GDExtensionInterfaceStringToUtf32Chars string_utf32;
    GDExtensionInterfaceStringNameNewWithUtf8Chars name_new;
    GDExtensionPtrDestructor string_destroy;
    GDExtensionPtrDestructor name_destroy;
    std::array<GDExtensionVariantFromTypeConstructorFunc, GDEXTENSION_VARIANT_TYPE_DICTIONARY + 1> writers{};
    std::array<GDExtensionTypeFromVariantConstructorFunc, GDEXTENSION_VARIANT_TYPE_DICTIONARY + 1> readers{};

    explicit Api(GDExtensionInterfaceGetProcAddress lookup) {
        const auto version_function = required<GDExtensionInterfaceGetGodotVersion2>(lookup, "get_godot_version2");
        GDExtensionGodotVersion2 version{};
        version_function(&version);
        if (version.major != 4 || version.minor != 7 || version.patch != 2 || !version.hash ||
            std::string_view(version.hash) != "ed1daf0bf001b61586d9930840f2f1394092c079")
            throw Error(ErrorCode::incompatible_engine, "The engine does not match the recorded native interface revision.");
        nil = required<GDExtensionInterfaceVariantNewNil>(lookup, "variant_new_nil");
        copy = required<GDExtensionInterfaceVariantNewCopy>(lookup, "variant_new_copy");
        destroy = required<GDExtensionInterfaceVariantDestroy>(lookup, "variant_destroy");
        type = required<GDExtensionInterfaceVariantGetType>(lookup, "variant_get_type");
        from_type = required<GDExtensionInterfaceGetVariantFromTypeConstructor>(lookup, "get_variant_from_type_constructor");
        to_type = required<GDExtensionInterfaceGetVariantToTypeConstructor>(lookup, "get_variant_to_type_constructor");
        construct = required<GDExtensionInterfaceVariantConstruct>(lookup, "variant_construct");
        call = required<GDExtensionInterfaceVariantCall>(lookup, "variant_call");
        set = required<GDExtensionInterfaceVariantSet>(lookup, "variant_set");
        set_indexed = required<GDExtensionInterfaceVariantSetIndexed>(lookup, "variant_set_indexed");
        get = required<GDExtensionInterfaceVariantGet>(lookup, "variant_get");
        indexed = required<GDExtensionInterfaceVariantGetIndexed>(lookup, "variant_get_indexed");
        string_new = required<GDExtensionInterfaceStringNewWithUtf8CharsAndLen2>(lookup, "string_new_with_utf8_chars_and_len2");
        string_utf8 = required<GDExtensionInterfaceStringToUtf8Chars>(lookup, "string_to_utf8_chars");
        string_utf32 = required<GDExtensionInterfaceStringToUtf32Chars>(lookup, "string_to_utf32_chars");
        name_new = required<GDExtensionInterfaceStringNameNewWithUtf8Chars>(lookup, "string_name_new_with_utf8_chars");
        const auto destructor = required<GDExtensionInterfaceVariantGetPtrDestructor>(lookup, "variant_get_ptr_destructor");
        string_destroy = destructor(GDEXTENSION_VARIANT_TYPE_STRING);
        name_destroy = destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
        if (!string_destroy || !name_destroy) throw Error(ErrorCode::missing_symbol, "An engine string destructor is unavailable.");
        for (const auto kind : {GDEXTENSION_VARIANT_TYPE_BOOL, GDEXTENSION_VARIANT_TYPE_INT,
                                GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_STRING}) {
            writers[kind] = from_type(kind);
            readers[kind] = to_type(kind);
            if (!writers[kind] || !readers[kind]) throw Error(ErrorCode::missing_symbol, "A typed engine scalar constructor is unavailable.");
        }
    }

    NativeValue fresh() { return NativeValue(std::make_unique<NativeStorage>(shared_from_this())); }

    NativeValue empty(GDExtensionVariantType kind) {
        auto result = fresh();
        GDExtensionCallError error{};
        construct(kind, result.get(), nullptr, 0, &error);
        result.storage_->initialized = true;
        if (error.error != GDEXTENSION_CALL_OK) throw Error(ErrorCode::engine_call, "The engine container constructor refused a value.");
        return result;
    }

    NativeValue method(GDExtensionVariantPtr self, const char* method_name,
                       const GDExtensionConstVariantPtr* args = nullptr, std::int64_t count = 0) {
        Builtin name(name_destroy);
        name_new(name.get(), method_name);
        name.initialized = true;
        auto result = fresh();
        GDExtensionCallError error{};
        call(self, name.get(), args, count, result.get(), &error);
        result.storage_->initialized = true;
        if (error.error != GDEXTENSION_CALL_OK) throw Error(ErrorCode::engine_call, "An engine container method refused a value.");
        return result;
    }

    template<class T> T scalar(GDExtensionVariantType kind, GDExtensionConstVariantPtr source) {
        T result{};
        readers[kind](&result, const_cast<void*>(source));
        return result;
    }

    std::string string(GDExtensionConstVariantPtr source, Budget& budget) {
        Builtin native(string_destroy);
        readers[GDEXTENSION_VARIANT_TYPE_STRING](native.get(), const_cast<void*>(source));
        native.initialized = true;
        const auto characters = string_utf32(native.get(), nullptr, 0);
        if (characters < 0 || static_cast<std::uint64_t>(characters) > max_string_bytes ||
            static_cast<std::uint64_t>(characters) > budget.strings)
            throw Error(ErrorCode::limit, "The native string exceeds the remaining string limit.");
        std::vector<char32_t> codepoints(static_cast<std::size_t>(characters));
        if (characters && string_utf32(native.get(), codepoints.data(), characters) != characters)
            throw Error(ErrorCode::engine_call, "The native string changed during scalar validation.");
        for (const auto scalar : codepoints)
            if (scalar == 0 || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff))
                throw Error(ErrorCode::invalid_string, "The native string is outside the supported Unicode profile.");
        const auto length = string_utf8(native.get(), nullptr, 0);
        if (length < 0) throw Error(ErrorCode::engine_call, "The engine reported an invalid string length.");
        budget.string(static_cast<std::size_t>(length));
        std::string result(static_cast<std::size_t>(length), '\0');
        if (length && string_utf8(native.get(), result.data(), length) != length)
            throw Error(ErrorCode::engine_call, "The engine string changed while being copied.");
        validate_string(result);
        return result;
    }

    std::int64_t size(GDExtensionConstVariantPtr source, Budget& budget) {
        auto result = method(const_cast<void*>(source), "size");
        if (type(result.get()) != GDEXTENSION_VARIANT_TYPE_INT) throw Error(ErrorCode::engine_call, "The engine container size is not an integer.");
        const auto count = scalar<std::int64_t>(GDEXTENSION_VARIANT_TYPE_INT, result.get());
        budget.children(count);
        return count;
    }

    NativeValue index(GDExtensionConstVariantPtr source, std::int64_t at) {
        auto result = fresh();
        GDExtensionBool valid = false, out_of_bounds = false;
        indexed(source, at, result.get(), &valid, &out_of_bounds);
        result.storage_->initialized = true;
        if (!valid || out_of_bounds) throw Error(ErrorCode::engine_call, "The engine container changed during indexed import.");
        return result;
    }

    values::Value read(GDExtensionConstVariantPtr source, Budget& budget, std::size_t depth) {
        if (!source) throw Error(ErrorCode::unsupported_type, "A missing Variant pointer is not a null value.");
        budget.enter(depth);
        switch (type(source)) {
            case GDEXTENSION_VARIANT_TYPE_NIL: return values::Value();
            case GDEXTENSION_VARIANT_TYPE_BOOL: return values::Value(scalar<GDExtensionBool>(GDEXTENSION_VARIANT_TYPE_BOOL, source) != 0);
            case GDEXTENSION_VARIANT_TYPE_INT: return values::Value(scalar<std::int64_t>(GDEXTENSION_VARIANT_TYPE_INT, source));
            case GDEXTENSION_VARIANT_TYPE_FLOAT: {
                const auto number = scalar<double>(GDEXTENSION_VARIANT_TYPE_FLOAT, source);
                if (!std::isfinite(number)) throw Error(ErrorCode::unsupported_type, "A nonfinite engine number is not plain data.");
                return values::Value(number);
            }
            case GDEXTENSION_VARIANT_TYPE_STRING: return values::Value(string(source, budget));
            case GDEXTENSION_VARIANT_TYPE_ARRAY: {
                const auto count = size(source, budget);
                values::Value::Array result;
                result.reserve(static_cast<std::size_t>(count));
                for (std::int64_t i = 0; i < count; ++i) {
                    auto child = index(source, i);
                    result.push_back(read(child.get(), budget, depth + 1));
                }
                return values::Value(std::move(result));
            }
            case GDEXTENSION_VARIANT_TYPE_DICTIONARY: {
                const auto count = size(source, budget);
                auto keys = method(const_cast<void*>(source), "keys");
                if (type(keys.get()) != GDEXTENSION_VARIANT_TYPE_ARRAY || size(keys.get(), budget) != count)
                    throw Error(ErrorCode::engine_call, "The engine dictionary changed during import.");
                values::Value::Object result;
                for (std::int64_t i = 0; i < count; ++i) {
                    auto key = index(keys.get(), i);
                    if (type(key.get()) != GDEXTENSION_VARIANT_TYPE_STRING)
                        throw Error(ErrorCode::unsupported_type, "Plain dictionaries require String keys, without key coercion.");
                    auto name = string(key.get(), budget);
                    auto child = fresh();
                    GDExtensionBool valid = false;
                    get(source, key.get(), child.get(), &valid);
                    child.storage_->initialized = true;
                    if (!valid) throw Error(ErrorCode::engine_call, "The engine dictionary changed during key import.");
                    if (!result.emplace(std::move(name), read(child.get(), budget, depth + 1)).second)
                        throw Error(ErrorCode::unsupported_type, "Distinct engine keys cannot collapse into one plain key.");
                }
                return values::Value(std::move(result));
            }
            default: throw Error(ErrorCode::unsupported_type, "The engine value is outside the supported plain-data types.");
        }
    }

    struct ExportSlot {
        std::string_view text;
        std::optional<NativeValue> retained;
        bool seen = false;
    };
    using ExportCache = std::array<ExportSlot, 512>;

    NativeValue write_string(std::string_view text, Budget& budget, ExportCache& cache) {
        budget.string(text.size());
        auto& slot = cache[std::hash<std::string_view>{}(text) % cache.size()];
        if (slot.seen && slot.text == text && slot.retained) {
            auto result = fresh();
            copy(result.get(), slot.retained->get());
            result.storage_->initialized = true;
            return result;
        }
        const bool repeated = slot.seen && slot.text == text;
        validate_string(text);
        Builtin native(string_destroy);
        const auto error = string_new(native.get(), text.data(), static_cast<std::int64_t>(text.size()));
        native.initialized = true;
        if (error != 0) throw Error(ErrorCode::invalid_string, "The engine refused the explicitly validated UTF-8 string.");
        const auto encoded_size = string_utf8(native.get(), nullptr, 0);
        if (encoded_size < 0 || static_cast<std::uint64_t>(encoded_size) != text.size())
            throw Error(ErrorCode::invalid_string, "The engine normalized the plain string instead of preserving it.");
        std::string encoded(text.size(), '\0');
        if ((encoded_size && string_utf8(native.get(), encoded.data(), encoded_size) != encoded_size) || encoded != text)
            throw Error(ErrorCode::invalid_string, "The engine changed the plain string during conversion.");
        auto result = fresh();
        writers[GDEXTENSION_VARIANT_TYPE_STRING](result.get(), native.get());
        result.storage_->initialized = true;
        if (repeated) {
            auto kept = fresh();
            copy(kept.get(), result.get());
            kept.storage_->initialized = true;
            slot.retained.emplace(std::move(kept));
        } else {
            slot.retained.reset();
            slot.text = text;
            slot.seen = true;
        }
        return result;
    }

    NativeValue write(const values::Value& value, Budget& budget, std::size_t depth, ExportCache& cache) {
        budget.enter(depth);
        if (value.type() == values::Type::string)
            return write_string(std::get<std::string>(value.storage()), budget, cache);
        auto result = fresh();
        switch (value.type()) {
            case values::Type::null:
                nil(result.get());
                result.storage_->initialized = true;
                return result;
            case values::Type::boolean: {
                GDExtensionBool number = std::get<bool>(value.storage()) ? 1 : 0;
                writers[GDEXTENSION_VARIANT_TYPE_BOOL](result.get(), &number);
                break;
            }
            case values::Type::integer: {
                auto number = std::get<values::Value::Integer>(value.storage());
                writers[GDEXTENSION_VARIANT_TYPE_INT](result.get(), &number);
                break;
            }
            case values::Type::floating: {
                auto number = std::get<double>(value.storage());
                if (!std::isfinite(number)) throw Error(ErrorCode::unsupported_type, "A nonfinite plain number cannot enter the engine.");
                writers[GDEXTENSION_VARIANT_TYPE_FLOAT](result.get(), &number);
                break;
            }
            case values::Type::string: break; // Handled before allocating the result.
            case values::Type::array: {
                const auto& children = std::get<values::Value::Array>(value.storage());
                budget.children(static_cast<std::int64_t>(children.size()));
                result = empty(GDEXTENSION_VARIANT_TYPE_ARRAY);
                auto length = fresh();
                auto count = static_cast<std::int64_t>(children.size());
                writers[GDEXTENSION_VARIANT_TYPE_INT](length.get(), &count);
                length.storage_->initialized = true;
                const GDExtensionConstVariantPtr resize_args[]{length.get()};
                auto resized = method(result.get(), "resize", resize_args, 1);
                if (type(resized.get()) != GDEXTENSION_VARIANT_TYPE_INT ||
                    scalar<std::int64_t>(GDEXTENSION_VARIANT_TYPE_INT, resized.get()) != 0)
                    throw Error(ErrorCode::engine_call, "The engine array refused its requested length.");
                for (std::size_t index = 0; index < children.size(); ++index) {
                    const auto& child = children[index];
                    auto item = write(child, budget, depth + 1, cache);
                    GDExtensionBool valid = false, out_of_bounds = false;
                    set_indexed(result.get(), static_cast<std::int64_t>(index), item.get(), &valid, &out_of_bounds);
                    if (!valid || out_of_bounds)
                        throw Error(ErrorCode::engine_call, "The engine array refused a typed item.");
                }
                return result;
            }
            case values::Type::object: {
                const auto& children = std::get<values::Value::Object>(value.storage());
                budget.children(static_cast<std::int64_t>(children.size()));
                result = empty(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
                for (const auto& [name, child] : children) {
                    // Keys consume the string quota, but not a value node.
                    if (depth + 1 > max_depth)
                        throw Error(ErrorCode::limit, "The plain-value nesting or node limit was exceeded.");
                    auto key = write_string(name, budget, cache);
                    auto item = write(child, budget, depth + 1, cache);
                    GDExtensionBool valid = false;
                    set(result.get(), key.get(), item.get(), &valid);
                    if (!valid) throw Error(ErrorCode::engine_call, "The engine dictionary refused a typed key or value.");
                }
                return result;
            }
        }
        result.storage_->initialized = true;
        return result;
    }
};

NativeStorage::~NativeStorage() { if (initialized) api->destroy(get()); }
}  // namespace detail

NativeValue::NativeValue(std::unique_ptr<detail::NativeStorage> storage) : storage_(std::move(storage)) {}
NativeValue::~NativeValue() = default;
NativeValue::NativeValue(NativeValue&&) noexcept = default;
NativeValue& NativeValue::operator=(NativeValue&&) noexcept = default;
GDExtensionVariantPtr NativeValue::get() noexcept { return storage_ ? storage_->get() : nullptr; }
GDExtensionConstVariantPtr NativeValue::get() const noexcept { return storage_ ? storage_->get() : nullptr; }
Boundary::Boundary(GDExtensionInterfaceGetProcAddress lookup) : api_(std::make_shared<detail::Api>(lookup)) {}
Boundary::~Boundary() = default;
values::Value Boundary::import_value(GDExtensionConstVariantPtr source) const {
    Budget budget;
    return api_->read(source, budget, 0);
}
NativeValue Boundary::export_value(const values::Value& source) const {
    Budget budget;
    detail::Api::ExportCache cache;
    return api_->write(source, budget, 0, cache);
}

}  // namespace factory::godot_values
