#include "../proof.hpp"
#include <fstream>
#include <iostream>
#include <unistd.h>

using namespace factory::proof;
namespace {
int checks = 0;
void ok(bool value) {
  ++checks;
  require(value, "Composition assertion " + std::to_string(checks) + " failed");
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
Json proof_case(const std::string &id, const fs::path &image,
                bool final_stage) {
  Json media = Json::array({Json{{"id", "after"},
                                 {"path", image.string()},
                                 {"kind", "image"},
                                 {"role", final_stage ? "after" : "concept"},
                                 {"caption", "Source-matched fixture view"}}});
  if (final_stage)
    media.push_back(Json{{"id", "before"},
                         {"path", image.string()},
                         {"kind", "image"},
                         {"role", "before"},
                         {"caption", "Existing worksite"}});
  return Json{{"id", id},
              {"title", id},
              {"criteria", "Preserve the reviewed component"},
              {"context", "Whole worksite fixture"},
              {"existing", true},
              {"media", media}};
}
Json manifest(const fs::path &image, bool replacement, bool final_stage) {
  Json cases = Json::array();
  if (!replacement)
    cases.push_back(proof_case("foundation", image, final_stage));
  cases.push_back(
      proof_case(replacement ? "compact-press" : "press", image, final_stage));
  return Json{{"schema", 1},
              {"title", replacement ? "Corrected press" : "Original worksite"},
              {"bead", "factory-test"},
              {"actor", "test"},
              {"stage", final_stage ? "final" : "direction"},
              {"paths", replacement
                            ? Json::array({"native/press.cpp"})
                            : Json::array({"view.tscn", "native/press.cpp"})},
              {"cases", cases}};
}
std::string submitted(const fs::path &store, const fs::path &repo, Json m) {
  return submit(store, repo, m, "00000000-0000-0000-0000-000000000001")
      .at("id")
      .get<std::string>();
}
void decide_cases(const fs::path &store, const std::string &id,
                  bool replacement, bool reject_press) {
  Json cases = Json::object();
  if (!replacement)
    cases["foundation"] = {{"status", "approved"}, {"note", ""}};
  cases[replacement ? "compact-press" : "press"] = {
      {"status", reject_press ? "changes_requested" : "approved"},
      {"note", reject_press ? "Correct the press" : ""}};
  decide(
      store, id,
      Json{{"verdict", reject_press ? "changes_requested" : "approved"},
           {"cases", cases},
           {"reviewed_manifest_sha256", digest(store / id / "manifest.json")}});
}
} // namespace

int main() {
  const auto root = fs::temp_directory_path() /
                    ("factory-proof-composition-test-" + identifier());
  try {
    const auto repo = root / "repo", store = root / "store";
    fs::create_directories(repo / "native");
    std::ofstream(root / "view.png") << "fixture pixels";
    auto git = [&](std::initializer_list<std::string> args) {
      std::vector<std::string> command{"git"};
      command.insert(command.end(), args);
      ok(run(command, repo).code == 0);
    };
    auto revision = [&] {
      auto result = run({"git", "rev-parse", "HEAD"}, repo);
      ok(result.code == 0);
      while (!result.output.empty() && result.output.back() == '\n')
        result.output.pop_back();
      return result.output;
    };
    auto commit = [&] {
      git({"add", "."});
      git({"-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture"});
    };
    git({"init", "-q"});
    git({"config", "user.email", "composition@example.invalid"});
    git({"config", "user.name", "Composition Test"});
    std::ofstream(repo / "view.tscn") << "old foundation\n";
    std::ofstream(repo / "native/press.cpp") << "int press = 0;\n";
    commit();
    const auto before = revision();
    std::ofstream(repo / "view.tscn") << "reviewed foundation\n";
    std::ofstream(repo / "native/press.cpp") << "int press = 1;\n";
    commit();
    auto direction =
        submitted(store, repo, manifest(root / "view.png", false, false));
    decide_cases(store, direction, false, false);
    auto base = manifest(root / "view.png", false, true);
    base["direction"] = direction;
    const auto base_id = submitted(store, repo, base);
    decide_cases(store, base_id, false, true);
    std::ofstream(repo / "native/press.cpp") << "int press = 2;\n";
    commit();
    const auto after = revision();
    direction =
        submitted(store, repo, manifest(root / "view.png", true, false));
    decide_cases(store, direction, true, false);
    auto replacement = manifest(root / "view.png", true, true);
    replacement["direction"] = direction;
    const auto replacement_id = submitted(store, repo, replacement);
    Json scope{{"schema", 1},
               {"bead", "factory-test"},
               {"actor", "test"},
               {"reason", "Combine real case decisions for unchanged sources"},
               {"base_final", base_id},
               {"replacement_final", replacement_id},
               {"case_replacements", {{"press", "compact-press"}}},
               {"paths", {"view.tscn"}}};
    refuses([&] { check_gate(store, repo, before, after); });
    refuses([&] { compose_reviewed_cases(store, repo, scope); });
    decide_cases(store, replacement_id, true, false);
    auto invalid = scope;
    invalid["case_replacements"] = Json::object();
    refuses([&] { compose_reviewed_cases(store, repo, invalid); });
    invalid = scope;
    invalid["paths"] = Json::array({"view.tscn", "view.tscn"});
    refuses([&] { compose_reviewed_cases(store, repo, invalid); });
    invalid = scope;
    invalid["paths"] = Json::array({"unreviewed.tscn"});
    refuses([&] { compose_reviewed_cases(store, repo, invalid); });
    const auto composed = compose_reviewed_cases(store, repo, scope);
    ok(composed.at("source_inputs").contains("view.tscn"));
    check_gate(store, repo, before, after);
    ++checks;
    const auto scope_path =
        store / ".compositions" / (digest_text(composed.dump()) + ".json");
    auto altered = composed;
    altered["case_replacements"]["press"] = "foundation";
    write_json(scope_path, altered);
    refuses([&] { check_gate(store, repo, before, after); });
    write_json(scope_path, composed);
    std::ofstream(repo / "view.tscn") << "later changed foundation\n";
    commit();
    refuses([&] { check_gate(store, repo, before, revision()); });
    fs::remove_all(root);
    std::cout << "PROOF_COMPOSITION_PASS " << checks << '\n';
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    fs::remove_all(root);
    return 1;
  }
}
