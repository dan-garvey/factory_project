#include "../proof.hpp"
#include "rpc_server.hpp"
#include <fstream>
#include <iostream>
using namespace factory::proof;
int main(int argc, char **argv) {
  if (argc != 5)
    return 2;
  auto root =
      fs::temp_directory_path() / ("factory-proof-hooks-" + identifier());
  try {
    auto repo = root / "repo", store = root / "store", hooks = root / "hooks";
    fs::create_directories(repo / "scripts");
    fs::create_directories(hooks);
    auto copy = [](const fs::path &a, const fs::path &b) {
      fs::copy_file(a, b);
      fs::permissions(b, fs::perms::owner_all);
    };
    auto tool = fs::canonical(argv[1]);
    copy(argv[2], hooks / "reference-transaction");
    copy(argv[3], hooks / "pre-push");
    copy(argv[4], repo / "scripts/check-visual-approval.sh");
    auto command = [&](std::vector<std::string> args) {
      auto r = run(args, repo);
      require(r.code == 0, r.output);
      return r.output;
    };
    auto git = [&](std::initializer_list<std::string> tail) {
      std::vector<std::string> args{"git"};
      args.insert(args.end(), tail);
      return command(args);
    };
    auto head = [&] {
      auto value = git({"rev-parse", "HEAD"});
      while (!value.empty() && value.back() == '\n')
        value.pop_back();
      return value;
    };
    git({"init", "-q", "-b", "main"});
    git({"config", "user.name", "Proof hook fixture"});
    git({"config", "user.email", "proof@example.invalid"});
    std::ofstream(repo / "view.tscn") << "original view\n";
    git({"add", "."});
    git({"commit", "-qm", "fixture baseline"});
    auto baseline = head();
    write_json(repo / ".git/factory-proof/config.json",
               Json{{"store", store.string()},
                    {"codex", "unused"},
                    {"beads", "unused"}});
    git({"config", "core.hooksPath", hooks.string()});
    git({"config", "factory.proofRequired", "true"});
    git({"config", "factory.proofExecutable", tool.string()});
    git({"config", "factory.proofSHA256", digest(tool)});
    git({"checkout", "-qb", "candidate"});
    std::ofstream(repo / "view.tscn") << "new shape\n";
    git({"add", "."});
    git({"commit", "-qm", "candidate visual"});
    auto candidate = head();
    require(
        run({"git", "update-ref", "refs/heads/main", candidate, baseline}, repo)
                .code != 0,
        "Unapproved main update was admitted");
    require(git({"rev-parse", "main"}) == baseline + "\n",
            "Main moved after failed approval");
    auto push = [&] {
      return run({"sh", "-c", "printf '%s\\n' \"$1\" | \"$2\"",
                  "proof-hook-test",
                  "refs/heads/candidate " + candidate + " refs/heads/main " +
                      baseline,
                  (hooks / "pre-push").string()},
                 repo)
          .code;
    };
    require(push() != 0, "Unapproved pre-push was admitted");
    fs::create_directories(root / "media");
    std::ofstream(root / "media/view.png") << "test image";
    Json m{{"schema", 1},
           {"title", "Hook fixture"},
           {"bead", "factory-fixture"},
           {"actor", "test"},
           {"stage", "direction"},
           {"paths", {"view.tscn"}},
           {"cases",
            Json::array({Json{
                {"id", "shape"},
                {"title", "Shape"},
                {"criteria", "Readable"},
                {"context", "Test fixture"},
                {"existing", false},
                {"media",
                 Json::array({Json{{"id", "view"},
                                   {"path", (root / "media/view.png").string()},
                                   {"kind", "image"},
                                   {"role", "concept"},
                                   {"caption", "Fixture"}}})}}})}};
    auto approve = [&](const std::string &id) {
      decide(store, id,
             Json{{"verdict", "approved"},
                  {"reviewed_manifest_sha256",
                   digest(store / id / "manifest.json")},
                  {"cases",
                   {{"shape",
                     {{"status", "approved"},
                      {"note",
                       "Isolated test decision; never human acceptance"}}}}}});
    };
    auto direction =
        submit(store, repo, m, "00000000-0000-0000-0000-000000000001");
    auto directionId = direction.at("id").get<std::string>();
    approve(directionId);
    m["stage"] = "final";
    m["direction"] = directionId;
    m["cases"][0]["media"][0]["role"] = "after";
    auto final = submit(store, repo, m, "00000000-0000-0000-0000-000000000001");
    const auto finalId = final.at("id").get<std::string>();
    const auto finalDir = store / finalId;
    write_json(finalDir / "goal-wait.json", Json{{"paused_by_review", true}});
    const auto goalWaitHash = digest(finalDir / "goal-wait.json");
    auto localAction = [&](const std::string &action) {
      return run({tool.string(), action, "--root", repo.string(), "--id",
                  finalId, "--manifest-sha256",
                  digest(finalDir / "manifest.json")},
                 repo);
    };
    // Config deliberately has no daemon socket and no usable Beads binary.
    // Both actions must work offline without messaging or changing a goal.
    const auto discarded = localAction("discard");
    require(discarded.code == 0 &&
                Json::parse(discarded.output).at("status") == "discarded",
            "Offline discard failed");
    require(!fs::exists(finalDir / "decision.json") &&
                !fs::exists(finalDir / "delivery.json") &&
                !fs::exists(finalDir / "beads-receipt.json"),
            "Discard created an approval or notification record");
    require(push() != 0, "Discard granted publication approval");
    require(digest(finalDir / "goal-wait.json") == goalWaitHash,
            "Discard changed the waiting goal record");
    const auto restored = localAction("restore");
    require(restored.code == 0 && !fs::exists(finalDir / "discarded.json") &&
                digest(finalDir / "goal-wait.json") == goalWaitHash,
            "Offline restore failed or changed the waiting goal record");
    approve(final.at("id"));
    require(localAction("discard").code != 0,
            "A submitted decision was discarded");
    require(localAction("restore").code != 0,
            "A submitted decision was restored");
    require(push() == 0, "Approved pre-push refused");
    git({"update-ref", "refs/heads/main", candidate, baseline});
    require(git({"rev-parse", "main"}) == candidate + "\n",
            "Approved main update failed");
    // End-to-end CLI test for Antigravity submit, session persistence, and
    // clean-environment WSL delivery.
    const auto fakeBr = root / "fake-br";
    std::ofstream(fakeBr)
        << "#!/bin/sh\n"
           "if [ \"$1\" = \"show\" ]; then\n"
           "  printf '[{\"id\":\"factory-fixture\",\"status\":\"in_progress\","
           "\"assignee\":\"test\"}]\\n'\n"
           "fi\n"
           "exit 0\n";
    fs::permissions(fakeBr, fs::perms::owner_all);
    write_json(repo / ".git/factory-proof/config.json",
               Json{{"store", store.string()},
                    {"socket", "/unused-codex-socket"},
                    {"beads", fakeBr.string()}});
    const auto agyStateFile = root / "agy-cli-state.json";
    write_json(agyStateFile,
               Json{{"csrf_token", "cli-csrf"},
                    {"status", "CASCADE_RUN_STATUS_IDLE"},
                    {"steps", Json::array()}});
    AntigravityRpcFixture agyServer(agyStateFile);
    const std::string agyAddr =
        "127.0.0.1:" + std::to_string(agyServer.port);
    const std::string agyThread = "00000000-0000-0000-0000-000000000009";
    auto runAgyCli = [&](const std::string &subcmd,
                         const std::string &extra = "") {
      return run({"sh", "-c",
                  "unset CODEX_THREAD_ID; "
                  "export ANTIGRAVITY_CONVERSATION_ID=" +
                      agyThread + " ANTIGRAVITY_LS_ADDRESS=" + agyAddr +
                      " ANTIGRAVITY_CSRF_TOKEN=cli-csrf; "
                      "exec \"$1\" " +
                      subcmd + " --root \"$2\" " + extra,
                  "agy-cli", tool.string(), repo.string()},
                 repo);
    };
    const auto connCheck = runAgyCli("check-connection");
    require(connCheck.code == 0 &&
                Json::parse(connCheck.output).at("runtime") == "antigravity",
            "Antigravity CLI check-connection failed: " + connCheck.output);
    const auto bothSet = run(
        {"sh", "-c",
         "export CODEX_THREAD_ID=" + agyThread +
             " ANTIGRAVITY_CONVERSATION_ID=" + agyThread +
             " ANTIGRAVITY_LS_ADDRESS=" + agyAddr +
             " ANTIGRAVITY_CSRF_TOKEN=cli-csrf; "
             "exec \"$1\" check-connection --root \"$2\"",
         "agy-both", tool.string(), repo.string()},
        repo);
    require(bothSet.code != 0,
            "CLI accepted simultaneous CODEX_THREAD_ID and "
            "ANTIGRAVITY_CONVERSATION_ID");
    m["stage"] = "direction";
    m.erase("direction");
    m["cases"][0]["media"][0]["role"] = "concept";
    const auto manifestFile = root / "agy-manifest.json";
    write_json(manifestFile, m);
    const auto subOut =
        runAgyCli("submit", "--manifest \"" + manifestFile.string() + "\"");
    require(subOut.code == 0, "Antigravity CLI submit failed: " + subOut.output);
    const auto cliBundleId =
        Json::parse(subOut.output).at("id").get<std::string>();
    const auto decisionFile = root / "agy-decision.json";
    write_json(decisionFile,
               Json{{"verdict", "approved"},
                    {"reviewed_manifest_sha256",
                     digest(store / cliBundleId / "manifest.json")},
                    {"cases",
                     {{"shape",
                       {{"status", "approved"}, {"note", "CLI approval"}}}}}});
    require(run({tool.string(), "decide", "--root", repo.string(), "--id",
                 cliBundleId, "--decision", decisionFile.string()},
                repo)
                    .code == 0,
            "Antigravity CLI decide failed");
    const auto wslDeliver = run(
        {"sh", "-c",
         "unset CODEX_THREAD_ID ANTIGRAVITY_CONVERSATION_ID "
         "ANTIGRAVITY_LS_ADDRESS ANTIGRAVITY_CSRF_TOKEN; "
         "exec \"$1\" deliver --root \"$2\" --id \"$3\"",
         "wsl-deliver", tool.string(), repo.string(), cliBundleId},
        repo);
    require(wslDeliver.code == 0 &&
                Json::parse(wslDeliver.output).at("status") == "delivered" &&
                read_json(agyStateFile).at("steps").size() == 1,
            "Clean-environment WSL delivery to Antigravity failed: " +
                wslDeliver.output);
    fs::remove_all(root);
    std::cout << "PROOF_HOOKS_PASS 17\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\nRetained: " << root << '\n';
    return 1;
  }
}
