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
    const auto manifestHash = digest(store / id / "manifest.json");
    refuses([&] { set_discarded(store, id, "stale-window", true); });
    ok(set_discarded(store, id, manifestHash, true).at("status") ==
       "discarded");
    ok(set_discarded(store, id, manifestHash, true).at("status") ==
       "discarded");
    ok(digest(store / id / "manifest.json") == manifestHash &&
       !fs::exists(store / id / "decision.json") &&
       !fs::exists(store / id / "delivery.json") &&
       !fs::exists(store / id / "beads-receipt.json"));
    refuses([&] { decide(store, id, reviewedDecision(id)); });
    refuses([&] { deliver(store, repo, id, "/not-called", "/not-called"); });
    ok(set_discarded(store, id, manifestHash, false).at("status") ==
       "waiting_for_human");
    ok(!fs::exists(store / id / "discarded.json"));
    refuses([&] { decide(store, id, decision()); });
    auto approval = decide(store, id, reviewedDecision(id));
    ok(approval.at("manifest_sha256") == digest(store / id / "manifest.json"));
    refuses([&] { decide(store, id, reviewedDecision(id)); });
    refuses([&] { set_discarded(store, id, manifestHash, true); });
    refuses([&] { set_discarded(store, id, manifestHash, false); });
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
    finalDecision["attachments"] = {(root / "media/view.png").string(),
                                    (root / "media/view.png").string()};
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
    auto fakeBr = root / "beads-spy";
    std::ofstream(fakeBr) << "#!/bin/sh\nexit 0\n";
    fs::permissions(fakeBr, fs::perms::owner_all);
    auto delivery =
        deliver(store, repo, finalId, "@missing-proof-peer", fakeBr.string());
    ok(delivery.at("status") == "failed");
    rpcState["queue_refuse"] = true;
    write_json(rpcFile, rpcState);
    delivery = deliver(store, repo, finalId, endpoint, fakeBr.string());
    ok(delivery.at("status") == "failed");
    ok(delivery.at("detail").get<std::string>().find(
           "Fixture rejected queue input") != std::string::npos);
    rpcState = read_json(rpcFile);
    ok(rpcState.value("queue", Json::array()).empty());
    rpcState["queue_refuse"] = false;
    rpcState["receipt_image_bytes"] = 18 * 1024 * 1024;
    rpcState["single_frame"] = true;
    write_json(rpcFile, rpcState);
    delivery = deliver(store, repo, finalId, endpoint, fakeBr.string());
    ok(delivery.at("status") == "delivered");
    rpcState = read_json(rpcFile);
    const auto queued = rpcState.at("queue").at(0);
    ok(queued.at("threadId") == "00000000-0000-0000-0000-000000000001");
    ok(queued.at("clientUserMessageId") == "factory-proof-" + decisionId);
    ok(queued.at("input")[0].at("text").get<std::string>().find("3420 ms") !=
       std::string::npos);
    // Even an approval with human notes/marks sends no image attachments.
    ok(queued.at("input").size() == 1);
    ok(queued.at("input")[0].at("text").get<std::string>().find("Side view") ==
       std::string::npos);
    deliver(store, repo, finalId, endpoint, fakeBr.string());
    ok(read_json(rpcFile).at("queue_calls") == 2);
    // Hydrated image receipts also work across large continuation frames, and
    // the transport still refuses an excessive declared size before allocation.
    rpcState = read_json(rpcFile);
    rpcState["single_frame"] = false;
    write_json(rpcFile, rpcState);
    const Json transportInput{{"threadId", "fixture-thread"},
                              {"clientUserMessageId", "large-receipt"},
                              {"input", Json::array()}};
    ok(codex_rpc(endpoint, "thread/queue/add", transportInput)
           .at("queuedSubmission")
           .at("clientUserMessageId") == "large-receipt");
    rpcState = read_json(rpcFile);
    rpcState["oversized_reply"] = true;
    write_json(rpcFile, rpcState);
    bool sizeRefused = false;
    try {
      codex_rpc(endpoint, "thread/queue/add", transportInput);
    } catch (const RpcFailure &error) {
      sizeRefused =
          error.may_have_submitted &&
          std::string(error.what()).find("64 MiB") != std::string::npos;
    }
    ok(sizeRefused);
    rpcState = read_json(rpcFile);
    rpcState.erase("receipt_image_bytes");
    rpcState.erase("single_frame");
    rpcState.erase("oversized_reply");
    // A lost acknowledgement must recover a pending queue receipt without
    // appending a second copy. A missing receipt must continue to refuse.
    rpcState["queue"] = Json::array();
    rpcState["drop_queue_reply"] = true;
    rpcState["list_image_bytes"] = 18 * 1024 * 1024;
    write_json(rpcFile, rpcState);
    write_json(store / finalId / "delivery.json", Json{{"status", "pending"}});
    delivery = deliver(store, repo, finalId, endpoint, fakeBr.string());
    ok(delivery.at("status") == "uncertain");
    refuses([&] { deliver(store, repo, finalId, endpoint, fakeBr.string()); });
    ok(reconcile_delivery(config, store / finalId));
    deliver(store, repo, finalId, endpoint, fakeBr.string());
    ok(read_json(rpcFile).at("queue_calls") == 5);
    rpcState = read_json(rpcFile);
    rpcState.erase("list_image_bytes");
    rpcState["drop_queue_reply"] = false;
    rpcState["queue"] = Json::array();
    write_json(rpcFile, rpcState);
    write_json(store / finalId / "delivery.json",
               Json{{"status", "uncertain"}});
    ok(!reconcile_delivery(config, store / finalId));
    refuses([&] { deliver(store, repo, finalId, endpoint, fakeBr.string()); });
    rpcState["items"][0]["item"]["type"] = "userMessage";
    rpcState["items"][0]["item"]["id"] = "human-receipt";
    write_json(rpcFile, rpcState);
    ok(reconcile_delivery(config, store / finalId));
    ok(read_json(store / finalId / "delivery.json").at("item") ==
       "human-receipt");
    rpcState["queue"] = {queued};
    rpcState["runtime_status"] = "active";
    write_json(rpcFile, rpcState);
    write_json(store / finalId / "delivery.json",
               Json{{"status", "delivered"},
                    {"queued_submission_id", queued.at("id")}});
    ok(start_queued_feedback(config, store / finalId));
    ok(read_json(rpcFile).value("start_calls", 0) == 0);
    rpcState["runtime_status"] = "idle";
    write_json(rpcFile, rpcState);
    ok(start_queued_feedback(config, store / finalId));
    ok(read_json(rpcFile).at("queue").empty());
    ok(read_json(rpcFile).at("start_calls") == 1);
    ok(read_json(store / finalId / "delivery.json").at("turn_id") ==
       "started-review-turn");
    ok(start_queued_feedback(config, store / finalId));
    ok(read_json(rpcFile).at("start_calls") == 1);
    auto feedback = [&](Json review) {
      auto bundle =
          submit(store, repo, m, "00000000-0000-0000-0000-000000000001");
      const auto proofId = bundle.at("id").get<std::string>();
      review["reviewed_manifest_sha256"] =
          digest(store / proofId / "manifest.json");
      decide(store, proofId, review);
      deliver(store, repo, proofId, endpoint, fakeBr.string());
      return read_json(rpcFile).at("queue").back().at("input");
    };
    auto compact = feedback(decision());
    const auto receipt = compact[0].at("text").get<std::string>();
    ok(compact.size() == 1 && receipt.size() < 400);
    ok(receipt.find("approved") != std::string::npos &&
       receipt.find("Candidate: " + candidate) != std::string::npos);
    ok(receipt.find("Shaft connection") == std::string::npos &&
       receipt.find("Cog drive") == std::string::npos &&
       receipt.find("/media/") == std::string::npos);
    auto rejection = decision();
    rejection["verdict"] = "changes_requested";
    rejection["cases"]["cogs"]["status"] = "changes_requested";
    rejection["cases"]["cogs"]["annotations"] = {annotation};
    rejection["attachments"] = {(root / "media/view.png").string(),
                                (root / "media/view.png").string()};
    auto marked = feedback(rejection);
    const auto markedText = marked[0].at("text").get<std::string>();
    ok(marked.size() == 2 && marked[1].at("type") == "localImage");
    ok(markedText.find("3420 ms") != std::string::npos &&
       markedText.find("cogs-motion.mp4") != std::string::npos);
    ok(markedText.find("shaft-view.png") == std::string::npos &&
       markedText.find("Shaft connection") == std::string::npos);
    ok(markedText.find("Wrong direction") ==
       markedText.rfind("Wrong direction"));
    auto unmarked = decision();
    unmarked["verdict"] = "changes_requested";
    unmarked["cases"]["shaft"]["status"] = "changes_requested";
    unmarked["cases"]["shaft"]["note"] = "Show the contact from the side";
    auto contextual = feedback(unmarked);
    ok(contextual.size() == 1);
    ok(contextual[0].at("text").get<std::string>().find("/media/") ==
       std::string::npos);
    ok(contextual[0].at("text").get<std::string>().find("Cog drive") ==
       std::string::npos);
    // Stale attachment paths without a corresponding human mark are not sent.
    unmarked["attachments"] = {(root / "media/view.png").string()};
    ok(feedback(unmarked).size() == 1);
    rejection["cases"]["shaft"]["status"] = "changes_requested";
    rejection["cases"]["shaft"]["note"] = "Text-only feedback needs no image";
    const auto mixed = feedback(rejection);
    ok(mixed.size() == 2 && mixed[0].at("text").get<std::string>().find(
                                "shaft-view.png") == std::string::npos);
    auto overall = decision();
    overall["verdict"] = "changes_requested";
    overall["note"] = "Please adjust the spacing consistently.";
    auto general = feedback(overall);
    ok(general.size() == 1);
    ok(general[0].at("text").get<std::string>().find(
           overall.at("note").get<std::string>()) != std::string::npos);
    // Refuse an unreceivable image echo before enqueueing or writing a Beads
    // receipt, leaving the immutable human decision available for recovery.
    const auto largeFrame = root / "media/large.png";
    std::ofstream(largeFrame) << "oversized marked frame fixture";
    fs::resize_file(largeFrame, 48ULL * 1024 * 1024);
    const auto tooLarge =
        submit(store, repo, m, "00000000-0000-0000-0000-000000000001")
            .at("id")
            .get<std::string>();
    auto largeReview = rejection;
    largeReview["attachments"] = {largeFrame.string()};
    largeReview["reviewed_manifest_sha256"] =
        digest(store / tooLarge / "manifest.json");
    decide(store, tooLarge, largeReview);
    const auto callsBefore = read_json(rpcFile).at("queue_calls");
    refuses([&] { deliver(store, repo, tooLarge, endpoint, fakeBr.string()); });
    ok(read_json(rpcFile).at("queue_calls") == callsBefore &&
       read_json(store / tooLarge / "delivery.json").at("status") ==
           "pending" &&
       !fs::exists(store / tooLarge / "beads-receipt.json"));
    // A discarded replacement cannot invalidate an earlier approved proof or
    // block a fresh replacement. Restore must not create competing branches.
    auto replacement = final;
    replacement["previous"] = finalId;
    auto replace = [&](const Json &manifest) {
      return submit(store, repo, manifest,
                    "00000000-0000-0000-0000-000000000001")
          .at("id")
          .get<std::string>();
    };
    auto discard = [&](const std::string &proofId, bool value = true) {
      return set_discarded(store, proofId,
                           digest(store / proofId / "manifest.json"), value);
    };
    const auto abandoned = replace(replacement);
    refuses([&] { check_gate(store, repo, baseline, candidate); });
    discard(abandoned);
    check_gate(store, repo, baseline, candidate);
    ++checks;
    const auto fresh = replace(replacement);
    refuses([&] { check_gate(store, repo, baseline, candidate); });
    refuses([&] { discard(abandoned, false); });
    replacement["previous"] = abandoned;
    refuses([&] { replace(replacement); });
    discard(fresh);
    discard(abandoned, false);
    refuses([&] { check_gate(store, repo, baseline, candidate); });
    discard(abandoned);
    const auto descendant = replace(replacement);
    // This active successor still supersedes the approved ancestor through
    // the discarded middle revision; discard never becomes approval.
    refuses([&] { check_gate(store, repo, baseline, candidate); });
    refuses([&] { discard(abandoned, false); });
    decide(store, descendant, reviewedDecision(descendant));
    check_gate(store, repo, baseline, candidate);
    ++checks;
    auto directionReplacement = m;
    directionReplacement["previous"] = id;
    const auto abandonedDirection = replace(directionReplacement);
    replacement["previous"] = descendant;
    refuses([&] { replace(replacement); });
    discard(abandonedDirection);
    const auto nextFinal = replace(replacement);
    discard(nextFinal);
    check_gate(store, repo, baseline, candidate);
    ++checks;
    const auto pending = replace(m);
    directionReplacement["previous"] = pending;
    const auto pendingReplacement = replace(directionReplacement);
    refuses([&] { decide(store, pending, reviewedDecision(pending)); });
    discard(pendingReplacement);
    decide(store, pending, reviewedDecision(pending));
    ok(!fs::exists(store / abandoned / "decision.json") &&
       !fs::exists(store / abandoned / "delivery.json"));
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
    refuses([&] {
      set_discarded(store, next_id, digest(store / next_id / "manifest.json"),
                    true);
    });
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
    // Antigravity Connect/HTTP transport and conversation delivery contracts.
    Json agyState{
        {"csrf_token", "fixture-csrf"},
        {"status", "CASCADE_RUN_STATUS_IDLE"},
        {"chunked_reply", true},
        {"steps",
         Json::array({Json{
             {"type", "CORTEX_STEP_TYPE_USER_INPUT"},
             {"status", "CORTEX_STEP_STATUS_DONE"},
             {"metadata", {{"executionId", "initial-user-step"}}},
             {"userInput",
              {{"items", Json::array({Json{{"text", "Initial prompt"}}})},
               {"userConfig",
                {{"plannerConfig",
                  {{"conversational", {{"plannerMode", 1}}}}}}},
               {"userAgentSpec", {{"agentId", "self"}}}}}}})}};
    const auto agyFile = root / "agy-state.json";
    write_json(agyFile, agyState);
    AntigravityRpcFixture agyServer(agyFile);
    const auto agyEndpoint = agyServer.endpoint();
    const Json agyConfig{{"socket", agyEndpoint}};
    refuses([&] {
      pause_for_review(Json{{"socket", agyServer.endpoint("wrong-csrf")}},
                       "00000000-0000-0000-0000-000000000002");
    });
    const auto agyPaused =
        pause_for_review(agyConfig, "00000000-0000-0000-0000-000000000002");
    ok(agyPaused.at("paused_by_review") == false &&
       agyPaused.at("runtime") == "antigravity");
    resume_after_review(agyConfig, "00000000-0000-0000-0000-000000000002",
                        agyPaused);
    const auto agyBundle =
        submit(store, repo, m, "00000000-0000-0000-0000-000000000002");
    const auto agyId = agyBundle.at("id").get<std::string>();
    auto agyReview = rejection;
    agyReview["attachments"] = {(root / "media/view.png").string()};
    agyReview["reviewed_manifest_sha256"] =
        digest(store / agyId / "manifest.json");
    const auto agyDecision = decide(store, agyId, agyReview);
    const auto agyDecisionId = agyDecision.at("id").get<std::string>();
    agyState["send_refuse"] = true;
    write_json(agyFile, agyState);
    auto agyDelivery =
        deliver(store, repo, agyId, agyEndpoint, fakeBr.string());
    ok(agyDelivery.at("status") == "failed" &&
       agyDelivery.at("detail").get<std::string>().find(
           "Fixture rejected cascade message") != std::string::npos);
    agyState = read_json(agyFile);
    ok(agyState.at("steps").size() == 1);
    agyState["send_refuse"] = false;
    write_json(agyFile, agyState);
    agyDelivery = deliver(store, repo, agyId, agyEndpoint, fakeBr.string());
    ok(agyDelivery.at("status") == "delivered");
    agyState = read_json(agyFile);
    ok(agyState.at("steps").size() == 2);
    const auto &sentStep = agyState.at("steps").back().at("userInput");
    ok(sentStep.at("deliveryStrategy") ==
       "MESSAGE_DELIVERY_STRATEGY_WHEN_IDLE");
    ok(sentStep.at("userConfig")
           .at("plannerConfig")
           .at("conversational")
           .at("plannerMode") == 1);
    ok(sentStep.at("userAgentSpec").at("agentId") == "self");
    ok(sentStep.at("items").at(0).at("text").get<std::string>().find(
           "[proof-decision:" + agyDecisionId + "]") != std::string::npos);
    ok(sentStep.at("media").size() == 1 &&
       sentStep.at("media").at(0).at("mimeType") == "image/png" &&
       !sentStep.at("media").at(0).at("inlineData").get<std::string>().empty());
    // Inline base64 media leaves the retained proof bundle's feedback PNG
    // untouched on disk.
    ok(fs::exists(store / agyId /
                  agyDecision.at("attachments").at(0).at("path")));
    // Oversized HTTP responses are refused before allocation.
    agyState["oversized_reply"] = true;
    write_json(agyFile, agyState);
    bool agyOversizedRefused = false;
    try {
      antigravity_rpc(
          agyEndpoint, "SendUserCascadeMessage",
          Json{{"cascadeId", "00000000-0000-0000-0000-000000000002"},
               {"items", Json::array()}});
    } catch (const RpcFailure &error) {
      agyOversizedRefused =
          error.may_have_submitted &&
          std::string(error.what()).find("64 MiB") != std::string::npos;
    }
    ok(agyOversizedRefused);
    // Dropped reply recovery reconciles against GetCascadeTrajectory without
    // sending a duplicate message or matching assistant/planner steps.
    agyState = read_json(agyFile);
    agyState.erase("oversized_reply");
    agyState["drop_send_reply"] = true;
    write_json(agyFile, agyState);
    write_json(store / agyId / "delivery.json", Json{{"status", "pending"}});
    agyDelivery = deliver(store, repo, agyId, agyEndpoint, fakeBr.string());
    ok(agyDelivery.at("status") == "uncertain");
    refuses([&] { deliver(store, repo, agyId, agyEndpoint, fakeBr.string()); });
    ok(reconcile_delivery(agyConfig, store / agyId));
    ok(read_json(store / agyId / "delivery.json").at("item") == "agy-step-4");
    const auto sendCallsAfterReconcile = read_json(agyFile).at("send_calls");
    deliver(store, repo, agyId, agyEndpoint, fakeBr.string());
    ok(read_json(agyFile).at("send_calls") == sendCallsAfterReconcile);
    // Assistant/planner steps echoing the marker never satisfy reconciliation.
    agyState = read_json(agyFile);
    agyState["drop_send_reply"] = false;
    agyState["steps"] = Json::array({Json{
        {"type", "CORTEX_STEP_TYPE_PLANNER_RESPONSE"},
        {"metadata", {{"executionId", "planner-step"}}},
        {"userInput",
         {{"items",
           Json::array({Json{
               {"text", "[proof-decision:" + agyDecisionId + "]"}}})}}}}});
    write_json(agyFile, agyState);
    write_json(store / agyId / "delivery.json", Json{{"status", "uncertain"}});
    ok(!reconcile_delivery(agyConfig, store / agyId));
    // Queued Antigravity steps reconcile and wait for idle before starting.
    agyState["status"] = "CASCADE_RUN_STATUS_RUNNING";
    agyState["queued_steps"] = Json::array({Json{
        {"type", "CORTEX_STEP_TYPE_USER_INPUT"},
        {"metadata", {{"executionId", "queued-agy-step"}}},
        {"userInput",
         {{"items",
           Json::array(
               {Json{{"text", "[proof-decision:" + agyDecisionId + "]"}}})}}}}});
    write_json(agyFile, agyState);
    ok(reconcile_delivery(agyConfig, store / agyId));
    ok(read_json(store / agyId / "delivery.json").at("queued_submission_id") ==
       "queued-agy-step");
    ok(start_queued_feedback(agyConfig, store / agyId));
    ok(read_json(agyFile).value("start_calls", 0) == 0);
    agyState = read_json(agyFile);
    agyState["status"] = "CASCADE_RUN_STATUS_IDLE";
    write_json(agyFile, agyState);
    ok(start_queued_feedback(agyConfig, store / agyId));
    ok(read_json(agyFile).at("start_calls") == 1 &&
       read_json(agyFile).at("queued_steps").empty());
    fs::remove_all(root);
    std::cout << "PROOF_CONTRACT_PASS " << checks << '\n';
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\nRetained test artifacts: " << root << '\n';
    return 1;
  }
}
