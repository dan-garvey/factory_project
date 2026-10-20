#include "factory/repair_workbench.hpp"
#include "factory/repair_scenarios.hpp"
#include "factory/geared_scenarios.hpp"
#include "factory/co_drive_scenarios.hpp"

#include <algorithm>
#include <charconv>
#include <exception>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace factory::repair_scenarios {
namespace {
namespace w = world;
namespace a = authority;
namespace s = stationary;
using I = a::Integer;
using V = values::Value;
using Tokens = std::vector<std::string>;

struct Host {
    const Definition& definition;
    w::Profile profile;
    std::unique_ptr<w::World> simulation;
    std::string context;
    I x{}, z{}, epoch{1}, request{};
    bool source_choice{};
};

bool integer(const std::string& text, I& value) {
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
}

Tokens tokenize(const std::string& line) {
    std::istringstream input(line);
    Tokens tokens;
    for (std::string token; input >> token;) tokens.push_back(std::move(token));
    return tokens;
}

const char* role_name(s::Role role) {
    switch (role) {
        case s::Role::collector: return "collector";
        case s::Role::belt: return "belt";
        case s::Role::processor: return "processor";
        case s::Role::waterwheel: return "waterwheel";
        case s::Role::gear: return "gear";
        case s::Role::shaft: return "shaft";
    }
    return "unknown";
}

void lot(std::ostream& out, std::string_view holder, const materials::WorkLot& work) {
    out << holder << " work=" << work.id << " remaining=" << work.remaining_ticks
        << " recipe_units=" << work.recipe.input_units_per_product << " cycle=" << work.recipe.cycle_ticks << '\n';
}

void status(const Host& host, const w::State& state, std::ostream& out) {
    const auto& stock = state.material.stock;
    const auto& cargo = state.material.cargo.at("P");
    const auto power = w::machine_power(state.topology);
    out << "Position (" << host.x << ",0," << host.z << "), reach " << host.profile.build_reach << ".\n"
        << "Stock source=" << stock.source << " collector=" << stock.collector << " belt=" << stock.belt
        << " input=" << stock.input << " output=" << stock.output << '\n'
        << "Power collector=" << power.collector << " belt=" << power.belt << " processor=" << power.processor << '\n';
    if (state.material.processing) lot(out, "Press", *state.material.processing);
    else out << "Press empty.\n";
    out << "Cargo raw=" << cargo.raw_units << " products=" << cargo.products << "/4\n";
    for (const auto& work : cargo.work_lots) lot(out, "Carried", work);
    if (host.source_choice) {
        const auto choice = co_drive_scenarios::inspect(state);
        out << "Source arrangement: " << co_drive_scenarios::mode_name(choice.mode) << "; registered sources=" << choice.sources << '\n';
    }
}

void inspect(const Host& host, std::ostream& out) {
    const auto state = host.simulation->snapshot().state;
    const auto power = s::power_view(state.topology);
    status(host, state, out);
    out << "Parts:\n";
    for (const auto& part : state.topology.parts) {
        const auto& geometry = part.geometry;
        out << "  " << geometry.id << " generation=" << part.generation << ' ' << role_name(part.role)
            << " at=" << geometry.center[0] << ',' << geometry.center[1] << ',' << geometry.center[2]
            << " axis=" << "xyz"[static_cast<unsigned>(geometry.axis)];
        if (part.role == s::Role::shaft) out << " half_span=" << geometry.half_span;
        if (part.role == s::Role::gear) out << " teeth=" << geometry.teeth;
        const auto motion = power.mechanical.motion.find(geometry.id);
        if (motion != power.mechanical.motion.end())
            out << " rotation=" << mechanics::motion_state_name(motion->second.state)
                << " rate=" << motion->second.rate.numerator << '/' << motion->second.rate.denominator;
        out << '\n';
    }
    out << "Material links:\n";
    for (const auto& link : state.topology.material_links)
        out << "  " << link.from.id << '@' << link.from.generation << " -> " << link.to.id << '@' << link.to.generation << '\n';
    out << "Carried parts:\n";
    for (const auto& [part, quantity] : state.kits.at("P")) {
        if (quantity == 0) continue;
        out << "  " << role_name(part.role) << " teeth=" << part.teeth << " half_span=" << part.half_span << " count=" << quantity << '\n';
    }
}

void help(std::ostream& out) {
    out << "inspect | hint | help | quit\n"
           "walk <east|west|north|south> [1..8] | wait [1..32]\n"
           "place shaft <x> <y> <z> <axis:x|y|z> <half_span>\n"
           "place gear <x> <y> <z> <axis:x|y|z> <teeth>\n"
           "link <from> <to> | remove <part> | drive <waterwheel> <on|off>\n"
           "collect <processor> [amount] | recover <machine>\n"
           "insert_raw <machine> <amount> | insert_work <processor> <work_id>\n"
           "North increases z. Walking stays on y=0 within x,z=-12..12.\n"
           "The drive switch controls all placed waterwheels.\n"
           "Only wait runs production. Inspect and hints preserve all work.\n";
}

bool target(a::Object& intent, const w::State& state, const std::string& id, bool destination, std::ostream& out) {
    const auto found = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [&](const auto& item) { return item.geometry.id == id; });
    if (found == state.topology.parts.end()) { out << "No current part named " << id << ".\n"; return false; }
    intent.emplace(destination ? "to" : "target", V(found->geometry.id));
    intent.emplace(destination ? "to_generation" : "generation", V(found->generation));
    return true;
}

enum class Step { keep, quit, failed };

Step act(Host& host, const Tokens& tokens, std::ostream& out, std::ostream& errors) {
    if (tokens.empty()) return Step::keep;
    const auto& verb = tokens[0];
    const auto syntax = [&] { out << "Invalid command. Type help for the syntax.\n"; return Step::keep; };
    if (verb == "help" || verb == "inspect" || verb == "hint" || verb == "quit") {
        if (tokens.size() != 1) return syntax();
        if (verb == "quit") return Step::quit;
        if (verb == "help") help(out);
        else if (verb == "hint") out << host.definition.hint << '\n';
        else inspect(host, out);
        return Step::keep;
    }
    if (verb == "walk" || verb == "wait") {
        const std::size_t base = verb == "walk" ? 2 : 1;
        I count{1};
        if (tokens.size() < base || tokens.size() > base + 1 ||
            (tokens.size() == base + 1 && !integer(tokens[base], count)) || count <= 0 ||
            count > (verb == "walk" ? 8 : 32)) return syntax();
        if (verb == "walk") {
            I x = host.x, z = host.z;
            if (tokens[1] == "east") x += count;
            else if (tokens[1] == "west") x -= count;
            else if (tokens[1] == "north") z += count;
            else if (tokens[1] == "south") z -= count;
            else return syntax();
            if (x < -12 || x > 12 || z < -12 || z > 12) { out << "The walk leaves this workbench. Position unchanged.\n"; return Step::keep; }
            if (host.epoch == std::numeric_limits<I>::max()) return Step::failed;
            host.x = x; host.z = z; ++host.epoch;
        } else {
            for (I tick = 0; tick < count; ++tick) {
                if (host.simulation->tick().error != w::TransactionError::none) {
                    errors << "Native production could not advance.\n"; return Step::failed;
                }
            }
            out << "Waited " << count << " ticks.\n";
        }
        status(host, host.simulation->snapshot().state, out);
        return Step::keep;
    }

    a::Object intent;
    const auto state = host.simulation->snapshot().state;
    if (verb == "place") {
        I x{}, y{}, z{}, dimension{};
        if (tokens.size() != 7 || (tokens[1] != "shaft" && tokens[1] != "gear") || !integer(tokens[2], x) || !integer(tokens[3], y) ||
            !integer(tokens[4], z) || !integer(tokens[6], dimension) ||
            (tokens[5] != "x" && tokens[5] != "y" && tokens[5] != "z")) return syntax();
        intent = {{"action", V("place")}, {"role", V(tokens[1])},
            {"center", V(V::Array{V(x), V(y), V(z)})}, {"axis", V(tokens[5])},
            {"teeth", V(tokens[1] == "gear" ? dimension : I{0})}, {"half_span", V(tokens[1] == "shaft" ? dimension : I{0})}};
    } else if (verb == "link") {
        if (tokens.size() != 3) return syntax();
        if (!target(intent, state, tokens[1], false, out) || !target(intent, state, tokens[2], true, out)) return Step::keep;
        intent.emplace("action", V("link"));
    } else if (verb == "collect" || verb == "recover" || verb == "remove" || verb == "insert_raw" || verb == "insert_work" || verb == "drive") {
        const bool parameter = verb == "insert_raw" || verb == "insert_work" || verb == "drive";
        const std::size_t minimum = parameter ? 3 : 2;
        const std::size_t maximum = verb == "collect" ? 3 : minimum;
        if (tokens.size() < minimum || tokens.size() > maximum) return syntax();
        I amount{1};
        if (verb == "drive") {
            if (tokens[2] != "on" && tokens[2] != "off") return syntax();
            intent.emplace("enabled", V(tokens[2] == "on"));
        } else if (parameter || tokens.size() == 3) {
            if (!integer(tokens[2], amount) || amount <= 0) return syntax();
        }
        if (!target(intent, state, tokens[1], false, out)) return Step::keep;
        intent.emplace("action", V(verb == "drive" ? std::string("set_drive") : verb));
        if (verb == "collect" || verb == "insert_raw") intent.emplace("amount", V(amount));
        if (verb == "insert_work") intent.emplace("work_id", V(amount));
    } else return syntax();

    if (host.request == std::numeric_limits<I>::max()) return Step::failed;
    intent.emplace("context", V(host.context));
    intent.emplace("client", V("repair-terminal"));
    intent.emplace("actor", V("P"));
    intent.emplace("request", V("action-" + std::to_string(++host.request)));
    const auto delivery = host.simulation->command({"P", "repair-terminal"}, intent,
        [&](const std::string& actor) -> std::optional<a::ActorCut> {
            return a::ActorCut{actor, {static_cast<double>(host.x), 0.0, static_cast<double>(host.z)},
                               host.epoch, true, host.profile.build_reach};
        });
    if (!delivery.completed()) { errors << "Native command could not complete.\n"; return Step::failed; }
    const auto& result = *delivery.result;
    const auto accepted = std::get<bool>(result.at("accepted").storage());
    out << (accepted ? "Accepted: " : "Held: ") << std::get<std::string>(result.at("reason").storage());
    const auto& entity = std::get<std::string>(result.at("entity").storage());
    if (!entity.empty()) out << " (" << entity << ')';
    out << '\n';
    status(host, host.simulation->snapshot().state, out);
    return Step::keep;
}
}  // namespace

int workbench(std::span<const std::string_view> arguments, std::istream& input, std::ostream& out, std::ostream& errors) {
    try {
        if (arguments.size() == 1 && (arguments[0] == "list" || arguments[0] == "help")) {
            out << "repair_workbench list | play <scenario>\n";
            for (const auto& entry : catalogue()) out << entry.id << ": " << entry.title << '\n';
            for (const auto& entry : geared_scenarios::catalogue()) out << entry.id << ": " << entry.title << '\n';
            for (const auto& entry : co_drive_scenarios::catalogue()) out << entry.id << ": " << entry.title << '\n';
            return out ? 0 : 2;
        }
        if (arguments.size() != 2 || arguments[0] != "play") {
            errors << "Usage: repair_workbench list | play <scenario>\n"; return 2;
        }
        auto content = make(arguments[1]);
        if (!content) content = geared_scenarios::make(arguments[1]);
        if (!content) content = co_drive_scenarios::make(arguments[1]);
        if (!content) { errors << "Unknown repair scenario. Use list.\n"; return 2; }
        const std::string context = "terminal-repair-" + std::string(content->definition->id);
        Host host{*content->definition, content->profile, w::World::create(context, content->profile, content->seed), context};
        host.source_choice = host.definition.id == co_drive_scenarios::definition().id;
        if (!host.simulation) { errors << "Native repair scenario could not start.\n"; return 2; }
        out << host.definition.title << '\n' << host.definition.objective << '\n'
            << "Type inspect to trace the line, help for actions, or hint if stuck.\n";
        inspect(host, out);
        for (std::string line;;) {
            out << "repair> " << std::flush;
            if (!out) return 2;
            if (!std::getline(input, line)) {
                if (input.bad() || !input.eof()) { errors << "Input failed.\n"; return 2; }
                out << "Unfinished.\n";
                return out ? 1 : 2;
            }
            if (line.size() > 512) { out << "Command too long. Work unchanged.\n"; continue; }
            const auto step = act(host, tokenize(line), out, errors);
            if (!out || step == Step::failed) return 2;
            if (step == Step::quit) { out << "Unfinished.\n"; return out ? 1 : 2; }
            const auto current = host.simulation->snapshot().state;
            if (current.material.cargo.at("P").products >= 4 &&
                (!host.source_choice || co_drive_scenarios::inspect(current).ready())) {
                out << (host.source_choice ? "Complete: source conflict repaired and four plates retrieved from the original finite stock.\n" :
                                             "Complete: four plates retrieved from the original finite stock.\n");
                return out ? 0 : 2;
            }
        }
    } catch (const std::exception&) {
        if (errors) errors << "Repair workbench could not continue.\n";
        return 2;
    }
}
}  // namespace factory::repair_scenarios
