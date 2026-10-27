#include "../proof.hpp"
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
    approve(final.at("id"));
    require(push() == 0, "Approved pre-push refused");
    git({"update-ref", "refs/heads/main", candidate, baseline});
    require(git({"rev-parse", "main"}) == candidate + "\n",
            "Approved main update failed");
    fs::remove_all(root);
    std::cout << "PROOF_HOOKS_PASS 5\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\nRetained: " << root << '\n';
    return 1;
  }
}
