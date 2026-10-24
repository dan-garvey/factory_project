#pragma once

#include "factory/world.hpp"

#include <stdexcept>
#include <string>

namespace factory::world::tests {

// Existing construction fixtures need completed stock; harvest_world_test.cpp
// separately tests every start, contact, interruption, and retry boundary.
inline Delivery complete_manual_cut(World& world, const Binding& binding,
        const authority::Object& intent, const ObserveActor& observe) {
    using V = values::Value;
    auto started = world.command(binding, intent, observe);
    if (!started.completed() || !started.result ||
        !std::get<bool>(started.result->at("accepted").storage())) return started;
    for (V::Integer tick = 0; tick < manual_cut_ticks; ++tick) {
        const auto step = world.tick(observe);
        if (step.error != TransactionError::none)
            throw std::runtime_error("Native fixture cut could not advance.");
    }
    authority::Object finish = intent;
    finish.erase("target");
    finish.at("action") = V("finish_harvest");
    finish.at("request") = V("fixture-finish-" +
        std::get<std::string>(intent.at("request").storage()));
    auto completed = world.command(binding, finish, observe);
    if (!completed.completed() || !completed.result ||
        !std::get<bool>(completed.result->at("accepted").storage()))
        throw std::runtime_error("Native fixture cut did not complete at contact.");
    return completed;
}

}
