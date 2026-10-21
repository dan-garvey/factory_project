#include "tuft.hpp"

#include <algorithm>
#include <bit>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using factory::foliage::Bytes;
int checks = 0;
void verify(bool condition) {
    ++checks;
    if (!condition) throw std::runtime_error("Tuft control failed: " + std::to_string(checks));
}
void put_float(Bytes& bytes, std::size_t at, float value) {
    auto bits = std::bit_cast<std::uint32_t>(value);
    for (int n = 0; n < 4; ++n) bytes[at + n] = static_cast<std::uint8_t>(bits >> (n * 8));
}
Bytes header(unsigned extent, bool alpha) {
    Bytes bytes{137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 'I', 'H', 'D', 'R'};
    for (int dimension = 0; dimension < 2; ++dimension)
        for (int n = 3; n >= 0; --n) bytes.push_back(static_cast<std::uint8_t>(extent >> (n * 8)));
    bytes.push_back(8);
    bytes.push_back(alpha ? 6 : 2);
    bytes.resize(33);
    return bytes;
}
void rejected(const Bytes& geometry, const Bytes& color, const Bytes& normal, const Bytes& arm, bool fern = false) {
    try {
        (void)(fern ? factory::foliage::pack_fern : factory::foliage::pack_tuft)(geometry, color, normal, arm);
        verify(false);
    } catch (const std::runtime_error& error) {
        if (std::string(error.what()).starts_with("Tuft control failed")) throw;
        verify(true);
    }
}
}  // namespace

int main() {
    try {
        Bytes geometry(1006632);
        for (std::size_t i = 0; i < 1386; ++i) {
            put_float(geometry, 215508 + i * 12 + 4, 0.17f);
            put_float(geometry, 232140 + i * 12 + 4, 1.0f);
        }
        const auto color = header(384, true);
        const auto normal = header(256, false);
        const auto arm = header(256, false);
        const auto original = geometry;
        const auto packed = factory::foliage::pack_tuft(geometry, color, normal, arm);
        verify(geometry == original);
        verify(packed.size() > 52000 && packed.size() < 60000);
        verify(packed[0] == 'g' && packed[1] == 'l' && packed[2] == 'T' && packed[3] == 'F' && packed[4] == 2);
        std::string text(packed.begin() + 20, packed.end());
        verify(text.find("\"alphaMode\":\"MASK\"") != std::string::npos);
        verify(text.find("\"uri\"") == std::string::npos);
        verify(text.find("\"translation\"") == std::string::npos);
        verify(factory::foliage::pack_tuft(geometry, color, normal, arm) == packed);
        auto changed = geometry;
        changed.pop_back();
        rejected(changed, color, normal, arm);
        changed = geometry;
        put_float(changed, 215508, std::bit_cast<float>(0x7fc00000u));
        rejected(changed, color, normal, arm);
        changed = geometry;
        put_float(changed, 215508, 0.9f);
        rejected(changed, color, normal, arm);
        changed = geometry;
        put_float(changed, 232140 + 4, 0.2f);
        rejected(changed, color, normal, arm);
        changed = geometry;
        put_float(changed, 248772, -0.1f);
        rejected(changed, color, normal, arm);
        changed = geometry;
        changed[259860] = 0xff;
        changed[259861] = 0xff;
        rejected(changed, color, normal, arm);
        rejected(geometry, header(256, true), normal, arm);
        rejected(geometry, header(384, false), normal, arm);
        auto large = color;
        large.resize(650001);
        rejected(geometry, large, normal, arm);
        large.resize(600000);
        auto large_normal = normal;
        large_normal.resize(100000);
        rejected(geometry, large, large_normal, arm);
        Bytes fern(176176);
        for (std::size_t i = 0; i < 544; ++i) {
            put_float(fern, 131088 + i * 12, 0.24f);
            put_float(fern, 137616 + i * 12 + 4, 1.0f);
        }
        const auto fern_original = fern;
        const auto frond = factory::foliage::pack_fern(fern, color, normal, arm);
        verify(fern == fern_original && frond.size() > 23000 && frond.size() < 40000);
        const std::string fern_text(frond.begin() + 20, frond.end());
        verify(fern_text.find("\"count\":544") != std::string::npos && fern_text.find("\"count\":2352") != std::string::npos);
        verify(fern_text.find("\"name\":\"Fern02A\"") != std::string::npos && fern_text.find("\"uri\"") == std::string::npos);
        const auto json_bytes = std::uint32_t(frond[12]) | (std::uint32_t(frond[13]) << 8) |
            (std::uint32_t(frond[14]) << 16) | (std::uint32_t(frond[15]) << 24);
        verify(std::equal(fern.begin() + 131088, fern.begin() + 137616, frond.begin() + 28 + json_bytes));
        auto fern_changed = fern;
        fern_changed[0] = 0xff;
        verify(factory::foliage::pack_fern(fern_changed, color, normal, arm) == frond);
        fern_changed = fern;
        fern_changed.pop_back();
        rejected(fern_changed, color, normal, arm, true);
        rejected(geometry, color, normal, arm, true);
        rejected(fern, color, normal, arm);
        fern_changed = fern;
        put_float(fern_changed, 131088, std::bit_cast<float>(0x7fc00000u));
        rejected(fern_changed, color, normal, arm, true);
        fern_changed = fern;
        put_float(fern_changed, 131088, 0.75f);
        rejected(fern_changed, color, normal, arm, true);
        fern_changed = fern;
        put_float(fern_changed, 137616 + 4, 0.2f);
        rejected(fern_changed, color, normal, arm, true);
        fern_changed = fern;
        put_float(fern_changed, 144144, -0.1f);
        rejected(fern_changed, color, normal, arm, true);
        fern_changed = fern;
        fern_changed[148496] = 0xff;
        fern_changed[148497] = 0xff;
        rejected(fern_changed, color, normal, arm, true);
        std::cout << "Passed " << checks << " synthetic package controls. Image decode is tested separately.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
