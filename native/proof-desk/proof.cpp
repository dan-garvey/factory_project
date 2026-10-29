#include "proof.hpp"
#include "codex_rpc.hpp"
#include "revision_history.hpp"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <poll.h>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace factory::proof {
void require(bool condition, const std::string &error) {
  if (!condition)
    throw std::runtime_error(error);
}
namespace {
constexpr uintmax_t media_limit = 256ULL * 1024 * 1024;
struct Lock {
  int fd;
  explicit Lock(const fs::path &root) {
    fs::create_directories(root);
    fd = open((root / ".lock").c_str(), O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    require(fd >= 0, "Cannot open proof store lock");
    if (flock(fd, LOCK_EX | LOCK_NB)) {
      close(fd);
      throw std::runtime_error("Proof store is busy; retry this action");
    }
  }
  ~Lock() {
    flock(fd, LOCK_UN);
    close(fd);
  }
};
std::string hex(const unsigned char *bytes, size_t n) {
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (size_t i = 0; i < n; ++i)
    out << std::setw(2) << unsigned(bytes[i]);
  return out.str();
}
std::string str(const Json &value, const char *key, size_t limit = 4000) {
  require(value.contains(key) && value.at(key).is_string(),
          std::string("Missing text: ") + key);
  auto s = value.at(key).get<std::string>();
  require(!s.empty() && s.size() <= limit && s.find('\0') == std::string::npos,
          std::string("Invalid text: ") + key);
  return s;
}
void safe_id(const std::string &id) {
  require(std::regex_match(id, std::regex("[A-Za-z0-9][A-Za-z0-9_.-]{0,127}")),
          "Invalid identifier");
}
void safe_relative(const std::string &name) {
  fs::path p(name);
  require(!name.empty() && !p.is_absolute() &&
              name.find('\\') == std::string::npos,
          "Expected relative path");
  for (const auto &part : p)
    require(part != ".." && part != "." && part != ".beads" && part != ".git",
            "Unsafe proof input path");
}
std::string git(const fs::path &repo, const std::vector<std::string> &tail) {
  std::vector<std::string> args{"git", "--no-optional-locks", "-C",
                                repo.string()};
  args.insert(args.end(), tail.begin(), tail.end());
  auto result = run(args);
  require(result.code == 0, "Git command failed: " + result.output);
  return result.output;
}
std::string trimmed(std::string s) {
  while (!s.empty() && (s.back() == '\n' || s.back() == '\r'))
    s.pop_back();
  return s;
}
Json load_bundle(const fs::path &store, const std::string &id) {
  safe_id(id);
  auto m = read_json(store / id / "manifest.json");
  require(m.at("id") == id, "Bundle identity mismatch");
  validate_manifest(m);
  return m;
}
void require_latest(const fs::path &store, const std::string &id) {
  RevisionHistory revisions;
  for (const auto &entry : fs::directory_iterator(store)) {
    if (!entry.is_directory() || entry.path().filename().string().front() == '.' ||
        !fs::exists(entry.path() / "manifest.json"))
      continue;
    auto other = read_json(entry.path() / "manifest.json");
    const auto other_id = entry.path().filename().string();
    revisions.previous.emplace(other_id, other.value("previous", std::string()));
    if (fs::exists(entry.path() / "discarded.json"))
      revisions.discarded.insert(other_id);
  }
  require(revisions.current(id), "A newer active revision supersedes this proof");
}
Json approved(const fs::path &store, const std::string &id) {
  require_latest(store, id);
  require(!fs::exists(store / id / "discarded.json"),
          "A discarded proof does not grant approval");
  auto m = load_bundle(store, id);
  verify_media(store / id, m);
  auto d = read_json(store / id / "decision.json");
  validate_decision(m, d);
  require(d.at("verdict") == "approved", "Referenced proof is not approved");
  require(d.at("manifest_sha256") == digest(store / id / "manifest.json"),
          "Approval refers to different evidence");
  return m;
}
void save_state(const fs::path &dir, const std::string &status,
                const std::string &detail = "") {
  write_json(dir / "delivery.json",
             Json{{"status", status}, {"detail", detail}});
}
} // namespace
ProcessResult run(const std::vector<std::string> &args, const fs::path &cwd,
                  int timeout_seconds) {
  require(!args.empty(), "Empty command");
  int pipes[2];
  require(pipe2(pipes, O_CLOEXEC) == 0, "pipe failed");
  auto pid = fork();
  if (pid < 0) {
    close(pipes[0]);
    close(pipes[1]);
    throw std::runtime_error("fork failed");
  }
  if (pid == 0) {
    setpgid(0, 0);
    close(pipes[0]);
    dup2(pipes[1], 1);
    dup2(pipes[1], 2);
    close(pipes[1]);
    int null_fd = open("/dev/null", O_RDONLY);
    dup2(null_fd, 0);
    close(null_fd);
    if (!cwd.empty() && chdir(cwd.c_str()))
      _exit(126);
    std::vector<char *> argv;
    for (const auto &arg : args)
      argv.push_back(const_cast<char *>(arg.c_str()));
    argv.push_back(nullptr);
    execvp(argv[0], argv.data());
    _exit(127);
  }
  close(pipes[1]);
  fcntl(pipes[0], F_SETFL, O_NONBLOCK);
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(timeout_seconds);
  std::string output;
  int status = 0;
  bool finished = false;
  bool eof = false;
  bool timeout = false;
  while (!finished || !eof) {
    char buffer[8192];
    auto n = read(pipes[0], buffer, sizeof(buffer));
    if (n > 0)
      output.append(buffer, static_cast<size_t>(n));
    else if (n == 0)
      eof = true;
    if (!finished)
      finished = waitpid(pid, &status, WNOHANG) == pid;
    if (output.size() > 4 * 1024 * 1024 ||
        std::chrono::steady_clock::now() > deadline) {
      kill(-pid, SIGKILL);
      if (!finished)
        waitpid(pid, &status, 0);
      timeout = true;
      break;
    }
    if (n <= 0 && (!finished || !eof)) {
      pollfd p{pipes[0], POLLIN, 0};
      poll(&p, 1, 20);
    }
  }
  close(pipes[0]);
  return {timeout             ? 124
          : WIFEXITED(status) ? WEXITSTATUS(status)
                              : 128 + WTERMSIG(status),
          output};
}
Json read_json(const fs::path &path) {
  require(fs::is_regular_file(path) && !fs::is_symlink(path) &&
              fs::file_size(path) <= 4 * 1024 * 1024,
          "Missing or oversized JSON: " + path.string());
  std::ifstream in(path);
  Json result;
  in >> result;
  return result;
}
void write_json(const fs::path &path, const Json &value) {
  fs::create_directories(path.parent_path());
  auto temp = path.string() + ".tmp-" + identifier();
  auto data = value.dump(2) + "\n";
  int fd = open(temp.c_str(), O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
  require(fd >= 0, "Cannot create durable record");
  size_t done = 0;
  while (done < data.size()) {
    auto n = write(fd, data.data() + done, data.size() - done);
    if (n <= 0) {
      close(fd);
      fs::remove(temp);
      throw std::runtime_error("Record write failed");
    }
    done += n;
  }
  bool synced = fsync(fd) == 0;
  close(fd);
  require(synced, "Record sync failed");
  fs::rename(temp, path);
  int dir = open(path.parent_path().c_str(), O_DIRECTORY | O_RDONLY);
  if (dir >= 0) {
    fsync(dir);
    close(dir);
  }
}
std::string digest_text(const std::string &value) {
  unsigned char out[EVP_MAX_MD_SIZE];
  unsigned int size = 0;
  require(EVP_Digest(value.data(), value.size(), out, &size, EVP_sha256(),
                     nullptr) == 1,
          "Digest failed");
  return hex(out, size);
}
std::string digest(const fs::path &path) {
  require(fs::is_regular_file(path) && !fs::is_symlink(path),
          "Missing regular media file: " + path.string());
  require(fs::file_size(path) <= media_limit, "Media exceeds 256 MiB limit");
  std::ifstream in(path, std::ios::binary);
  auto *ctx = EVP_MD_CTX_new();
  require(ctx != nullptr, "Digest allocation failed");
  EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr);
  char buffer[65536];
  while (in.read(buffer, sizeof(buffer)) || in.gcount())
    EVP_DigestUpdate(ctx, buffer, in.gcount());
  unsigned char out[EVP_MAX_MD_SIZE];
  unsigned int size = 0;
  EVP_DigestFinal_ex(ctx, out, &size);
  EVP_MD_CTX_free(ctx);
  require(in.eof(), "Media read failed");
  return hex(out, size);
}
std::string identifier() {
  unsigned char bytes[16];
  require(RAND_bytes(bytes, sizeof(bytes)) == 1, "Random identifier failed");
  return hex(bytes, sizeof(bytes));
}
void validate_manifest(const Json &m) {
  require(m.is_object() && m.value("schema", 0) == 1,
          "Unsupported proof schema");
  str(m, "title", 160);
  safe_id(str(m, "bead", 128));
  str(m, "actor", 160);
  auto stage = str(m, "stage", 32);
  require(stage == "direction" || stage == "final",
          "Expected direction or final stage");
  require(m.contains("cases") && m.at("cases").is_array() &&
              !m.at("cases").empty() && m.at("cases").size() <= 64,
          "Require 1 to 64 evidence cases");
  std::set<std::string> ids;
  size_t total_media = 0;
  size_t image_count = 0;
  for (const auto &c : m.at("cases")) {
    auto id = str(c, "id", 128);
    safe_id(id);
    require(ids.insert(id).second, "Duplicate evidence case");
    str(c, "title", 160);
    str(c, "criteria");
    str(c, "context");
    require(c.contains("existing") && c.at("existing").is_boolean(),
            "Each case must declare existing versus new content");
    require(c.contains("media") && c.at("media").is_array() &&
                !c.at("media").empty() && c.at("media").size() <= 32,
            "Each case needs 1 to 32 media items");
    bool before = false, after = false;
    std::set<std::string> media_ids;
    for (const auto &media : c.at("media")) {
      require(++total_media <= 64, "A proof bundle can contain at most 64 "
                                   "media items; split larger changes");
      auto mid = str(media, "id", 128);
      safe_id(mid);
      require(media_ids.insert(mid).second, "Duplicate media identifier");
      str(media, "caption", 1000);
      str(media, "path", 4096);
      auto kind = str(media, "kind", 32);
      require(kind == "image" || kind == "clip", "Unsupported media kind");
      if (kind == "image")
        require(++image_count <= 32, "A bundle may contain at most 32 images, "
                                     "leaving room for marked feedback");
      auto role = str(media, "role", 32);
      require(role == "before" || role == "after" || role == "concept",
              "Unsupported media role");
      require(stage != "final" || role != "concept",
              "Final evidence must show actual before/after media");
      before |= role == "before";
      after |= role == "after";
    }
    if (stage == "final") {
      require(after, "Final case has no candidate evidence");
      if (c.at("existing").get<bool>())
        require(before, "Existing content requires before and after evidence");
    }
  }
}
void validate_decision(const Json &m, const Json &d) {
  require(d.is_object(), "Expected decision object");
  auto verdict = str(d, "verdict", 32);
  require(verdict == "approved" || verdict == "changes_requested",
          "Unknown decision");
  require(d.contains("cases") && d.at("cases").is_object() &&
              d.at("cases").size() == m.at("cases").size(),
          "Decision must cover every required case");
  bool changes = false;
  size_t feedback_bytes = d.value("note", std::string()).size();
  size_t annotation_count = 0;
  for (const auto &c : m.at("cases")) {
    auto id = c.at("id").get<std::string>();
    require(d.at("cases").contains(id), "Required case missing from decision");
    const auto &review = d.at("cases").at(id);
    feedback_bytes += review.value("note", std::string()).size();
    auto status = str(review, "status", 32);
    require(status == "approved" || status == "changes_requested" ||
                status == "unreviewed",
            "Invalid case decision");
    if (verdict == "approved")
      require(status == "approved",
              "Whole-change approval requires every case approved");
    if (status == "changes_requested") {
      changes = true;
      require(!review.value("note", std::string()).empty() ||
                  !review.value("annotations", Json::array()).empty(),
              "A case change request needs a note or annotation");
    }
    require(review.value("note", std::string()).size() <= 16000,
            "Feedback exceeds limit");
    if (!review.contains("annotations"))
      continue;
    require(review.at("annotations").is_array() &&
                review.at("annotations").size() <= 128,
            "Too many annotations");
    for (const auto &a : review.at("annotations")) {
      require(++annotation_count <= 32,
              "A review can contain at most 32 annotations");
      feedback_bytes += a.value("text", std::string()).size();
      auto mid = str(a, "media", 128);
      auto found = std::find_if(
          c.at("media").begin(), c.at("media").end(),
          [&](const Json &media) { return media.at("id") == mid; });
      require(found != c.at("media").end(),
              "Annotation refers to unknown media");
      str(a, "text", 4000);
      for (auto key : {"x", "y", "end_x", "end_y"})
        require(a.contains(key) && a.at(key).is_number() &&
                    a.at(key).get<double>() >= 0 &&
                    a.at(key).get<double>() <= 1,
                "Annotation coordinate out of range");
      require(a.contains("time_ms") && a.at("time_ms").is_number_integer() &&
                  a.at("time_ms").get<int64_t>() >= 0,
              "Invalid annotation timestamp");
      if (found->at("kind") == "image")
        require(a.at("time_ms") == 0, "Image annotation has a clip timestamp");
    }
  }
  require(verdict != "changes_requested" || changes ||
              !d.value("note", std::string()).empty(),
          "A change request needs feedback");
  require(d.value("note", std::string()).size() <= 16000,
          "Feedback exceeds limit");
  require(
      feedback_bytes <= 32000,
      "Combined feedback exceeds 32 KiB; shorten notes or split this review");
}
void verify_media(const fs::path &bundle, const Json &m) {
  for (const auto &c : m.at("cases"))
    for (const auto &media : c.at("media")) {
      auto path = media.at("path").get<std::string>();
      safe_relative(path);
      require(digest(bundle / path) == media.at("sha256"),
              "Evidence changed or is missing: " + path);
    }
}
Json source_inputs(const fs::path &repo, const std::string &revision,
                   const Json &paths) {
  require(paths.is_array() && !paths.empty(), "Declare affected source paths");
  Json result = Json::object();
  for (const auto &p : paths) {
    auto name = p.get<std::string>();
    safe_relative(name);
    auto listing = git(repo, {"ls-tree", "-r", "-z", revision, "--", name});
    if (listing.empty()) {
      result[name] = nullptr;
      continue;
    }
    size_t pos = 0;
    while (pos < listing.size()) {
      auto end = listing.find('\0', pos);
      auto row = listing.substr(pos, end - pos);
      auto tab = row.find('\t');
      require(tab != std::string::npos, "Malformed Git tree record");
      std::istringstream head(row.substr(0, tab));
      std::string mode, kind, blob;
      head >> mode >> kind >> blob;
      require(kind == "blob" && mode != "120000",
              "Proof source cannot be a symlink or submodule");
      result[row.substr(tab + 1)] = blob;
      if (end == std::string::npos)
        break;
      pos = end + 1;
    }
  }
  return result;
}
Json submit(const fs::path &store, const fs::path &repo, Json m,
            const std::string &thread) {
  validate_manifest(m);
  require(std::regex_match(
              thread,
              std::regex("[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")),
          "Submit from the exact originating CODEX_THREAD_ID");
  Lock lock(store);
  std::string stage = m.at("stage");
  auto revision = trimmed(git(repo, {"rev-parse", "HEAD"}));
  if (stage == "final")
    require(git(repo, {"status", "--porcelain", "--untracked-files=normal"})
                .empty(),
            "Final proof requires a clean committed candidate checkout");
  m["revision"] = revision;
  m["source_inputs"] = source_inputs(repo, revision, m.at("paths"));
  m["thread"] = thread;
  m["repo"] = fs::canonical(repo).string();
  m["id"] = identifier();
  m["submitted_at"] = std::chrono::duration_cast<std::chrono::seconds>(
                          std::chrono::system_clock::now().time_since_epoch())
                          .count();
  if (m.contains("previous")) {
    require_latest(store, str(m, "previous", 128));
    auto prev = load_bundle(store, str(m, "previous", 128));
    require(prev.at("bead") == m.at("bead") &&
                prev.at("stage") == m.at("stage"),
            "Revision must belong to the same change and stage");
  }
  if (stage == "final") {
    auto direction = approved(store, str(m, "direction", 128));
    const bool minor = m.value("minor_correction", false);
    if (minor)
      str(m, "direction_reason", 2000);
    require(direction.at("bead") == m.at("bead") || minor,
            "Direction belongs to another change");
    require(direction.at("stage") == "direction" || minor,
            "Final proof must reference approved direction, or declare a minor "
            "correction");
    for (const auto &c : direction.at("cases"))
      require(std::any_of(m.at("cases").begin(), m.at("cases").end(),
                          [&](const Json &current) {
                            return current.at("id") == c.at("id");
                          }),
              "Final proof dropped a required approved-direction case");
  }
  auto stage_dir = store / (".staging-" + m.at("id").get<std::string>());
  fs::create_directories(stage_dir / "media");
  uintmax_t total = 0;
  try {
    for (auto &c : m.at("cases"))
      for (auto &media : c.at("media")) {
        fs::path source(str(media, "path"));
        require(source.is_absolute() && !fs::is_symlink(source),
                "Media must be an absolute regular file");
        auto ext = source.extension().string();
        auto kind = media.at("kind");
        require(kind == "image"
                    ? (ext == ".png" || ext == ".jpg" || ext == ".jpeg")
                    : (ext == ".mp4" || ext == ".webm" || ext == ".mov"),
                "Unsupported media extension");
        auto hash = digest(source);
        total += fs::file_size(source);
        require(total <= 512ULL * 1024 * 1024, "Proof bundle exceeds 512 MiB");
        auto name =
            fs::path("media") / (c.at("id").get<std::string>() + "-" +
                                 media.at("id").get<std::string>() + ext);
        fs::copy_file(source, stage_dir / name);
        require(digest(stage_dir / name) == hash,
                "Media changed during submission");
        media["path"] = name.generic_string();
        media["sha256"] = hash;
      }
    write_json(stage_dir / "manifest.json", m);
    fs::rename(stage_dir, store / m.at("id").get<std::string>());
  } catch (...) {
    fs::remove_all(stage_dir);
    throw;
  }
  return m;
}
Json decide(const fs::path &store, const std::string &id, Json d) {
  Lock lock(store);
  auto m = load_bundle(store, id);
  auto dir = store / id;
  require(!fs::exists(dir / "discarded.json"),
          "This proof was discarded locally. Restore it before reviewing.");
  require(!fs::exists(dir / "decision.json"),
          "This revision already has a final decision");
  require(d.value("reviewed_manifest_sha256", std::string()) ==
              digest(dir / "manifest.json"),
          "The review window refers to different evidence. Reopen the proof.");
  verify_media(dir, m);
  validate_decision(m, d);
  // Reject a stale window after a replacement proof has entered the queue.
  require_latest(store, id);
  d["manifest_sha256"] = digest(dir / "manifest.json");
  d["id"] = identifier();
  d["proof"] = id;
  if (d.contains("attachments")) {
    require(d.at("attachments").is_array() && d.at("attachments").size() <= 64,
            "Too many marked frames");
    fs::create_directories(dir / "feedback");
    for (auto &attachment : d.at("attachments")) {
      fs::path source(attachment.get<std::string>());
      require(source.is_absolute() && source.extension() == ".png",
              "Marked frames must be PNG files");
      auto hash = digest(source);
      auto name = fs::path("feedback") / (hash + ".png");
      if (!fs::exists(dir / name))
        fs::copy_file(source, dir / name);
      require(digest(dir / name) == hash,
              "Marked frame changed during submission");
      attachment = Json{{"path", name.generic_string()}, {"sha256", hash}};
    }
  }
  size_t images = d.value("attachments", Json::array()).size();
  for (const auto &c : m.at("cases"))
    for (const auto &media : c.at("media"))
      if (media.at("kind") == "image")
        ++images;
  require(images <= 64, "Review exceeds the 64-image feedback limit. Split the "
                        "change into smaller proof bundles.");
  write_json(dir / "decision.json", d);
  save_state(dir, "pending");
  return d;
}
Json set_discarded(const fs::path &store, const std::string &id,
                   const std::string &manifest_hash, bool discarded) {
  Lock lock(store);
  load_bundle(store, id);
  const auto dir = store / id;
  require(!fs::exists(dir / "decision.json"),
          "A submitted decision cannot be discarded or restored");
  require(manifest_hash == digest(dir / "manifest.json"),
          "This window refers to different evidence. Reopen the proof.");
  require_latest(store, id);
  Json result{{"proof", id},
              {"status", discarded ? "discarded" : "waiting_for_human"}};
  if (discarded) {
    result["manifest_sha256"] = manifest_hash;
    write_json(dir / "discarded.json", result);
  } else {
    fs::remove(dir / "discarded.json");
    int fd = open(dir.c_str(), O_DIRECTORY | O_RDONLY);
    require(fd >= 0, "Cannot open proof directory for sync");
    const bool synced = fsync(fd) == 0;
    close(fd);
    require(synced, "Cannot sync restored proof");
  }
  // This local queue action never writes a decision, contacts Beads or Codex,
  // resumes a goal, or delivers a notification.
  return result;
}
Json deliver(const fs::path &store, const fs::path &repo, const std::string &id,
             const std::string &socket, const std::string &beads) {
  Lock lock(store);
  auto m = load_bundle(store, id);
  auto dir = store / id;
  require(!fs::exists(dir / "discarded.json"),
          "Discarded proofs cannot deliver feedback");
  auto d = read_json(dir / "decision.json");
  validate_decision(m, d);
  require(d.at("manifest_sha256") == digest(dir / "manifest.json"),
          "Decision evidence mismatch");
  verify_media(dir, m);
  auto state = fs::exists(dir / "delivery.json")
                   ? read_json(dir / "delivery.json")
                   : Json{{"status", "pending"}};
  if (state.at("status") == "delivered" || state.at("status") == "queued")
    return state;
  require(
      state.at("status") != "sending" && state.at("status") != "uncertain",
      "Delivery may already have succeeded. Reconcile the receipt in the "
      "originating thread before retrying; no automatic duplicate is sent.");
  std::ostringstream message;
  message << "Factory Proof Desk human review [proof-decision:"
          << d.at("id").get<std::string>() << "]\n";
  message << m.at("title").get<std::string>() << " | "
          << m.at("stage").get<std::string>() << " | "
          << d.at("verdict").get<std::string>() << "\n";
  message << "Bead: " << m.at("bead").get<std::string>()
          << "\nCandidate: " << m.at("revision").get<std::string>()
          << "\nProof: " << id << "\n";
  const bool corrections = d.at("verdict") == "changes_requested";
  if (!d.value("note", std::string()).empty())
    message << d.at("note").get<std::string>() << "\n";
  std::vector<std::string> images;
  std::set<std::string> imageHashes;
  bool hasMarks = false;
  auto addImage = [&](const fs::path &path, const std::string &hash) {
    if (imageHashes.insert(hash).second)
      images.push_back(path.string());
  };
  for (const auto &c : m.at("cases")) {
    const auto &review = d.at("cases").at(c.at("id").get<std::string>());
    const auto marks = review.value("annotations", Json::array());
    hasMarks |= !marks.empty(); // validate_decision requires annotation text.
    const auto note = review.value("note", std::string());
    if (note.empty() && marks.empty() &&
        review.at("status") != "changes_requested")
      continue;
    message << "\n"
            << c.at("title").get<std::string>() << ": "
            << review.at("status").get<std::string>() << "\n";
    if (!note.empty())
      message << note << "\n";
    for (const auto &a : marks)
      message << "Media " << a.at("media").get<std::string>() << " at "
              << a.at("time_ms") << " ms, (" << a.at("x") << ", " << a.at("y")
              << "): " << a.at("text").get<std::string>() << "\n";
    if (!corrections || marks.empty())
      continue;
    for (const auto &media : c.at("media")) {
      // Only explicitly marked evidence accompanies feedback. Text-only case
      // notes never reattach context already available to the originating
      // agent.
      if (std::none_of(marks.begin(), marks.end(), [&](const Json &a) {
            return a.at("media") == media.at("id");
          }))
        continue;
      if (media.at("kind") == "image" &&
          !d.value("attachments", Json::array()).empty())
        continue;
      auto path = (dir / media.at("path").get<std::string>()).string();
      message << media.at("caption").get<std::string>() << ": " << path << "\n";
      if (media.at("kind") == "image")
        addImage(path, media.at("sha256"));
    }
  }
  for (const auto &a : d.value("attachments", Json::array())) {
    auto path = dir / a.at("path").get<std::string>();
    require(digest(path) == a.at("sha256"), "Marked feedback changed");
    if (corrections && hasMarks)
      addImage(path, a.at("sha256"));
  }
  require(images.size() <= 64, "Too many images for one feedback message; "
                               "reduce this proof's media before sending");
  // The daemon echoes resolved images in its receipt. Refuse before any
  // mutation if that receipt cannot fit, reserving space for JSON metadata.
  uintmax_t receiptBytes = Json(message.str()).dump().size() + 1024 * 1024;
  for (const auto &image : images)
    receiptBytes += 4 * ((fs::file_size(image) + 2) / 3);
  require(receiptBytes <= codex_message_limit,
          "Marked feedback exceeds the 64 MiB delivery limit. Reduce marked "
          "images or split the review; no agent message was sent.");
  if (!fs::exists(dir / "beads-receipt.json")) {
    auto result = run({beads, "comments", "add", m.at("bead"), "--actor",
                       "factory-proof-desk-human", "--message", message.str()},
                      repo);
    require(result.code == 0,
            "Decision saved; Beads record failed: " + result.output);
    write_json(dir / "beads-receipt.json", Json{{"recorded", true}});
  }
  Json input = Json::array({Json{{"type", "text"}, {"text", message.str()}}});
  for (const auto &image : images)
    input.push_back(Json{{"type", "localImage"}, {"path", image}});
  const auto clientId = "factory-proof-" + d.at("id").get<std::string>();
  save_state(dir, "sending");
  try {
    const auto response = codex_rpc(socket, "thread/queue/add",
                                    Json{{"threadId", m.at("thread")},
                                         {"clientUserMessageId", clientId},
                                         {"input", input}});
    const auto &receipt = response.at("queuedSubmission");
    require(receipt.at("clientUserMessageId") == clientId,
            "Codex returned a receipt for another message");
    write_json(dir / "delivery.json",
               Json{{"status", "delivered"},
                    {"detail", "Review queued to the originating agent"},
                    {"client_message_id", clientId},
                    {"queued_submission_id", receipt.at("id")}});
  } catch (const RpcFailure &error) {
    save_state(dir, error.may_have_submitted ? "uncertain" : "failed",
               error.what());
  } catch (const std::exception &error) {
    save_state(dir, "uncertain", error.what());
  }
  return read_json(dir / "delivery.json");
}
bool visual_path(const std::string &path) {
  static const std::set<std::string> extensions{
      ".gd",  ".tscn", ".tres", ".glb",    ".gltf",
      ".png", ".jpg",  ".svg",  ".shader", ".gdshader"};
  return extensions.count(fs::path(path).extension().string()) ||
         path.rfind("native/proof-desk/viewer", 0) == 0;
}
Json declare_nonvisual(const fs::path &store, const fs::path &repo,
                       const Json &declaration) {
  str(declaration, "reason", 4000);
  safe_id(str(declaration, "bead", 128));
  str(declaration, "actor", 160);
  Lock lock(store);
  auto revision = trimmed(git(repo, {"rev-parse", "HEAD"}));
  auto inputs = source_inputs(repo, revision, declaration.at("paths"));
  for (auto it = inputs.begin(); it != inputs.end(); ++it)
    require(
        !visual_path(it.key()),
        "Known visual files require human review, not a nonvisual declaration");
  auto result = declaration;
  result["revision"] = revision;
  result["source_inputs"] = inputs;
  write_json(store / ".scopes" / (digest_text(result.dump()) + ".json"),
             result);
  return result;
}
void check_gate(const fs::path &store, const fs::path &repo,
                const std::string &before, const std::string &after) {
  auto changes = git(repo, {"diff", "--name-only", "-z", before, after});
  std::set<std::string> needed;
  for (size_t p = 0; p < changes.size();) {
    auto end = changes.find('\0', p);
    auto path = changes.substr(p, end - p);
    auto ext = fs::path(path).extension().string();
    // Native changes can alter physical component geometry and connections.
    if (visual_path(path) || (path.rfind("native/", 0) == 0 &&
                              (ext == ".cpp" || ext == ".hpp" || ext == ".h")))
      needed.insert(path);
    if (end == std::string::npos)
      break;
    p = end + 1;
  }
  if (needed.empty())
    return;
  require(
      fs::is_directory(store),
      "Visual changes require human proof approval; proof store is missing");
  if (fs::is_directory(store / ".scopes"))
    for (const auto &entry : fs::directory_iterator(store / ".scopes")) {
      try {
        auto scope = read_json(entry.path());
        auto current = source_inputs(repo, after, scope.at("paths"));
        if (current != scope.at("source_inputs"))
          continue;
        for (auto it = current.begin(); it != current.end(); ++it)
          if (!visual_path(it.key()))
            needed.erase(it.key());
      } catch (const std::exception &) {
      }
    }
  for (const auto &entry : fs::directory_iterator(store)) {
    if (!entry.is_directory() || !fs::exists(entry.path() / "decision.json"))
      continue;
    try {
      auto m = approved(store, entry.path().filename().string());
      if (m.at("stage") != "final")
        continue;
      auto current = source_inputs(repo, after, m.at("paths"));
      if (current != m.at("source_inputs"))
        continue;
      for (auto it = m.at("source_inputs").begin();
           it != m.at("source_inputs").end(); ++it)
        needed.erase(it.key());
    } catch (const std::exception &) { /* Invalid or unrelated proofs cannot
                                          authorize publication. */
    }
  }
  std::string missing;
  for (const auto &path : needed)
    missing += "\n  " + path;
  require(needed.empty(),
          "Human final visual approval is missing or stale for:" + missing);
}
} // namespace factory::proof
