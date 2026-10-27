#pragma once
#include "proof.hpp"
namespace factory::proof {
// One bounded event-driven connection, never a model-side polling loop.
Json codex_rpc(const fs::path &socket, const std::string &method,
               const Json &params);
Json pause_for_review(const Json &config, const std::string &thread);
void resume_after_review(const Json &config, const std::string &thread,
                         const Json &paused);
bool reconcile_delivery(const Json &config, const fs::path &bundle);
} // namespace factory::proof
