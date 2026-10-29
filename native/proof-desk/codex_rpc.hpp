#pragma once
#include "proof.hpp"
#include <stdexcept>
namespace factory::proof {
// Queue receipts and persisted user items can contain base64 image data even
// when the request supplied only local file paths.
inline constexpr size_t codex_message_limit = 64ULL * 1024 * 1024;
struct RpcFailure : std::runtime_error {
  bool may_have_submitted;
  RpcFailure(const std::string &message, bool uncertain)
      : std::runtime_error(message), may_have_submitted(uncertain) {}
};
// One bounded event-driven connection, never a model-side polling loop.
Json codex_rpc(const fs::path &socket, const std::string &method,
               const Json &params);
Json pause_for_review(const Json &config, const std::string &thread);
void resume_after_review(const Json &config, const std::string &thread,
                         const Json &paused);
bool reconcile_delivery(const Json &config, const fs::path &bundle);
bool start_queued_feedback(const Json &config, const fs::path &bundle);
} // namespace factory::proof
