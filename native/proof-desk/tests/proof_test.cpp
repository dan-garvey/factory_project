#include "../codex_rpc.hpp"
#include "../proof.hpp"
#include "rpc_server.hpp"
#include <fstream>
#include <iostream>
#include <unistd.h>
using namespace factory::proof;
int checks = 0;
void ok(bool value) {
  ++checks;
  require(value, "Assertion " + std::to_string(checks) + " failed");
}
template <class F> void refuses(F work) {
  bool failed = false;
  try {
    work();
  } catch (const std::exception &) {
    failed = true;
  }
  ok(failed);
}
Json sample() {
  return Json{
      {"schema", 1},
      {"title", "Crank"},
      {"bead", "factory-test"},
      {"actor", "test"},
      {"stage", "direction"},
      {"paths", {"component.cpp"}},
      {"cases",
       Json::array(
           {Json{{"id", "shaft"},
                 {"title", "Shaft connection"},
                 {"criteria", "Contact is clear"},
                 {"context", "Player view"},
                 {"existing", true},
                 {"media", Json::array({Json{{"id", "view"},
                                             {"path", "/tmp/view.png"},
                                             {"kind", "image"},
                                             {"role", "concept"},
                                             {"caption", "Side view"}}})}},
            Json{{"id", "cogs"},
                 {"title", "Cog drive"},
                 {"criteria", "Cogs turn"},
                 {"context", "Whole assembly"},
                 {"existing", false},
                 {"media",
                  Json::array({Json{{"id", "motion"},
                                    {"path", "/tmp/motion.mp4"},
                                    {"kind", "clip"},
                                    {"role", "concept"},
                                    {"caption", "Full rotation"}}})}}})}};
}
Json decision() {
  return Json{{"verdict", "approved"},
              {"cases",
               {{"shaft", {{"status", "approved"}, {"note", ""}}},
                {"cogs", {{"status", "approved"}, {"note", ""}}}}}};
}
int main() {
  auto root =
      fs::temp_directory_path() / ("factory-proof-test-" + identifier());
  try {
    auto m = sample();
    validate_manifest(m);
    ++checks;
    auto d = decision();
    validate_decision(m, d);
    ++checks;
    auto bad = m;
    bad["cases"][1]["id"] = "shaft";
    refuses([&] { validate_manifest(bad); });
    bad = m;
    bad["cases"][0]["media"] = Json::array();
    refuses([&] { validate_manifest(bad); });
    bad = m;
    bad["stage"] = "final";
    refuses([&] { validate_manifest(bad); });
    bad["cases"][0]["media"][0]["role"] = "after";
    bad["cases"][1]["media"][0]["role"] = "after";
    refuses([&] { validate_manifest(bad); });
    auto before = bad["cases"][0]["media"][0];
    before["id"] = "before";
    before["role"] = "before";
    bad["cases"][0]["media"].push_back(before);
    validate_manifest(bad);
    ++checks;
    d["cases"]["cogs"]["status"] = "unreviewed";
    refuses([&] { validate_decision(m, d); });
    d = decision();
    d["cases"].erase("cogs");
    refuses([&] { validate_decision(m, d); });
    d = decision();
    d["verdict"] = "changes_requested";
    d["cases"]["cogs"]["status"] = "changes_requested";
    refuses([&] { validate_decision(m, d); });
    d["cases"]["cogs"]["note"] = "Show the second cog";
    validate_decision(m, d);
    ++checks;
    auto annotation = Json{{"media", "motion"}, {"text", "Wrong direction"},
                           {"x", .4},           {"y", .3},
                           {"end_x", .5},       {"end_y", .6},
                           {"time_ms", 3420}};
    d["cases"]["cogs"]["annotations"] = {annotation};
    validate_decision(m, d);
    ++checks;
    d["cases"]["cogs"]["annotations"][0]["x"] = 1.2;
    refuses([&] { validate_decision(m, d); });
    ok(digest_text("abc") ==
       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    fs::create_directories(root / "repo");
    fs::create_directories(root / "media");
    Json rpcState{{"goal",
                   {{"status", "active"},
                    {"objective", "Fixture objective"},
                    {"createdAt", 1},
                    {"tokensUsed", 42},
                    {"tokenBudget", 100}}},
                  {"items", Json::array()}};
    auto rpcFile = root / "rpc-state.json";
    write_json(rpcFile, rpcState);
    auto endpoint = "@factory-proof-test-" + identifier();
    RpcFixture rpcServer(endpoint, rpcFile);
    Json config{{"codex", "unused"}, {"socket", endpoint}};
    rpcState["bad_upgrade"] = true;
    write_json(rpcFile, rpcState);
    refuses([&] { pause_for_review(config, "fixture-thread"); });
    ok(read_json(rpcFile).at("goal").at("status") == "active");
    rpcState.erase("bad_upgrade");
    write_json(rpcFile, rpcState);
    auto paused = pause_for_review(config, "fixture-thread");
    ok(paused.at("paused_by_review") == true);
    ok(read_json(rpcFile).at("goal").at("status") == "paused");
    resume_after_review(config, "fixture-thread", paused);
    ok(read_json(rpcFile).at("goal").at("status") == "active");
    ok(read_json(rpcFile).at("goal").at("tokensUsed") == 42);
    rpcState["goal"]["status"] = "budgetLimited";
    write_json(rpcFile, rpcState);
    resume_after_review(config, "fixture-thread", paused);
    ok(read_json(rpcFile).at("goal").at("status") == "budgetLimited");
    rpcState["goal"]["status"] = "paused";
    rpcState["goal"]["objective"] = "Different goal";
    write_json(rpcFile, rpcState);
    resume_after_review(config, "fixture-thread", paused);
    ok(read_json(rpcFile).at("goal").at("status") == "paused");
    auto repo = root / "repo", store = root / "store";
    ok(run({"git", "init", "-q"}, repo).code == 0);
    ok(run({"git", "config", "user.email", "proof-test@example.invalid"}, repo)
           .code == 0);
    ok(run({"git", "config", "user.name", "Proof Test"}, repo).code == 0);
    std::ofstream(repo / "component.cpp") << "int component = 1;\n";
    std::ofstream(repo / "view.tscn") << "baseline view\n";
    ok(run({"git", "add", "."}, repo).code == 0);
    ok(run({"git", "-c", "core.hooksPath=/dev/null", "commit", "-qm",
            "test fixture"},
           repo)
           .code == 0);
    auto revisionId = [&] {
      auto value = run({"git", "rev-parse", "HEAD"}, repo).output;
      while (!value.empty() && value.back() == '\n')
        value.pop_back();
      return value;
    };
    auto commitAll = [&] {
      ok(run({"git", "add", "."}, repo).code == 0);
      ok(run({"git", "-c", "core.hooksPath=/dev/null", "commit", "-qm",
              "isolated test change"},
             repo)
             .code == 0);
    };
    auto baseline = revisionId();
    std::ofstream(root / "media/view.png") << "fixture image";
    std::ofstream(root / "media/motion.mp4") << "fixture video";
    m["cases"][0]["media"][0]["path"] = (root / "media/view.png").string();
    m["cases"][1]["media"][0]["path"] = (root / "media/motion.mp4").string();
    m["paths"].push_back("view.tscn");
    auto submitted =
        submit(store, repo, m, "00000000-0000-0000-0000-000000000001");
    auto id = submitted.at("id").get<std::string>();
    ok(submitted.at("source_inputs").contains("component.cpp"));
    verify_media(store / id, submitted);
    ++checks;
    auto reviewedDecision = [&](const std::string &proofId) {
      auto value = decision();
      value["reviewed_manifest_sha256"] =
          digest(store / proofId / "manifest.json");
      return value;
    };
    refuses([&] { decide(store, id, decision()); });
    auto approval = decide(store, id, reviewedDecision(id));
    ok(approval.at("manifest_sha256") == digest(store / id / "manifest.json"));
    refuses([&] { decide(store, id, reviewedDecision(id)); });
    auto final = m;
    final["stage"] = "final";
    final["direction"] = id;
    for (auto &c : final["cases"])
      for (auto &media : c["media"])
        media["role"] = "after";
    before = final["cases"][0]["media"][0];
    before["id"] = "before";
    before["role"] = "before";
    final["cases"][0]["media"].push_back(before);
    std::ofstream(repo / "view.tscn") << "candidate view\n";
    commitAll();
    auto candidate = revisionId();
    refuses([&] { check_gate(store, repo, baseline, candidate); });
    auto result =
        submit(store, repo, final, "00000000-0000-0000-0000-000000000001");
    ok(result.at("stage") == "final");
    auto finalId = result.at("id").get<std::string>();
    auto finalDecision = reviewedDecision(finalId);
    finalDecision["cases"]["cogs"]["annotations"] = {annotation};
    finalDecision["attachments"] = {(root / "media/view.png").string()};
    decide(store, finalId, finalDecision);
    ok(!reconcile_delivery(config, store / finalId));
    auto decisionId = read_json(store / finalId / "decision.json")
                          .at("id")
                          .get<std::string>();
    rpcState["items"] = {Json{
        {"item",
         {{"id", "assistant-copy"},
          {"type", "agentMessage"},
          {"content", Json::array({Json{{"type", "text"},
                                        {"text", "[proof-decision:" +
                                                     decisionId + "]"}}})}}}}};
    write_json(rpcFile, rpcState);
    ok(!reconcile_delivery(config, store / finalId));
    check_gate(store, repo, baseline, candidate);
    ++checks;
    // Shell metacharacters are literal user feedback, never command text.
    auto fakeQueue = root / "queue-spy";
    auto fakeBr = root / "beads-spy";
    std::ofstream(fakeQueue)
        << "#!/bin/sh\nprintf 'call\\n' >> '" << (root / "queue-calls").string()
        << "'\nprintf '%s\\0' \"$@\" > '" << (root / "queue-args").string()
        << "'\n";
    std::ofstream(fakeBr) << "#!/bin/sh\nexit 0\n";
    fs::permissions(fakeQueue, fs::perms::owner_all);
    fs::permissions(fakeBr, fs::perms::owner_all);
    auto delivery =
        deliver(store, repo, finalId, fakeQueue.string(), fakeBr.string());
    ok(delivery.at("status") == "delivered");
    std::ifstream argsIn(root / "queue-args", std::ios::binary);
    std::string args((std::istreambuf_iterator<char>(argsIn)), {});
    ok(args.find("00000000-0000-0000-0000-000000000001") != std::string::npos);
    ok(args.find("3420 ms") != std::string::npos);
    ok(args.find("--image") != std::string::npos);
    ok(args.find("proof-decision:") != std::string::npos);
    deliver(store, repo, finalId, fakeQueue.string(), fakeBr.string());
    std::ifstream callsIn(root / "queue-calls");
    std::string calls((std::istreambuf_iterator<char>(callsIn)), {});
    ok(calls == "call\n");
    rpcState["items"][0]["item"]["type"] = "userMessage";
    rpcState["items"][0]["item"]["id"] = "human-receipt";
    write_json(rpcFile, rpcState);
    ok(reconcile_delivery(config, store / finalId));
    ok(read_json(store / finalId / "delivery.json").at("item") ==
       "human-receipt");
    // Disjoint changes can reuse approval; a changed visual input cannot.
    std::ofstream(repo / "unrelated.txt") << "unrelated\n";
    commitAll();
    check_gate(store, repo, baseline, revisionId());
    ++checks;
    std::ofstream(repo / "view.tscn") << "unreviewed geometry\n";
    commitAll();
    refuses([&] { check_gate(store, repo, baseline, revisionId()); });
    Json scope{{"bead", "factory-test"},
               {"actor", "test"},
               {"reason", "Nonvisual operation only"},
               {"paths", {"view.tscn"}}};
    refuses([&] { declare_nonvisual(store, repo, scope); });
    fs::create_directories(repo / "native");
    std::ofstream(repo / "native/helper.cpp") << "int helper=1;\n";
    commitAll();
    auto nativeBefore = revisionId();
    std::ofstream(repo / "native/helper.cpp") << "int helper=2;\n";
    commitAll();
    auto nativeAfter = revisionId();
    refuses([&] { check_gate(store, repo, nativeBefore, nativeAfter); });
    scope["paths"] = {"native/helper.cpp"};
    declare_nonvisual(store, repo, scope);
    check_gate(store, repo, nativeBefore, nativeAfter);
    ++checks;
    std::ofstream(repo / "native/helper.cpp") << "int helper=3;\n";
    commitAll();
    refuses([&] { check_gate(store, repo, nativeBefore, revisionId()); });
    fs::remove(repo / "view.tscn");
    commitAll();
    ok(source_inputs(repo, revisionId(), Json::array({"view.tscn"}))
           .at("view.tscn")
           .is_null());
    final["cases"].erase(final["cases"].begin() + 1);
    refuses([&] {
      submit(store, repo, final, "00000000-0000-0000-0000-000000000001");
    });
    // A stale open reviewer cannot approve a replaced revision.
    auto revision = m;
    revision["previous"] = id;
    auto next =
        submit(store, repo, revision, "00000000-0000-0000-0000-000000000001");
    auto next_id = next.at("id").get<std::string>();
    revision["previous"] = next_id;
    submit(store, repo, revision, "00000000-0000-0000-0000-000000000001");
    refuses([&] { decide(store, next_id, reviewedDecision(next_id)); });
    // A transport ambiguity never causes automatic duplicate delivery.
    write_json(store / id / "delivery.json", Json{{"status", "sending"}});
    refuses([&] { deliver(store, repo, id, "/not-called", "/not-called"); });
    // Tampering invalidates the entire proof even after approval.
    std::ofstream(store / id / "media/shaft-view.png") << "changed";
    refuses([&] { verify_media(store / id, submitted); });
    refuses([&] { submit(store, repo, final, "not-a-thread"); });
    ok(visual_path("experiments/opening/item.tscn"));
    ok(!visual_path("docs/example.md"));
    auto timed = run({"sh", "-c", "sleep 3"}, {}, 1);
    ok(timed.code == 124);
    fs::remove_all(root);
    std::cout << "PROOF_CONTRACT_PASS " << checks << '\n';
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\nRetained test artifacts: " << root << '\n';
    return 1;
  }
}
