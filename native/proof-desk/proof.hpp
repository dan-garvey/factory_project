#pragma once
#include "vendor/json.hpp"
#include <filesystem>
#include <string>
#include <vector>

namespace factory::proof {
using Json = nlohmann::json;
namespace fs = std::filesystem;
struct ProcessResult {
  int code;
  std::string output;
};
ProcessResult run(const std::vector<std::string> &args,
                  const fs::path &cwd = {}, int timeout_seconds = 30);
Json read_json(const fs::path &path);
void write_json(const fs::path &path, const Json &value);
std::string digest(const fs::path &path);
std::string digest_text(const std::string &value);
std::string identifier();
void require(bool condition, const std::string &error);
void validate_manifest(const Json &manifest);
void validate_decision(const Json &manifest, const Json &decision);
void verify_media(const fs::path &bundle, const Json &manifest);
bool visual_path(const std::string &path);
Json declare_nonvisual(const fs::path &store, const fs::path &repo,
                       const Json &declaration);
Json source_inputs(const fs::path &repo, const std::string &revision,
                   const Json &paths);
Json submit(const fs::path &store, const fs::path &repo, Json manifest,
            const std::string &thread);
Json decide(const fs::path &store, const std::string &id, Json decision);
Json deliver(const fs::path &store, const fs::path &repo, const std::string &id,
             const std::string &socket, const std::string &beads);
void check_gate(const fs::path &store, const fs::path &repo,
                const std::string &before, const std::string &after);
} // namespace factory::proof
