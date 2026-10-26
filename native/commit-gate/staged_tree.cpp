#include "staged_tree.hpp"

#include "native/validation/tree_manifest.hpp"

#include <cerrno>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace factory::commit_gate {
namespace {
namespace fs = std::filesystem;

void require(bool value, const char* reason) {
    if (!value) throw std::runtime_error(reason);
}

bool within(const fs::path& parent, const fs::path& candidate) {
    auto ancestor = parent.begin();
    auto child = candidate.begin();
    for (; ancestor != parent.end(); ++ancestor, ++child) {
        if (child == candidate.end() || *ancestor != *child) return false;
    }
    return true;
}

validation::ObjectFormat format_of(const std::string& tree) {
    require((tree.size() == 40 || tree.size() == 64) &&
                tree.find_first_not_of("0123456789abcdef") == std::string::npos,
            "The staged native source needs a complete lowercase Git tree ID.");
    return tree.size() == 40 ? validation::ObjectFormat::sha1 : validation::ObjectFormat::sha256;
}
}

StagedTree::StagedTree(fs::path root, std::string tree, std::size_t files,
                       std::size_t bytes) noexcept
    : root_(std::move(root)), tree_(std::move(tree)), files_(files), bytes_(bytes) {}

void StagedTree::remove() noexcept {
    if (root_.empty()) return;
    std::error_code ignored;
    fs::remove_all(root_, ignored);
    root_.clear();
}

StagedTree::~StagedTree() { remove(); }

StagedTree::StagedTree(StagedTree&& other) noexcept
    : root_(std::move(other.root_)), tree_(std::move(other.tree_)),
      files_(other.files_), bytes_(other.bytes_) { other.root_.clear(); }

void StagedTree::close() {
    if (root_.empty()) return;
    std::error_code error;
    fs::remove_all(root_, error);
    if (error) throw std::runtime_error("Cannot clean the staged native snapshot: " + error.message());
    root_.clear();
}

StagedTree materialize_staged_tree(const fs::path& checkout, const std::string& tree,
                                   const fs::path& artifact_parent, const GitReader& git) {
    const auto format = format_of(tree);
    require(checkout.is_absolute() && fs::canonical(checkout) == checkout &&
                artifact_parent.is_absolute() && fs::canonical(artifact_parent) == artifact_parent &&
                !within(checkout, artifact_parent),
            "Keep the staged native snapshot in a canonical external artifact family.");
    for (const auto& component : artifact_parent)
        require(component != ".git" && component != ".beads",
                "Keep the staged native snapshot outside Git and private tracker administration.");
    struct stat parent{};
    require(::lstat(artifact_parent.c_str(), &parent) == 0 && S_ISDIR(parent.st_mode) &&
                parent.st_uid == ::geteuid() && (parent.st_mode & 0077) == 0,
            "The staged native artifact family must be private and owned.");

    const auto listing = git({"ls-tree", "-rz", "--full-tree", tree});
    require(listing.exit_code == 0, "Cannot list the immutable staged native tree.");
    const auto parsed = validation::parse_listing(listing.output, format);
    require(parsed.manifest.has_value(), "The immutable staged native tree has unsafe or unsupported entries.");
    require(!parsed.manifest->entries().empty(), "The immutable staged native tree is empty.");

    std::string pattern = (artifact_parent / ("staged-" + tree.substr(0, 12) + "-XXXXXX")).string();
    require(::mkdtemp(pattern.data()) != nullptr, "Cannot create a private staged native snapshot.");
    StagedTree snapshot(pattern, tree, 0, 0);
    std::size_t total = 0;
    std::size_t files = 0;
    for (const auto& entry : parsed.manifest->entries()) {
        const auto blob = git({"cat-file", "blob", entry.object_id});
        require(blob.exit_code == 0 && blob.output.size() <= maximum_staged_blob_bytes &&
                    blob.output.size() <= maximum_staged_source_bytes - total,
                "A staged native blob is missing or exceeds the source allowance.");
        const auto destination = snapshot.root() / entry.path;
        fs::create_directories(destination.parent_path());
        std::ofstream stream(destination, std::ios::binary | std::ios::trunc);
        require(static_cast<bool>(stream), "Cannot create a staged native source file.");
        stream.write(blob.output.data(), static_cast<std::streamsize>(blob.output.size()));
        stream.close();
        require(static_cast<bool>(stream), "Cannot write a complete staged native source file.");
        fs::permissions(destination, entry.mode == "100755"
            ? fs::perms::owner_all | fs::perms::group_read | fs::perms::group_exec |
                  fs::perms::others_read | fs::perms::others_exec
            : fs::perms::owner_read | fs::perms::owner_write |
                  fs::perms::group_read | fs::perms::others_read,
            fs::perm_options::replace);
        total += blob.output.size();
        ++files;
    }
    snapshot.files_ = files;
    snapshot.bytes_ = total;
    return StagedTree(std::move(snapshot));
}

} // namespace factory::commit_gate
