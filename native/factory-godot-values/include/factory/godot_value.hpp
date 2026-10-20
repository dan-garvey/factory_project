#pragma once

#include "factory/value.hpp"
#include "gdextension_interface.h"

#include <memory>
#include <stdexcept>
#include <string>

namespace factory::godot_values {

enum class ErrorCode { missing_symbol, incompatible_engine, unsupported_type, invalid_string, limit, engine_call };

class Error : public std::runtime_error {
public:
    Error(ErrorCode code, const std::string& message) : std::runtime_error(message), code_(code) {}
    [[nodiscard]] ErrorCode code() const noexcept { return code_; }
private:
    ErrorCode code_;
};

namespace detail { struct Api; struct NativeStorage; }

// An owned engine Variant. Destroy all instances before the engine shuts down.
// Moving transfers ownership; importing never borrows its containers.
class NativeValue {
public:
    ~NativeValue();
    NativeValue(NativeValue&&) noexcept;
    NativeValue& operator=(NativeValue&&) noexcept;
    NativeValue(const NativeValue&) = delete;
    NativeValue& operator=(const NativeValue&) = delete;
    [[nodiscard]] GDExtensionVariantPtr get() noexcept;
    [[nodiscard]] GDExtensionConstVariantPtr get() const noexcept;
private:
    explicit NativeValue(std::unique_ptr<detail::NativeStorage>);
    std::unique_ptr<detail::NativeStorage> storage_;
    friend struct detail::Api;
};

class Boundary {
public:
    explicit Boundary(GDExtensionInterfaceGetProcAddress);
    ~Boundary();
    Boundary(const Boundary&) = delete;
    Boundary& operator=(const Boundary&) = delete;

    [[nodiscard]] values::Value import_value(GDExtensionConstVariantPtr) const;
    [[nodiscard]] NativeValue export_value(const values::Value&) const;

private:
    std::shared_ptr<detail::Api> api_;
};

}  // namespace factory::godot_values
