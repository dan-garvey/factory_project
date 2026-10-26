#pragma once

#include <functional>
#include <string>
#include <vector>

namespace factory::commit_gate {

struct GitResult {
    int exit_code;
    std::string output;
};
using GitReader = std::function<GitResult(const std::vector<std::string>&)>;

} // namespace factory::commit_gate
