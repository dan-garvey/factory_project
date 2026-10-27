#include "codex_rpc.hpp"
#include "proof.hpp"
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>

using namespace factory::proof;
namespace {
std::string env(const char *key) {
  auto *value = std::getenv(key);
  return value ? value : "";
}
std::string trim(std::string text) {
  while (!text.empty() && (text.back() == '\n' || text.back() == '\r'))
    text.pop_back();
  return text;
}
std::string need(const std::map<std::string, std::string> &flags,
                 const std::string &key) {
  auto i = flags.find(key);
  require(i != flags.end() && !i->second.empty(), "Missing --" + key);
  return i->second;
}
Json beads_issue(const std::string &br, const fs::path &repo,
                 const std::string &id) {
  auto r = run({br, "show", id, "--json"}, repo);
  require(r.code == 0, "Cannot read owning Bead: " + r.output);
  auto start = r.output.find_first_of("[{");
  require(start != std::string::npos, "Malformed Beads response");
  auto result = Json::parse(r.output.substr(start));
  return result.is_array() ? result.at(0) : result;
}
} // namespace
int main(int argc, char **argv) {
  try {
    if (argc < 2 || std::string(argv[1]) == "--help") {
      std::cout
          << "factory-proof "
             "<submit|decide|deliver|status|gate|init|reconcile|declare-"
             "nonvisual> "
             "--root REPO [options]\n"
             "submit --manifest FILE uses CODEX_THREAD_ID; end your turn after "
             "submission.\n"
             "decide --id ID --decision FILE records the human decision.\n"
             "deliver --id ID queues notes and images to that exact "
             "originating thread.\n"
             "status --id ID reads once; do not poll from a waiting agent.\n"
             "gate --before COMMIT --after COMMIT checks final visual "
             "approvals.\n"
             "init --store ABSOLUTE_WINDOWS_MOUNT_PATH configures a private "
             "local store.\n"
             "reconcile --id ID reads the originating thread for a delivery "
             "receipt.\n"
             "check-connection checks the current thread without sending a "
             "message.\n";
      return 0;
    }
    std::string command = argv[1];
    std::map<std::string, std::string> flags;
    for (int i = 2; i < argc; i += 2) {
      require(i + 1 < argc && std::string(argv[i]).rfind("--", 0) == 0,
              "Expected --key value");
      require(flags.emplace(std::string(argv[i]).substr(2), argv[i + 1]).second,
              "Duplicate option");
    }
    fs::path repo = fs::canonical(need(flags, "root"));
    auto common = run({"git", "-C", repo.string(), "rev-parse",
                       "--path-format=absolute", "--git-common-dir"});
    require(common.code == 0, "Not a Git repository");
    fs::path config_path =
        fs::path(trim(common.output)) / "factory-proof" / "config.json";
    if (command == "init") {
      fs::path store(need(flags, "store"));
      require(store.is_absolute(), "Store must be absolute");
      fs::create_directories(store);
      require(!fs::exists(config_path), "Proof desk is already configured; "
                                        "review its existing configuration");
      write_json(
          config_path,
          Json{{"store", fs::canonical(store).string()},
               {"codex", env("HOME") + "/.local/bin/codex"},
               {"beads", env("HOME") + "/.local/bin/br"},
               {"socket", (env("CODEX_HOME").empty() ? env("HOME") + "/.codex"
                                                     : env("CODEX_HOME")) +
                              "/app-server-control/app-server-control.sock"}});
      std::cout << config_path << '\n';
      return 0;
    }
    auto config = read_json(config_path);
    fs::path store(config.at("store").get<std::string>());
    auto codex = config.at("codex").get<std::string>(),
         br = config.at("beads").get<std::string>();
    if (command == "check-connection") {
      auto result =
          codex_rpc(config.at("socket").get<std::string>(), "thread/goal/get",
                    Json{{"threadId", env("CODEX_THREAD_ID")}});
      std::cout << Json{{"connected", true},
                        {"goal_status", result.at("goal").is_null()
                                            ? Json("none")
                                            : result.at("goal").at("status")}}
                       .dump()
                << '\n';
    } else if (command == "submit") {
      auto m = read_json(need(flags, "manifest"));
      validate_manifest(m);
      auto issue = beads_issue(br, repo, m.at("bead"));
      require(issue.value("assignee", std::string()) == m.at("actor"),
              "Proof actor must own the Bead");
      require(issue.at("status") != "closed",
              "Cannot submit proof for closed work");
      auto result = submit(store, repo, m, env("CODEX_THREAD_ID"));
      auto id = result.at("id").get<std::string>();
      auto record =
          run({br, "comments", "add", m.at("bead"), "--actor", m.at("actor"),
               "--message",
               "Human visual review submitted: " + id +
                   ". Stage: " + m.at("stage").get<std::string>() +
                   ". Candidate: " + result.at("revision").get<std::string>() +
                   ". Required cases: " + std::to_string(m.at("cases").size()) +
                   ". Retained proof: " + (store / id).string() +
                   ". The originating agent is waiting exclusively for human "
                   "feedback; no polling or unrelated work."},
              repo);
      require(record.code == 0,
              "Bundle saved but Beads registration failed: " + record.output);
      write_json(store / id / "goal-wait.json",
                 pause_for_review(config, env("CODEX_THREAD_ID")));
      write_json(store / id / "registered.json", Json{{"registered", true}});
      std::cout << Json{{"id", id},
                        {"status", "waiting_for_human"},
                        {"message",
                         "End your turn now. The review app will deliver the "
                         "human decision as your next user message. Do not "
                         "poll or continue unrelated work."}}
                       .dump(2)
                << '\n';
    } else if (command == "declare-nonvisual") {
      auto declaration = read_json(need(flags, "manifest"));
      auto issue = beads_issue(br, repo, declaration.at("bead"));
      require(issue.value("assignee", std::string()) == declaration.at("actor"),
              "Scope actor must own the Bead");
      auto result = declare_nonvisual(store, repo, declaration);
      auto record = run({br, "comments", "add", declaration.at("bead"),
                         "--actor", declaration.at("actor"), "--message",
                         "Nonvisual source declaration for " +
                             result.at("revision").get<std::string>() + ": " +
                             declaration.at("reason").get<std::string>() +
                             ". Paths: " + declaration.at("paths").dump()},
                        repo);
      require(record.code == 0,
              "Nonvisual scope saved; Beads record failed: " + record.output);
      std::cout << result.dump(2) << '\n';
    } else if (command == "decide") {
      auto d =
          decide(store, need(flags, "id"), read_json(need(flags, "decision")));
      std::cout << d.dump(2) << '\n';
    } else if (command == "deliver") {
      auto id = need(flags, "id");
      require(id.find('/') == std::string::npos &&
                  id.find("..") == std::string::npos,
              "Invalid id");
      if (fs::exists(store / id / "delivery.json")) {
        auto old = read_json(store / id / "delivery.json");
        if (old.at("status") == "uncertain" || old.at("status") == "sending")
          require(reconcile_delivery(config, store / id),
                  "No originating-thread receipt was found. Delivery remains "
                  "uncertain; no duplicate was sent.");
      }
      auto state = deliver(store, repo, id, codex, br);
      if (state.at("status") == "delivered" &&
          fs::exists(store / id / "goal-wait.json"))
        resume_after_review(
            config, read_json(store / id / "manifest.json").at("thread"),
            read_json(store / id / "goal-wait.json"));
      std::cout << state.dump(2) << '\n';
      return state.at("status") == "delivered" ? 0 : 3;
    } else if (command == "status") {
      auto id = need(flags, "id");
      require(id.find('/') == std::string::npos &&
                  id.find("..") == std::string::npos,
              "Invalid id");
      std::cout << (fs::exists(store / id / "delivery.json")
                        ? read_json(store / id / "delivery.json")
                        : Json{{"status", "waiting_for_human"}})
                       .dump(2)
                << '\n';
    } else if (command == "gate") {
      check_gate(store, repo, need(flags, "before"), need(flags, "after"));
      std::cout << "Human visual approval gate passed.\n";
    } else if (command == "reconcile") {
      auto id = need(flags, "id");
      require(id.find('/') == std::string::npos &&
                  id.find("..") == std::string::npos,
              "Invalid id");
      require(reconcile_delivery(config, store / id),
              "No matching user-message receipt found; no message was resent");
      std::cout
          << "Delivery receipt reconciled; no duplicate message was sent.\n";
    } else
      throw std::runtime_error("Unknown command");
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "PROOF DESK: " << error.what() << '\n';
    return 1;
  }
}
