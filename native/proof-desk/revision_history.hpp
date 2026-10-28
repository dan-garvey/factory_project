#pragma once
#include <map>
#include <set>
#include <string>

namespace factory::proof {
// Both the native gate and the viewer derive revision visibility from the
// immutable lineage and local discard markers. Discard never grants approval.
struct RevisionHistory {
  std::map<std::string, std::string> previous;
  std::set<std::string> discarded;

  std::set<std::string> superseded() const {
    std::set<std::string> result;
    for (const auto &[id, parent] : previous) {
      if (discarded.contains(id))
        continue;
      std::set<std::string> visited;
      auto ancestor = parent;
      while (!ancestor.empty() && visited.insert(ancestor).second) {
        result.insert(ancestor);
        auto found = previous.find(ancestor);
        if (found == previous.end())
          break;
        ancestor = found->second;
      }
    }
    return result;
  }

  bool current(std::string id) const {
    const auto replaced = superseded();
    std::set<std::string> visited;
    while (!id.empty() && visited.insert(id).second) {
      if (replaced.contains(id))
        return false;
      if (!discarded.contains(id))
        return true;
      // Restoring or replacing a discarded branch must not compete with an
      // active sibling submitted since that branch was discarded.
      auto found = previous.find(id);
      if (found == previous.end())
        return false;
      id = found->second;
    }
    return id.empty();
  }
};
} // namespace factory::proof
