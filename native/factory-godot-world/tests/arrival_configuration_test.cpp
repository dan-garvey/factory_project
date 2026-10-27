#include "native/factory-godot-world/src/arrival_configuration.hpp"

#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using factory::godot_world::make_arrival_configuration;
using factory::world::landing_deck_parts;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
}  // namespace

int main() {
    try {
        for (const auto& roster : {std::vector<std::string>{}, {"Q"}, {"P", "P"},
                 {"P", "R"}, {"P", "Q", "R"}})
            check(!make_arrival_configuration(true, false, roster),
                  "Invalid or duplicate workers must never receive starting content.");

        const auto generic = make_arrival_configuration(false, false, {"P", "Q"});
        check(generic && !generic->profile.landing_pod_center && !generic->seed.landing_pod &&
                  !generic->seed.fabrication_hub && generic->seed.foundations.empty() &&
                  !generic->profile.first_plate_unlock &&
                  !generic->profile.material.manual_ore && generic->profile.finite_parts.size() == 10,
              "The generic mechanics fixture retains its finite hardware without an arrival pod.");
        check(generic->seed.kits.at("P") == generic->profile.finite_parts &&
                  generic->seed.kits.at("Q").empty() &&
                  generic->seed.foundation_kits.at("P") == 24 &&
                  generic->seed.foundation_kits.at("Q") == 0,
              "The generic fixture grants its mechanical and foundation kits to P only.");

        const auto arrival = make_arrival_configuration(true, false, {"P", "Q"});
        check(arrival && arrival->profile.first_plate_unlock &&
                  arrival->profile.actors == std::set<std::string>{"P", "Q"} &&
                  arrival->profile.finite_parts.empty() && arrival->seed.kits.at("P").empty() &&
                  arrival->seed.kits.at("Q").empty(),
              "The normal arrival starts both workers before either has advanced machine parts.");
        check(arrival->seed.material.stock.source == arrival->profile.initial_units &&
                  arrival->profile.initial_units == 4096 &&
                  arrival->seed.material.timber_remaining.size() ==
                      arrival->profile.material.timber_sites.size() &&
                  arrival->profile.material.manual_ore->id == "opening-copper" &&
                  arrival->seed.material.cargo.size() == 2,
              "One finite native material ledger supplies the ore and all authored timber sites.");
        check(arrival->seed.landing_pod && arrival->seed.fabrication_hub &&
                  arrival->seed.foundations.size() == landing_deck_parts &&
                  arrival->seed.issued_entities.size() == landing_deck_parts + 2 &&
                  arrival->seed.foundation_kits.at("P") == 24 - landing_deck_parts &&
                  arrival->seed.foundation_kits.at("Q") == 0,
              "The pod, hub and nine issued deck panels consume only P's common foundation supply.");
        check(arrival->actor_starts.size() == 2 &&
                  arrival->actor_starts[0].first == "P" &&
                  arrival->actor_starts[1].first == "Q" &&
                  arrival->actor_starts[0].second != arrival->actor_starts[1].second,
              "P and Q keep separate native body starts on the shared deck.");

        const auto advanced = make_arrival_configuration(true, true, {"P", "Q"});
        check(advanced && !advanced->profile.first_plate_unlock &&
                  advanced->seed.material.stock.source == arrival->seed.material.stock.source &&
                  advanced->seed.issued_entities == arrival->seed.issued_entities &&
                  advanced->seed.foundations == arrival->seed.foundations &&
                  advanced->actor_starts == arrival->actor_starts &&
                  advanced->seed.kits == arrival->seed.kits,
              "The advanced fixture changes the first-plate gate without gifting or moving stock.");
        const auto solo = make_arrival_configuration(true, false, {"P"});
        check(solo && solo->profile.actors == std::set<std::string>{"P"} &&
                  solo->seed.material.cargo.size() == 1 && solo->actor_starts.size() == 1 &&
                  solo->seed.foundation_kits.size() == 1,
              "Solo arrival creates one worker with no unused second-worker custody.");
        std::cout << "Arrival configuration checks passed: " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Arrival configuration check failed: " << error.what() << '\n';
        return 1;
    }
}
