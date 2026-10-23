#include "local_resources.hpp"

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <memory>
#include <sstream>
#include <thread>
#include <vector>

#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace fs = std::filesystem;
namespace resource = factory::resources;
using Clock = std::chrono::steady_clock;

namespace {
fs::path executable, cli, artifacts, repo, common;
unsigned process_count = 0;
unsigned completed = 0;

void expect(bool value, const std::string& message) {
    if (!value) throw std::runtime_error(message);
}

std::string text(const fs::path& path) {
    std::ifstream input(path);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

void write(const fs::path& path, const std::string& value) {
    std::ofstream output(path);
    output << value;
    expect(bool(output), "Could not write fixture " + path.string());
}

void until(const std::function<bool()>& predicate, const std::string& message) {
    const auto end = Clock::now() + std::chrono::seconds(5);
    while (Clock::now() < end) {
        if (predicate()) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error(message);
}

// Each synthetic command has its own process group and retained output. Closing
// the parent's descriptors before exec prevents the test holder's permit from
// leaking into the competing CLI. The CLI's own child inheritance is tested
// separately. No synthetic command uses the real project's admission directory.
class Process {
public:
    pid_t pid;
    fs::path log;
    bool direct_child_reaped = false;
    explicit Process(const std::vector<std::string>& command,
                     const std::vector<std::pair<std::string,std::string>>& environment = {},
                     const std::vector<int>& closed_standard_descriptors = {},
                     const std::vector<int>& deliberately_inherited = {}) {
        log = artifacts / ("process-" + std::to_string(++process_count) + ".log");
        resource::FileDescriptor output(::open(log.c_str(), O_CREAT | O_WRONLY | O_EXCL | O_CLOEXEC, 0600));
        expect(output.get() >= 0, "Could not open retained fixture output");
        std::vector<int> close_fds;
        for (const auto& entry : fs::directory_iterator("/proc/self/fd")) {
            const int fd = std::stoi(entry.path().filename().string());
            if (fd > 2 && std::find(deliberately_inherited.begin(),deliberately_inherited.end(),fd) == deliberately_inherited.end())
                close_fds.push_back(fd);
        }
        auto arguments = command;
        std::vector<char*> argv;
        for (auto& argument : arguments) argv.push_back(argument.data());
        argv.push_back(nullptr);
        pid = ::fork();
        expect(pid >= 0, "Could not fork owned fixture");
        if (pid == 0) {
            if (::setpgid(0, 0) < 0 || ::dup2(output.get(), 1) < 0 || ::dup2(output.get(), 2) < 0) ::_exit(126);
            for (int fd : close_fds) ::close(fd);
            for (int fd : closed_standard_descriptors) ::close(fd);
            for (const auto& [key,value] : environment) {
                if (::setenv(key.c_str(),value.c_str(),1) < 0) ::_exit(126);
            }
            ::execvp(argv[0],argv.data());
            ::_exit(127);
        }
        // The child also calls setpgid; a completed exec can win this race.
        if (::setpgid(pid,pid) < 0 && errno != EACCES && errno != ESRCH)
            throw std::runtime_error("Could not isolate synthetic command group");
    }
    Process(const Process&) = delete;
    Process& operator=(const Process&) = delete;
    ~Process() {
        if (!direct_child_reaped) {
            ::kill(-pid,SIGKILL);
            while (::waitpid(pid,nullptr,0) < 0 && errno == EINTR) {}
            // PR_SET_CHILD_SUBREAPER also makes killed grandchildren ours.
            // Drain this owned group after the still-owned leader is reaped.
            for (;;) {
                const auto adopted=::waitpid(-pid,nullptr,0);
                if (adopted>0 || (adopted<0 && errno==EINTR)) continue;
                break;
            }
        }
    }
    int wait() {
        int status = 0;
        until([&] {
            const auto result = ::waitpid(pid,&status,WNOHANG);
            if (result < 0 && errno != EINTR) throw std::runtime_error("Could not reap owned command");
            return result == pid;
        },"Owned command exceeded five seconds; log: " + log.string());
        direct_child_reaped = true;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        throw std::runtime_error("Owned command has no final status");
    }
};

// Reaping the direct wrapper is not completion of its inherited command. This
// guard exists before termination or any post-reaping assertion. It checks
// waitable-child ownership before signaling, rather than trusting a reused PID.
class InheritedCommandGuard {
public:
    InheritedCommandGuard(Process& wrapper, pid_t child, bool* completion=nullptr)
        : wrapper_(wrapper), child_(child), completion_(completion) {
        expect(child>0 && ::getpgid(child)==wrapper.pid,"Inherited fixture is outside its owned group");
    }
    ~InheritedCommandGuard() {
        const bool complete=cleanup();
        if (completion_) *completion_=complete;
    }
    InheritedCommandGuard(const InheritedCommandGuard&)=delete;
    InheritedCommandGuard& operator=(const InheritedCommandGuard&)=delete;
    int wait() {
        int status=0;
        until([&] {
            const auto result=::waitpid(child_,&status,WNOHANG);
            if (result<0 && errno!=EINTR) throw std::runtime_error("Adopted fixture is not a waitable child");
            if (result==child_) child_reaped_=true;
            return child_reaped_;
        },"Could not reap the adopted fixture");
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128+WTERMSIG(status);
        throw std::runtime_error("Adopted fixture has no final status");
    }
private:
    bool cleanup() noexcept {
        if (!wrapper_.direct_child_reaped) {
            if (::kill(wrapper_.pid,SIGKILL)<0 && errno!=ESRCH) return false;
            pid_t result;
            do { result=::waitpid(wrapper_.pid,nullptr,0); } while (result<0 && errno==EINTR);
            if (result==wrapper_.pid || (result<0 && errno==ECHILD)) wrapper_.direct_child_reaped=true;
            else return false;
        }
        if (child_reaped_) return true;
        int status=0;
        pid_t result;
        do { result=::waitpid(child_,&status,WNOHANG); } while (result<0 && errno==EINTR);
        if (result==child_ || (result<0 && errno==ECHILD)) {
            child_reaped_=true;
            return true;
        }
        // A zero wait result proves that this exact live PID is our child.
        if (result!=0 || (::kill(child_,SIGKILL)<0 && errno!=ESRCH)) return false;
        do { result=::waitpid(child_,&status,0); } while (result<0 && errno==EINTR);
        child_reaped_=result==child_;
        return child_reaped_;
    }
    Process& wrapper_;
    pid_t child_;
    bool* completion_;
    bool child_reaped_=false;
};

class DeliberateFixtureAssertion : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

std::vector<std::string> wrapped(const std::string& mode,
                                const std::vector<std::string>& command = {},
                                const std::vector<std::string>& options = {}) {
    std::vector<std::string> result = {cli.string(),"--root",repo.string(),mode,"--no-wait"};
    result.insert(result.end(),options.begin(),options.end());
    result.push_back("--");
    if (command.empty()) result.insert(result.end(),{executable.string(),"--fixture","exit","0"});
    else result.insert(result.end(),command.begin(),command.end());
    return result;
}

int invoke(const std::vector<std::string>& args) {
    Process child(args);
    const int result = child.wait();
    if (result != 0) std::cout << "Retained nonzero fixture exit " << result << ": " << child.log << '\n';
    return result;
}

template<class Error, class Function> void rejects(Function action, const std::string& label) {
    try { action(); }
    catch (const Error&) { return; }
    throw std::runtime_error("Expected refusal: " + label);
}

void test(const std::string& name, const std::function<void()>& action) {
    std::cout << "RUN " << name << std::endl;
    action();
    ++completed;
    std::cout << "PASS " << name << std::endl;
}

int fixture(int argc, char** argv) {
    if (argc < 4) return 121;
    const std::string mode(argv[2]);
    if (mode == "exit") return std::stoi(argv[3]);
    if (mode == "signal") { ::raise(SIGTERM); return 122; }
    if (mode == "reject-extra-descriptor" && argc == 5) {
        const int descriptor=std::stoi(argv[4]);
        errno=0;
        if (::fcntl(descriptor,F_GETFD)>=0 || errno!=EBADF) return 125;
        write(argv[3],"unrelated descriptor closed\n");
        return 0;
    }
    if (mode == "closed-state" && argc == 5) {
        const std::string closed(argv[4]);
        for (int fd=0;fd<=2;++fd) {
            if (closed.find(char('0'+fd)) != std::string::npos) {
                errno=0;
                if (::fcntl(fd,F_GETFD)>=0 || errno!=EBADF) return 125;
            }
        }
        write(argv[3],"closed streams preserved\n");
        return 0;
    }
    if (mode == "environment") {
        std::ostringstream value;
        for (const char* name : {"CMAKE_BUILD_PARALLEL_LEVEL","CARGO_BUILD_JOBS","CTEST_PARALLEL_LEVEL"}) {
            const char* item = ::getenv(name);
            value << (item ? item : "<missing>") << '\n';
        }
        for (int i=4;i<argc;++i) value << argv[i] << '\n';
        write(argv[3],value.str());
        return 0;
    }
    if (mode == "hold" && argc == 5) {
        write(argv[3],std::to_string(::getpid()) + "\n");
        const auto end = Clock::now() + std::chrono::seconds(8);
        while (!fs::exists(argv[4]) && Clock::now() < end)
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        return fs::exists(argv[4]) ? 0 : 123;
    }
    if (mode == "hold-supervisor" && argc == 5) {
        write(argv[3],std::to_string(::getppid()) + "\n");
        const auto end = Clock::now() + std::chrono::seconds(8);
        while (!fs::exists(argv[4]) && Clock::now() < end)
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        return fs::exists(argv[4]) ? 0 : 123;
    }
    if (mode == "server-client" && argc == 5) {
        const pid_t server = ::fork();
        if (server < 0) return 126;
        if (server == 0) {
            write(argv[3],std::to_string(::getpid()) + "\n");
            const auto end = Clock::now() + std::chrono::seconds(8);
            while (!fs::exists(argv[4]) && Clock::now() < end)
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            return fs::exists(argv[4]) ? 0 : 123;
        }
        until([&] { return !text(argv[3]).empty(); },"Synthetic server did not start");
        return 0;
    }
    return 124;
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (argc > 1 && std::string(argv[1]) == "--fixture") return fixture(argc,argv);
        expect(argc == 4,"Expected CLI, actual source root and owned artifact root");
        executable = fs::canonical("/proc/self/exe");
        cli = fs::canonical(argv[1]);
        fs::create_directories(argv[3]);
        std::string pattern = (fs::absolute(argv[3]) / "admission-XXXXXX").string();
        expect(::mkdtemp(pattern.data()) != nullptr,"Could not create owned native test artifacts");
        artifacts = pattern;
        repo = artifacts / "main checkout with spaces";
        fs::create_directory(repo);
        std::cout << "Artifacts: " << artifacts << std::endl;
        expect(::prctl(PR_SET_CHILD_SUBREAPER,1) == 0,"Could not supervise the orphan-inheritance fixture");
        expect(invoke({"git","init","--quiet","-b","main",repo.string()}) == 0,"Disposable Git setup failed");
        common = resource::common_git_dir(repo);
        expect(common == repo/".git","Wrong disposable common Git directory");

        test("actual linked checkout resolves its existing canonical common directory",[&] {
            const auto source = fs::canonical(argv[2]);
            const auto actual_common = resource::common_git_dir(source);
            expect(actual_common.filename() == ".git","Unexpected real common Git directory");
            expect(fs::is_symlink(source/".beads"),"The source checkout is not canonically linked");
            expect(resource::common_git_dir(actual_common.parent_path()) == actual_common,"Main and linked checkout discovery differ");
        });
        test("shared checks coexist with checks and heavy work",[&] {
            resource::Admission holder(common,resource::Mode::check,false);
            expect(invoke(wrapped("check")) == 0,"Check failed alongside check");
            expect(invoke(wrapped("heavy")) == 0,"Heavy failed alongside check");
            expect(invoke(wrapped("benchmark")) == 75,"Measurement bypassed shared activity");
        });
        test("four heavy slots admit work and refuse a fifth",[&] {
            const auto path = common/"factory-local-resources/heavy.lock";
            struct stat first {},last {};
            {
                resource::Admission holder(common,resource::Mode::heavy,false);
                std::vector<std::unique_ptr<resource::Admission>> others;
                for (unsigned i=1;i<resource::heavy_slots;++i)
                    others.push_back(std::make_unique<resource::Admission>(common,resource::Mode::heavy,false));
                expect(::stat(path.c_str(),&first)==0,"Could not observe stable lock identity");
                expect(invoke(wrapped("check")) == 0,"Cheap check blocked behind heavy");
                expect(invoke(wrapped("heavy")) == 75,"Fifth heavy bypassed the slot limit");
                expect(invoke(wrapped("benchmark")) == 75,"Measurement bypassed heavy");
            }
            expect(invoke(wrapped("benchmark")) == 0,"Heavy release left activity locked");
            expect(::stat(path.c_str(),&last)==0 && first.st_ino==last.st_ino,"Admission replaced a retained lock inode");
        });
        test("measurements exclude every workload class",[&] {
            {
                resource::Admission holder(common,resource::Mode::benchmark,false);
                for (const std::string mode : {"check","heavy","benchmark"})
                    expect(invoke(wrapped(mode)) == 75,"Measurement failed to exclude " + mode);
            }
            expect(invoke(wrapped("heavy")) == 0,"Measurement release leaked the heavy permit");
        });
        test("four live command children overlap and release a reusable slot",[&] {
            std::vector<std::unique_ptr<Process>> workers;
            const auto release=artifacts/"release-four-commands";
            for (unsigned i=0;i<resource::heavy_slots;++i) {
                const auto marker=artifacts/("concurrent-command-"+std::to_string(i));
                workers.push_back(std::make_unique<Process>(wrapped("heavy",
                    {executable.string(),"--fixture","hold",marker.string(),release.string()})));
                until([&] {return !text(marker).empty();},"Concurrent command did not enter its slot");
            }
            expect(invoke(wrapped("heavy"))==75,"A fifth live command bypassed capacity");
            expect(invoke(wrapped("check"))==0,"Live heavy commands blocked cheap checks");
            expect(invoke(wrapped("benchmark"))==75,"Benchmark overlapped live heavy commands");
            write(release,"release\n");
            for (auto& worker : workers)
                expect(worker->wait()==0,"Concurrent command did not finish normally");
            expect(invoke(wrapped("heavy"))==0,"Released slot could not be reused");
            expect(invoke(wrapped("benchmark"))==0,"Concurrent commands leaked activity");
        });
        test("the legacy exclusive gate and native slots exclude each other",[&] {
            const auto path=common/"factory-local-resources/heavy.lock";
            resource::FileDescriptor legacy(::open(path.c_str(),O_RDWR));
            expect(legacy.get()>=0,"Cannot open legacy fixture gate");
            expect(::flock(legacy.get(),LOCK_EX|LOCK_NB)==0,"Cannot acquire legacy gate");
            expect(invoke(wrapped("heavy"))==75,"Native slots bypassed a legacy heavy job");
            expect(::flock(legacy.get(),LOCK_UN)==0,"Cannot release legacy fixture gate");
            {
                resource::Admission native(common,resource::Mode::heavy,false);
                errno=0;
                expect(::flock(legacy.get(),LOCK_EX|LOCK_NB)<0 &&
                    (errno==EWOULDBLOCK || errno==EAGAIN),"Legacy job bypassed an active native slot");
            }
            expect(::flock(legacy.get(),LOCK_EX|LOCK_NB)==0,"Native release left the legacy gate busy");
        });
        test("child exit, signal and failed exec release admission with distinct status",[&] {
            expect(invoke(wrapped("heavy",{executable.string(),"--fixture","exit","7"}))==7,"Child exit was hidden");
            expect(invoke(wrapped("heavy",{executable.string(),"--fixture","signal","unused"}))==143,"Signal exit was hidden");
            expect(invoke(wrapped("heavy",{"/missing/factory-fixture-command"}))==1,"Failed exec became a command result");
            expect(invoke(wrapped("heavy",{executable.string(),"--fixture","exit","127"}))==127,"Real child exit 127 became an exec failure");
            expect(invoke(wrapped("benchmark"))==0,"A failure leaked admission");
        });
        test("server-safe execution keeps an active client admitted and releases its detached server",[&] {
            std::vector<std::unique_ptr<resource::Admission>> others;
            for (unsigned i=1;i<resource::heavy_slots;++i)
                others.push_back(std::make_unique<resource::Admission>(common,resource::Mode::heavy,false));
            const auto active_marker=artifacts/"server-safe-active-client";
            const auto active_release=artifacts/"server-safe-active-release";
            Process active(wrapped("heavy",{executable.string(),"--fixture","hold",active_marker.string(),active_release.string()},
                {}));
            until([&] { return !text(active_marker).empty(); },"Server-safe client did not start");
            expect(invoke(wrapped("heavy"))==75,"Live server-safe client lost its heavy slot");
            expect(invoke(wrapped("benchmark"))==75,"Live server-safe client lost shared activity");
            write(active_release,"release\n");
            expect(active.wait()==0,"Server-safe client did not finish");
            const auto server_marker=artifacts/"server-safe-detached-server";
            const auto server_release=artifacts/"server-safe-server-release";
            Process client(wrapped("heavy",{executable.string(),"--fixture","server-client",
                server_marker.string(),server_release.string()}));
            until([&] { return !text(server_marker).empty(); },"Detached server did not start");
            const pid_t server=static_cast<pid_t>(std::stol(text(server_marker)));
            InheritedCommandGuard guard(client,server);
            expect(client.wait()==0,"Server-safe client did not exit while server stayed alive");
            expect(::kill(server,0)==0,"Detached server ended before permit checks");
            others.clear();
            const auto heavy_path=common/"factory-local-resources/heavy.lock";
            resource::FileDescriptor legacy(::open(heavy_path.c_str(),O_RDWR));
            expect(legacy.get()>=0 && ::flock(legacy.get(),LOCK_EX|LOCK_NB)==0,
                "Detached server retained the legacy heavy gate");
            expect(::flock(legacy.get(),LOCK_UN)==0,"Could not release legacy gate");
            expect(invoke(wrapped("heavy"))==0,"Detached server retained a heavy slot");
            expect(invoke(wrapped("benchmark"))==0,"Detached server retained activity");
            expect(::kill(server,0)==0,"Detached server ended before admission controls completed");
            write(server_release,"release\n");
            expect(guard.wait()==0,"Detached server did not exit cleanly");
        });
        test("default immediate supervisor retains admission after outer wrapper death",[&] {
            std::vector<std::unique_ptr<resource::Admission>> others;
            for (unsigned i=1;i<resource::heavy_slots;++i)
                others.push_back(std::make_unique<resource::Admission>(common,resource::Mode::heavy,false));
            const auto marker=artifacts/"default-supervisor-pid";
            const auto release=artifacts/"default-supervisor-release";
            Process wrapper(wrapped("heavy",{executable.string(),"--fixture","hold-supervisor",
                marker.string(),release.string()}));
            until([&] { return !text(marker).empty(); },"Default supervisor did not start its command");
            const pid_t supervisor=static_cast<pid_t>(std::stol(text(marker)));
            InheritedCommandGuard guard(wrapper,supervisor);
            expect(::kill(wrapper.pid,SIGKILL)==0,"Could not stop the outer wrapper");
            expect(wrapper.wait()==137,"Outer wrapper did not record its termination");
            expect(invoke(wrapped("heavy"))==75,"Wrapper death released a live supervisor's heavy slot");
            expect(invoke(wrapped("benchmark"))==75,"Wrapper death released a live supervisor's activity");
            write(release,"release\n");
            expect(guard.wait()==0,"Default supervisor did not finish after its command");
            others.clear();
            expect(invoke(wrapped("benchmark"))==0,"Default supervisor leaked admission after exit");
        });
        test("capacity thresholds and malformed memory fail explicitly",[&] {
            resource::enforce_capacity({20*resource::gib,8*resource::gib},20,8);
            rejects<resource::AdmissionError>([] {resource::enforce_capacity({20*resource::gib-1,8*resource::gib},20,8);},"disk below floor");
            rejects<resource::AdmissionError>([] {resource::enforce_capacity({20*resource::gib,8*resource::gib-1},20,8);},"memory below floor");
            const auto path=artifacts/"meminfo";
            write(path,"MemFree: 1 kB\nMemAvailable: 8388608 kB\n");
            expect(resource::memory_available(path)==8*resource::gib,"Wrong memory units");
            for (const std::string value : {"MemFree: 1 kB\n","MemAvailable: 8 MB\n","MemAvailable: -1 kB\n","MemAvailable: 8 kB extra\n","MemAvailable: 18446744073709551615 kB\n"}) {
                write(path,value);
                rejects<std::exception>([&] { (void)resource::memory_available(path); },"invalid or absent memory capacity");
            }
        });
        test("floor refusals never start the command and cheap checks remain available",[&] {
            const auto marker=artifacts/"capacity-must-not-run";
            const std::vector<std::string> command={executable.string(),"--fixture","environment",marker.string()};
            expect(invoke(wrapped("heavy",command,{"--disk-floor-gib","1048576"}))==75,"Disk floor was bypassed");
            expect(!fs::exists(marker),"Disk refusal ran the child");
            expect(invoke(wrapped("heavy",command,{"--memory-reserve-gib","1048576"}))==75,"Memory floor was bypassed");
            expect(!fs::exists(marker),"Memory refusal ran the child");
            expect(invoke(wrapped("check",command,{"--disk-floor-gib","1048576","--memory-reserve-gib","1048576"}))==0,"Cheap diagnosis probed heavy floors");
            expect(invoke(wrapped("benchmark"))==0,"A floor refusal leaked locks");
        });
        test("jobs override inherited values and command arguments stay literal",[&] {
            const auto output=artifacts/"environment";
            const std::vector<std::string> command={executable.string(),"--fixture","environment",output.string(),"spaces ; $(no-shell)"};
            Process defaults(wrapped("check",command),{{"CMAKE_BUILD_PARALLEL_LEVEL","48"},{"CARGO_BUILD_JOBS","48"},{"CTEST_PARALLEL_LEVEL","48"}});
            expect(defaults.wait()==0 && text(output)=="8\n8\n8\nspaces ; $(no-shell)\n","Default jobs or literal arguments changed");
            expect(invoke(wrapped("check",command,{"--jobs=3"}))==0 && text(output)=="3\n3\n3\nspaces ; $(no-shell)\n","Explicit jobs did not reach the child");
        });
        test("Git hook variables do not redirect common-directory discovery",[&] {
            Process poisoned(wrapped("check"),{{"GIT_DIR","/missing/hook-index-repo"},{"GIT_COMMON_DIR","/missing/hook-common"},{"GIT_WORK_TREE","/missing/hook-worktree"},{"GIT_INDEX_FILE","/missing/hook-index"}});
            expect(poisoned.wait()==0,"Inherited Git hook variables poisoned discovery");
        });
        test("closed standard descriptors do not break Git discovery or command execution",[&] {
            unsigned attempt=0;
            for (const std::vector<int>& closed : std::vector<std::vector<int>>{{1},{0,1},{1,2},{0,1,2}}) {
                const auto marker=artifacts/("closed-standard-descriptors-" + std::to_string(++attempt));
                std::string numbers;
                for (int fd : closed) numbers += char('0'+fd);
                const std::vector<std::string> command={executable.string(),"--fixture","closed-state",marker.string(),numbers};
                Process child(wrapped("check",command),{},closed);
                expect(child.wait()==0 && text(marker)=="closed streams preserved\n","Closed standard descriptors broke discovery, changed stream state or skipped the command");
            }
        });
        test("invalid arguments and absent checkout refuse before command execution",[&] {
            expect(invoke({cli.string(),"--help"})==0,"Help requires a checkout");
            expect(invoke({cli.string(),"check"})==2,"Missing command accepted");
            for (const std::string value : {"0","-1","1.5","18446744073709551616"})
                expect(invoke(wrapped("check",{}, {"--jobs",value}))==2,"Invalid jobs accepted: " + value);
            expect(invoke(wrapped("heavy",{}, {"--disk-floor-gib","18446744073709551615"}))==2,"Overflowing floor accepted");
            auto missing=wrapped("check");
            missing[2]=(artifacts/"not-a-checkout").string();
            expect(invoke(missing)==1,"Absent checkout discovery did not fail");
        });
        test("unrelated inheritable descriptors never reach the admitted command",[&] {
            const auto secret=artifacts/"owned-descriptor-fixture";
            const auto marker=artifacts/"unrelated-descriptor-result";
            write(secret,"Synthetic owned fixture only.\n");
            resource::FileDescriptor original(::open(secret.c_str(),O_RDONLY|O_CLOEXEC));
            expect(original.get()>=0,"Could not open the isolated descriptor fixture");
            resource::FileDescriptor injected(::fcntl(original.get(),F_DUPFD,80));
            expect(injected.get()>=80 && (::fcntl(injected.get(),F_GETFD)&FD_CLOEXEC)==0,"Could not prepare an unrelated inheritable descriptor");
            const std::vector<std::string> command={executable.string(),"--fixture","reject-extra-descriptor",marker.string(),std::to_string(injected.get())};
            Process child(wrapped("heavy",command),{},{},{injected.get()});
            expect(child.wait()==0 && text(marker)=="unrelated descriptor closed\n","The command inherited an unrelated descriptor");
            expect(::fcntl(injected.get(),F_GETFD)>=0,"The wrapper changed its caller's descriptor table");
        });
        test("a queued heavy command holds no shared activity permit",[&] {
            const auto path=common/"factory-local-resources/heavy.lock";
            resource::FileDescriptor held(::open(path.c_str(),O_RDWR));
            expect(held.get()>=0 && ::flock(held.get(),LOCK_EX|LOCK_NB)==0,"Cannot prepare isolated heavy holder");
            std::vector<std::string> command={cli.string(),"--root",repo.string(),"heavy","--",executable.string(),"--fixture","exit","0"};
            Process queued(command);
            until([&] {return text(queued.log).find("waiting for heavy admission")!=std::string::npos;},"Heavy waiter did not start");
            // A measurement can enter while the existing heavy-only holder has
            // not entered shared activity and a second heavy is waiting for it.
            expect(invoke(wrapped("benchmark"))==0,"Queued heavy held shared activity prematurely");
            held=resource::FileDescriptor();
            expect(queued.wait()==0,"Waiting heavy did not continue after release");
        });
        test("a full slot queue does not acquire activity before capacity",[&] {
            const auto path=common/"factory-local-resources/heavy.lock";
            resource::FileDescriptor occupied(::open(path.c_str(),O_RDWR));
            struct flock range {};
            range.l_type=F_WRLCK; range.l_whence=SEEK_SET; range.l_len=resource::heavy_slots;
            expect(occupied.get()>=0 && ::flock(occupied.get(),LOCK_SH|LOCK_NB)==0 &&
                ::fcntl(occupied.get(),F_OFD_SETLK,&range)==0,"Cannot prepare isolated occupied slots");
            Process queued({cli.string(),"--root",repo.string(),"heavy","--",
                executable.string(),"--fixture","exit","0"});
            until([&] {return text(queued.log).find("waiting for heavy admission")!=std::string::npos;},
                "Slot waiter did not start");
            expect(invoke(wrapped("benchmark"))==0,"A slot waiter held activity prematurely");
            occupied=resource::FileDescriptor();
            expect(queued.wait()==0,"Slot waiter did not resume after capacity returned");
        });
        test("the immediate command retains admission if its wrapper is killed",[&] {
            std::vector<std::unique_ptr<resource::Admission>> others;
            for (unsigned i=1;i<resource::heavy_slots;++i)
                others.push_back(std::make_unique<resource::Admission>(common,resource::Mode::heavy,false));
            const auto marker=artifacts/"inherited-child-pid";
            const auto release=artifacts/"release-inherited-child";
            Process wrapper(wrapped("heavy",{executable.string(),"--fixture","hold",marker.string(),release.string()},
                {"--inherit-permits"}));
            until([&] {return !text(marker).empty();},"Inherited command did not start");
            const auto child=static_cast<pid_t>(std::stol(text(marker)));
            InheritedCommandGuard guard(wrapper,child);
            expect(::kill(wrapper.pid,SIGKILL)==0,"Could not stop the owned synthetic wrapper");
            expect(wrapper.wait()==137,"Synthetic wrapper did not record its actual termination");
            expect(invoke(wrapped("heavy"))==75,"Wrapper death released the live child's heavy permit");
            expect(invoke(wrapped("benchmark"))==75,"Wrapper death released the live child's activity permit");
            expect(invoke(wrapped("check"))==0,"Inherited heavy unexpectedly blocked checks");
            write(release,"release\n");
            expect(guard.wait()==0,"Inherited child did not finish normally");
            others.clear();
            expect(invoke(wrapped("benchmark"))==0,"Immediate child exit leaked inherited admission");
        });
        test("a post-reaping assertion still cleans and reaps the inherited command",[&] {
            const auto marker=artifacts/"assertion-child-pid";
            const auto release=artifacts/"assertion-never-released";
            bool rejected=false,cleanup_complete=false;
            pid_t inherited=-1;
            {
                Process wrapper(wrapped("heavy",{executable.string(),"--fixture","hold",marker.string(),release.string()},
                    {"--inherit-permits"}));
                until([&] {return !text(marker).empty();},"Assertion fixture did not start");
                inherited=static_cast<pid_t>(std::stol(text(marker)));
                try {
                    InheritedCommandGuard guard(wrapper,inherited,&cleanup_complete);
                    expect(::kill(wrapper.pid,SIGKILL)==0,"Could not stop the assertion fixture wrapper");
                    const int actual=wrapper.wait();
                    expect(actual==137,"Assertion fixture wrapper did not record its real termination");
                    if (actual!=0) throw DeliberateFixtureAssertion("Deliberately incorrect normal-exit expectation after direct-wrapper reaping");
                } catch (const DeliberateFixtureAssertion&) {
                    rejected=true;
                }
            }
            expect(rejected && cleanup_complete,"The expected assertion bypassed inherited-command cleanup");
            errno=0;
            expect(::waitpid(inherited,nullptr,WNOHANG)==-1 && errno==ECHILD,"The cleanup control left an owned child unreaped");
            expect(invoke(wrapped("benchmark"))==0,"Post-reaping assertion leaked inherited admission");
        });
        std::cout << "PASS " << completed << " native regression groups; retained artifacts: " << artifacts << std::endl;
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << completed << " completed groups: " << error.what() << std::endl;
        return 1;
    }
}
