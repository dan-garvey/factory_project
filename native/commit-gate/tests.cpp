#include "coordinator.hpp"

#include "factory/capture.hpp"
#include "native/tooling/local_resources.hpp"

#include <array>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <map>
#include <poll.h>
#include <sstream>
#include <stdexcept>
#include <sys/file.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;
namespace gate = factory::commit_gate;
namespace resources = factory::resources;
namespace fs = std::filesystem;
namespace {
int checks{};
void check(bool value, const std::string& reason) {
    ++checks;
    if (!value) throw std::runtime_error(reason);
}
template<class Function> void refuses(Function function) {
    bool refused{};
    try { function(); } catch (const std::exception&) { refused = true; }
    check(refused, "Invalid metadata or configuration must refuse before admission.");
}
std::string trim(std::string value) {
    while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) value.pop_back();
    return value;
}
std::string nul(std::initializer_list<std::string> paths) {
    std::string result;
    for (const auto& path : paths) { result += path; result += '\0'; }
    return result;
}
struct Reader {
    std::string tree = std::string(40, 'a');
    std::string head = std::string(40, 'b');
    int head_exit{};
    int tree_exit{};
    std::string names;
    std::map<std::string, std::string> config{
        {"factory.godotExecutable", "/fixture engine/godot\n"},
        {"factory.godotSHA256", std::string(64, 'a') + "\n"},
        {"factory.godotArtifacts", "/fixture artifacts/compiler\n"},
    };
    unsigned calls{};
    gate::GitResult operator()(const std::vector<std::string>& args) {
        ++calls;
        if (args == std::vector<std::string>{"write-tree"}) return {tree_exit, tree + "\n"};
        if (args == std::vector<std::string>{"rev-parse", "--verify", "--quiet", "HEAD"}) return {head_exit, head + "\n"};
        if (args == std::vector<std::string>{"diff-tree", "--no-commit-id", "--name-only", "--no-renames", "-r", "-z", head, tree}) return {0, names};
        if (args == std::vector<std::string>{"ls-tree", "-rz", "--name-only", tree}) return {0, names};
        if (args == std::vector<std::string>{"config", "--local", "--bool", "--get", "extensions.worktreeConfig"}) {
            const auto value = config.find("extensions.worktreeConfig");
            return value == config.end() ? gate::GitResult{1, {}} : gate::GitResult{0, value->second};
        }
        if (args.size() == 4 && args[0] == "config" && args[2] == "--get" &&
            (args[1] == "--local" || (args[1] == "--worktree" && args[3] == "factory.godotArtifacts"))) {
            const auto value = config.find(args[3]);
            return value == config.end() ? gate::GitResult{1, {}} : gate::GitResult{0, value->second};
        }
        throw std::runtime_error("Unexpected Git acquisition command.");
    }
    gate::Plan plan() {
        return gate::prepare("/fixture checkout", [&](const auto& args) { return (*this)(args); });
    }
};
void plans() {
    Reader docs;
    docs.names = nul({"README.md", "fixture.GD", ".gd"});
    const auto cheap = docs.plan();
    check(!cheap.compile_gdscript && docs.calls == 3, "Documentation does not query runtime config or compile unchanged scripts.");
    check(!cheap.validate_native && cheap.changed_paths.size() == 3,
          "A documentation candidate retains exact changed paths without native work.");
    check(cheap.command == std::vector<std::string>{"/usr/bin/python3", "-B", "/fixture checkout/scripts/check.py", "--staged", "--expected-tree", docs.tree},
          "The existing checker receives exactly one pinned staged-tree invocation.");
    for (const auto& paths : {nul({"experiments/engine-environment/godot/opening/file.gd"}),
                              nul({"old.txt", "experiments/engine-environment/godot/renamed.gd"}),
                              nul({"experiments/engine-environment/godot/name with\nspace.gd"})}) {
        Reader game; game.names = paths;
        const auto heavy = game.plan();
        check(heavy.compile_gdscript && game.calls == 7, "A NUL-delimited script delta selects heavy, common runtime settings and extension metadata.");
        const std::vector<std::string> expected{"/usr/bin/python3", "-B", "/fixture checkout/scripts/check.py", "--staged", "--expected-tree", game.tree,
            "--parse-gdscript", "--godot", "/fixture engine/godot", "--godot-sha256", std::string(64, 'a'), "--prototype-artifacts", "/fixture artifacts/compiler"};
        check(heavy.command == expected, "Pinned compiler arguments and paths remain separate, with no shell or nested wrapper.");
    }
    Reader native;
    native.names = nul({"native/factory-core/src/materials.cpp"});
    const auto native_plan = native.plan();
    check(native_plan.validate_native && !native_plan.compile_gdscript &&
              native_plan.changed_paths == std::vector<std::string>{"native/factory-core/src/materials.cpp"},
          "A native staged change selects heavy validation from the exact index path.");
    Reader initial; initial.head_exit = 1; initial.names = nul({"experiments/engine-environment/godot/initial.gd"});
    check(initial.plan().compile_gdscript, "An unborn HEAD enumerates the complete staged tree.");
    Reader sha256; sha256.tree = std::string(64, 'c'); sha256.head = std::string(64, 'd');
    check(sha256.plan().tree == sha256.tree, "Both supported Git object formats retain complete identifiers.");
    for (const auto& path : {"outside.gd", "experiments/engine-environment/godot-other/file.gd", "experiments/engine-environment/file.gd"}) {
        Reader bad; bad.names = nul({path}); refuses([&] { (void)bad.plan(); });
    }
    Reader truncated; truncated.names = "file.gd"; refuses([&] { (void)truncated.plan(); });
    Reader git_failed; git_failed.tree_exit = 1; refuses([&] { (void)git_failed.plan(); });
    Reader head_failed; head_failed.head_exit = 128; refuses([&] { (void)head_failed.plan(); });
    Reader bad_tree; bad_tree.tree = "not-a-tree"; refuses([&] { (void)bad_tree.plan(); });
    Reader broken_worktree; broken_worktree.names = nul({"experiments/engine-environment/godot/fixture.gd"});
    broken_worktree.config["extensions.worktreeConfig"] = "true\n";
    refuses([&] {
        (void)gate::prepare("/fixture checkout", [&](const auto& args) {
            if (args == std::vector<std::string>{"config", "--worktree", "--get", "factory.godotArtifacts"})
                return gate::GitResult{128, {}};
            return broken_worktree(args);
        });
    });
    for (const auto& result : {gate::GitResult{128, {}}, gate::GitResult{0, "invalid\n"}}) {
        Reader broken_extension; broken_extension.names = initial.names;
        refuses([&] {
            (void)gate::prepare("/fixture checkout", [&](const auto& args) {
                if (args == std::vector<std::string>{"config", "--local", "--bool", "--get", "extensions.worktreeConfig"})
                    return result;
                return broken_extension(args);
            });
        });
    }
    for (const auto& key : {"factory.godotExecutable", "factory.godotSHA256", "factory.godotArtifacts"}) {
        Reader absent; absent.names = initial.names; absent.config.erase(key); refuses([&] { (void)absent.plan(); });
        Reader empty; empty.names = initial.names; empty.config[key] = " \n\t"; refuses([&] { (void)empty.plan(); });
    }
    for (const auto& digest : {std::string(63, 'a'), std::string(64, 'A'), std::string(64, 'z')}) {
        Reader bad; bad.names = initial.names; bad.config["factory.godotSHA256"] = digest; refuses([&] { (void)bad.plan(); });
    }
}
struct Environment {
    std::vector<std::string> saved;
    Environment() {
        for (char** item = environ; *item; ++item) if (std::string(*item).starts_with("GIT_")) saved.emplace_back(*item);
        for (const auto& item : saved) ::unsetenv(item.substr(0, item.find('=')).c_str());
    }
    ~Environment() {
        std::vector<std::string> current;
        for (char** item = environ; *item; ++item) if (std::string(*item).starts_with("GIT_")) current.emplace_back(*item);
        for (const auto& item : current) ::unsetenv(item.substr(0, item.find('=')).c_str());
        for (const auto& item : saved) { const auto equals = item.find('='); ::setenv(item.substr(0, equals).c_str(), item.substr(equals + 1).c_str(), 1); }
    }
};
void write(const fs::path& path, const std::string& text) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    stream << text;
    check(static_cast<bool>(stream), "The owned fixture input was written.");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    check(static_cast<bool>(stream), "The owned fixture result exists.");
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}
std::string git(const fs::path& root, std::vector<std::string> tail, const fs::path& index = {}) {
    std::vector<std::string> args;
    if (!index.empty()) args = {"/usr/bin/env", "GIT_INDEX_FILE=" + index.string()};
    args.insert(args.end(), {"/usr/bin/git", "-C", root.string()});
    args.insert(args.end(), tail.begin(), tail.end());
    const auto result = factory_launch::run_process(args, std::chrono::seconds(5), 1024 * 1024);
    check(result.exit_code == 0, "Fixture Git setup succeeded.");
    return trim(result.output);
}
void repository(const fs::path& root) {
    fs::create_directory(root);
    (void)git(root, {"init", "-q"});
    (void)git(root, {"config", "user.name", "Native gate fixture"});
    (void)git(root, {"config", "user.email", "fixture@example.invalid"});
    write(root / "scripts/check.py", "");  // Data only; no Python implementation.
    write(root / "README.md", "Fixture\n");
    (void)git(root, {"add", "."});
    const auto tree = git(root, {"write-tree"});
    const auto commit = git(root, {"commit-tree", tree, "-m", "Fixture base"});
    (void)git(root, {"update-ref", "HEAD", commit});
}
void runtime_config(const fs::path& root) {
    (void)git(root, {"config", "--local", "factory.godotExecutable", "/fixture engine/godot"});
    (void)git(root, {"config", "--local", "factory.godotSHA256", std::string(64, 'a')});
    (void)git(root, {"config", "--local", "factory.godotArtifacts", (root / "compiler artifacts").string()});
}
void worktree_artifacts(const fs::path& base) {
    const auto root = base / "worktree config";
    repository(root);
    runtime_config(root);
    write(root / "experiments/engine-environment/godot/fixture.gd", "");
    (void)git(root, {"add", "experiments/engine-environment/godot/fixture.gd"});
    const auto common = (root / "compiler artifacts").string();
    const auto owned = (root / "private compiler evidence").string();
    check(gate::prepare(root).command.back() == common,
          "A repository without worktree configuration keeps its common artifact destination.");
    (void)git(root, {"config", "--local", "extensions.worktreeConfig", "true"});
    check(gate::prepare(root).command.back() == common,
          "An absent worktree artifact setting falls back to common local configuration.");
    (void)git(root, {"config", "--worktree", "factory.godotArtifacts", owned});
    const auto selected = gate::prepare(root);
    std::cout << "Worktree artifact destination: expected " << owned
              << "; selected " << selected.command.back() << '\n';
    check(selected.command.back() == owned,
          "The current worktree selects its own artifact destination before the common setting.");
    check(git(root, {"config", "--local", "--get", "factory.godotArtifacts"}) == common,
          "Selecting a worktree destination does not rewrite the shared batch.");
    (void)git(root, {"config", "--worktree", "factory.godotArtifacts", ""});
    refuses([&] { (void)gate::prepare(root); });
    (void)git(root, {"config", "--worktree", "factory.godotArtifacts", owned});
    (void)git(root, {"config", "--local", "--unset", "factory.godotArtifacts"});
    check(gate::prepare(root).command.back() == owned,
          "A valid worktree destination does not require a shared artifact setting.");
    (void)git(root, {"config", "--worktree", "factory.godotExecutable", "/unused worktree engine"});
    (void)git(root, {"config", "--worktree", "factory.godotSHA256", "invalid worktree pin"});
    const auto pinned = gate::prepare(root);
    check(pinned.command[8] == "/fixture engine/godot" && pinned.command[10] == std::string(64, 'a'),
          "Executable and digest pins remain common repository-local settings.");
    (void)git(root, {"config", "--worktree", "--unset", "factory.godotArtifacts"});
    refuses([&] { (void)gate::prepare(root); });
}
void linked_worktree_artifacts(const fs::path& base) {
    const auto root = base / "linked config main";
    const auto linked = base / "linked config checkout";
    repository(root);
    runtime_config(root);
    (void)git(root, {"worktree", "add", "--detach", linked.string(), "HEAD"});
    for (const auto& checkout : {root, linked}) {
        write(checkout / "experiments/engine-environment/godot/fixture.gd", "");
        (void)git(checkout, {"add", "experiments/engine-environment/godot/fixture.gd"});
    }
    const auto common = (root / "compiler artifacts").string();
    const auto owned = (linked / "private compiler evidence").string();
    check(gate::prepare(linked).command.back() == common,
          "A linked checkout without the worktree extension uses common artifacts.");
    (void)git(root, {"config", "--local", "extensions.worktreeConfig", "false"});
    check(gate::prepare(linked).command.back() == common,
          "An explicitly disabled worktree extension keeps common artifacts.");
    (void)git(root, {"config", "--local", "extensions.worktreeConfig", "true"});
    check(gate::prepare(linked).command.back() == common,
          "An enabled extension without a checkout override keeps common artifacts.");
    (void)git(linked, {"config", "--worktree", "factory.godotArtifacts", owned});
    check(gate::prepare(linked).command.back() == owned,
          "An enabled linked checkout uses its private artifact destination.");
    check(gate::prepare(root).command.back() == common,
          "The main checkout keeps its common destination after a linked override.");
    check(git(root, {"config", "--local", "--get", "factory.godotArtifacts"}) == common,
          "Linked selection leaves the common artifact setting unchanged.");
}
int compiled_checker(int argc, char** argv) {
    if (argc < 6) return 99;
    const fs::path root = fs::path(argv[2]).parent_path().parent_path();
    std::string observed;
    for (int index = 1; index < argc; ++index) { observed += argv[index]; observed += '\0'; }
    if (const auto* index = ::getenv("GIT_INDEX_FILE")) observed += std::string("index=") + index;
    write(root / "observed-arguments", observed);
    const auto outcome = trim(read(root / "fixture-outcome"));
    if (outcome == "signal") { ::raise(SIGTERM); return 99; }
    return std::stoi(outcome);
}
struct Buddy {
    pid_t pid;
    explicit Buddy(const fs::path& common) : pid(-1) {
        int pipe[2];
        check(::pipe2(pipe, O_CLOEXEC) == 0, "The sibling admission fixture has a ready pipe.");
        pid = ::fork();
        check(pid >= 0, "The sibling admission fixture starts.");
        if (pid == 0) {
            ::close(pipe[0]);
            try {
                resources::Admission hold(common, resources::Mode::heavy, false);
                const char ready = 'R';
                if (::write(pipe[1], &ready, 1) != 1) ::_exit(2);
                ::close(pipe[1]);
                for (;;) ::pause();
            } catch (...) { ::_exit(2); }
        }
        ::close(pipe[1]);
        pollfd ready{pipe[0], POLLIN, 0};
        const int available = ::poll(&ready, 1, 3000);
        char value{};
        const auto count = available > 0 ? ::read(pipe[0], &value, 1) : -1;
        ::close(pipe[0]);
        if (count != 1 || value != 'R') { ::kill(pid, SIGKILL); (void)::waitpid(pid, nullptr, 0); pid = -1; }
        check(pid > 0, "The independent sibling holds one native heavy slot.");
    }
    ~Buddy() {
        if (pid <= 0) return;
        ::kill(pid, SIGKILL);
        while (::waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
    }
};
void actual(const fs::path& base, const std::string& self, const std::string& executable) {
    const auto root = base / "repository with spaces";
    repository(root);
    write(root / "documentation.txt", "Changed documentation\n");
    (void)git(root, {"add", "documentation.txt"});
    const auto doc_tree = git(root, {"write-tree"});
    const auto alternate = root / "temporary index with spaces";
    fs::copy_file(root / ".git/index", alternate);
    write(root / "experiments/engine-environment/godot/fixture.gd", "");
    (void)git(root, {"add", "experiments/engine-environment/godot/fixture.gd"}, alternate);
    const auto game_tree = git(root, {"write-tree"}, alternate);
    runtime_config(root);
    const auto owned_artifacts = (root / "owned compiler evidence").string();
    (void)git(root, {"config", "--local", "extensions.worktreeConfig", "true"});
    (void)git(root, {"config", "--worktree", "factory.godotArtifacts", owned_artifacts});
    check(!gate::prepare(root).compile_gdscript && gate::prepare(root).tree == doc_tree,
          "An unstaged script does not turn a staged documentation change into heavy work.");
    check(::setenv("GIT_INDEX_FILE", alternate.c_str(), 1) == 0, "The temporary hook index is selected.");
    const auto temporary = gate::prepare(root);
    check(temporary.compile_gdscript && temporary.tree == game_tree && temporary.tree != doc_tree,
          "Actual Git reads honor the temporary index before selecting heavy admission.");
    write(root / "fixture-outcome", "37\n");
    check(gate::run(root, self) == 37, "The new coordinator preserves a real compiled child exit.");
    const auto observed = read(root / "observed-arguments");
    check(observed.find(game_tree) != std::string::npos && observed.find("index=" + alternate.string()) != std::string::npos,
          "The exact temporary tree and hook environment reach the admitted outer checker.");
    check(observed.find(owned_artifacts) != std::string::npos,
          "The worktree destination reaches the same admitted temporary-index checker.");
    ::unsetenv("GIT_INDEX_FILE");
    const auto doc_index = root / "documentation index";
    fs::copy_file(root / ".git/index", doc_index);
    fs::copy_file(alternate, root / ".git/index", fs::copy_options::overwrite_existing);
    ::setenv("GIT_INDEX_FILE", doc_index.c_str(), 1);
    check(!gate::prepare(root).compile_gdscript && gate::prepare(root).tree == doc_tree,
          "A temporary documentation index stays cheap even when the ordinary index contains scripts.");
    ::unsetenv("GIT_INDEX_FILE");
    for (const auto& outcome : {"127\n", "signal\n"}) {
        write(root / "fixture-outcome", outcome);
        const auto result = factory_launch::run_process({self, "--run-fixture", root.string()}, std::chrono::seconds(10), 1024 * 1024, nullptr, true);
        check(result.exit_code == (std::string(outcome) == "signal\n" ? 128 + SIGTERM : 127),
              "Command exit 127 and signal-derived exits are forwarded without fallback.");
    }
    write(root / "fixture-outcome", "37\n");
    {
        Buddy buddy(root / ".git");
        const int legacy = ::open((root / ".git/factory-local-resources/heavy.lock").c_str(), O_RDWR);
        check(legacy >= 0, "The native and legacy gate use the same retained lock inode.");
        const int exclusive = ::flock(legacy, LOCK_EX | LOCK_NB);
        const int failure = errno;
        ::close(legacy);
        check(exclusive < 0 && (failure == EAGAIN || failure == EWOULDBLOCK),
              "An exclusive legacy heavy lock would serialize this fixture.");
        const auto result = factory_launch::run_process({self, "--run-fixture", root.string()}, std::chrono::seconds(5), 1024 * 1024, nullptr, true);
        check(result.exit_code == 37 && result.output.find("admitted heavy") != std::string::npos,
              "The coordinator completes beside another native heavy holder without weakening admission.");
    }
    const auto missing = factory_launch::run_process({executable, "--root", (base / "missing").string()}, std::chrono::seconds(5), 1024 * 1024);
    check(missing.exit_code == 1, "A nonexistent checkout fails without starting a checker.");
    const auto malformed = factory_launch::run_process({executable, "--unexpected"}, std::chrono::seconds(5), 1024 * 1024);
    check(malformed.exit_code == 2, "The installed entrypoint exposes no interpreter or admission override.");
}
}  // namespace
int main(int argc, char** argv) {
    try {
        const auto self = fs::canonical(argv[0]).string();
        if (argc > 1 && std::string(argv[1]) == "-B") return compiled_checker(argc, argv);
        if (argc == 3 && std::string(argv[1]) == "--run-fixture") return gate::run(argv[2], self);
        const bool worktree_only = argc == 3 && std::string(argv[2]) == "--worktree-only";
        const bool linked_only = argc == 3 && std::string(argv[2]) == "--linked-worktree-only";
        check(argc == 2 || worktree_only || linked_only, "Provide the native coordinator executable fixture.");
        Environment clean_git;
        auto pattern = (fs::temp_directory_path() / "factory-native-commit-XXXXXX").string();
        const auto* created = ::mkdtemp(pattern.data());
        check(created != nullptr, "The fixture has one private owned directory.");
        const fs::path root(created);
        if (!worktree_only) linked_worktree_artifacts(root);
        if (!linked_only) worktree_artifacts(root);
        if (!worktree_only && !linked_only) {
            plans();
            actual(root, self, fs::canonical(argv[1]).string());
        }
        fs::remove_all(root);
        std::cout << checks << " native commit coordinator controls passed; no engine ran.\n";
    } catch (const std::exception& error) {
        std::cerr << "Native coordinator control failed after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
