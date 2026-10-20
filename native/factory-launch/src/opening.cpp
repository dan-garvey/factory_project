#include "factory/opening.hpp"
#include "factory/capture.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <fcntl.h>
#include <fstream>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

namespace factory_launch {
namespace {
namespace fs = std::filesystem;
constexpr std::size_t source_limit = 2 * 1024 * 1024;

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void path_shape(const fs::path& path) {
    require(path.is_absolute() && path.lexically_normal() == path,
            "Use absolute normalized opening paths.");
    for (const auto& component : path)
        require(component != ".git" && component != ".beads",
                "Opening paths must exclude private metadata.");
    for (const unsigned char value : path.string())
        require(value >= 0x20 && value < 0x7f,
                "The first native opening adapter requires printable ASCII paths.");
}

bool within(const fs::path& parent, const fs::path& child) {
    const auto relative = child.lexically_relative(parent);
    return relative.empty() || (!relative.is_absolute() && *relative.begin() != "..");
}

std::string read(const fs::path& path, std::size_t limit = source_limit) {
    require(fs::is_regular_file(fs::symlink_status(path)), "Opening inputs must be regular files.");
    const auto bytes = fs::file_size(path);
    require(bytes <= limit, "An opening input exceeds its byte allowance.");
    std::ifstream file(path, std::ios::binary);
    require(static_cast<bool>(file), "Cannot read an opening input.");
    std::string result(static_cast<std::size_t>(bytes) + 1, '\0');
    file.read(result.data(), static_cast<std::streamsize>(result.size()));
    require(!file.bad() && static_cast<std::size_t>(file.gcount()) == bytes,
            "The opening input changed during its read.");
    result.resize(static_cast<std::size_t>(bytes));
    return result;
}

void write_extension_catalogue(const fs::path& runtime, const fs::path& descriptor) {
    const auto cache = runtime / ".godot";
    require(fs::create_directory(cache), "The generated extension cache must be fresh.");
    fs::permissions(cache, fs::perms::owner_all);
    struct Descriptor {
        int value;
        ~Descriptor() { if (value >= 0) ::close(value); }
    } directory{::open(cache.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)};
    require(directory.value >= 0, "Cannot open the fresh extension cache.");
    Descriptor output{::openat(directory.value, "extension_list.cfg",
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600)};
    require(output.value >= 0 && ::fchmod(output.value, 0600) == 0,
            "Cannot create the fresh extension catalogue.");
    const auto content = "res://" + descriptor.generic_string() + '\n';
    std::size_t offset = 0;
    while (offset < content.size()) {
        const auto count = ::write(output.value, content.data() + offset, content.size() - offset);
        if (count < 0 && errno == EINTR) continue;
        require(count > 0, "Cannot finish the generated extension catalogue.");
        offset += static_cast<std::size_t>(count);
    }
    require(::fsync(output.value) == 0 && ::fsync(directory.value) == 0,
            "Cannot retain the generated extension catalogue.");
}

void verify_extension_catalogue(const OpeningExternalResource& descriptor) {
    const auto& relative = descriptor.relative;
    require(!relative.empty() && !relative.is_absolute() && relative.lexically_normal() == relative &&
            relative.extension() == ".gdextension", "The catalogue requires a relative extension descriptor.");
    for (const auto& component : relative)
        require(component != "." && component != ".." && component != ".godot" &&
                component != ".git" && component != ".beads", "The descriptor path cannot escape its project.");
    auto runtime = descriptor.runtime;
    for (auto part = relative.begin(); part != relative.end(); ++part) runtime = runtime.parent_path();
    require(runtime.is_absolute() && fs::canonical(runtime) == runtime && runtime / relative == descriptor.runtime,
            "The descriptor must remain inside its original runtime project.");
    const auto cache = runtime / ".godot";
    const auto catalogue = cache / "extension_list.cfg";
    require(fs::is_directory(fs::symlink_status(cache)) && fs::canonical(cache) == cache &&
            fs::status(cache).permissions() == fs::perms::owner_all,
            "The generated extension cache changed its path or mode.");
    struct stat status{};
    require(::lstat(catalogue.c_str(), &status) == 0 && S_ISREG(status.st_mode) &&
            status.st_nlink == 1 && status.st_uid == ::geteuid() && (status.st_mode & 07777) == 0600,
            "The generated extension catalogue changed its type, ownership or mode.");
    require(read(catalogue, 64 * 1024) == "res://" + relative.generic_string() + '\n',
            "The generated catalogue differs from the pinned descriptor entry.");
}

std::vector<OpeningSource> roster(const fs::path& root) {
    std::vector<OpeningSource> result;
    std::size_t bytes = 0, scripts = 0, entries = 0;
    for (const auto& entry : fs::recursive_directory_iterator(root)) {
        require(++entries <= 1024, "The opening source directory exceeds its entry allowance.");
        const auto relative = entry.path().lexically_relative(root);
        require(std::distance(relative.begin(), relative.end()) <= 32,
                "The opening source directory is too deep.");
        for (const auto& component : relative)
            require(component != ".git" && component != ".beads" && component != ".godot",
                    "The pristine opening cannot include metadata or generated caches.");
        const auto status = entry.symlink_status();
        if (fs::is_directory(status)) continue;
        require(fs::is_regular_file(status), "Refuse opening symlinks and nonregular entries.");
        require(result.size() < 512, "The opening exceeds its source-file allowance.");
        const auto content = read(entry.path());
        require(content.size() <= source_limit - bytes, "The opening exceeds its total source allowance.");
        bytes += content.size();
        if (entry.path().extension() == ".gd") ++scripts;
        require(scripts <= 128, "The opening exceeds its script allowance.");
        result.push_back({relative, sha256(content), content.size(), status.permissions()});
    }
    std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) {
        return a.relative < b.relative;
    });
    require(scripts > 0 && fs::is_regular_file(fs::symlink_status(root / "project.godot")) &&
            fs::is_regular_file(fs::symlink_status(root / "opening/opening.tscn")),
            "The capture must include the actual offline opening scene and project.");
    return result;
}
} // namespace

OpeningCopy copy_opening_project(const fs::path& original, const fs::path& runtime) {
    path_shape(original);
    path_shape(runtime);
    require(fs::is_directory(original) && fs::canonical(original) == original &&
            fs::is_directory(runtime.parent_path()) && fs::canonical(runtime.parent_path()) == runtime.parent_path(),
            "Opening source and output parent must be canonical directories.");
    require(!within(original, runtime) && !within(runtime, original),
            "Pristine and runtime project directories must be separate.");
    require(!fs::exists(fs::symlink_status(runtime)), "The runtime project must be fresh.");
    OpeningCopy result{original, runtime, roster(original)};
    require(fs::create_directory(runtime), "Cannot create the fresh runtime project.");
    fs::permissions(runtime, fs::perms::owner_all);
    for (const auto& source : result.sources) {
        const auto destination = runtime / source.relative;
        fs::create_directories(destination.parent_path());
        require(fs::copy_file(original / source.relative, destination, fs::copy_options::none),
                "Cannot copy an immutable opening input.");
        fs::permissions(destination, source.permissions);
    }
    verify_opening_sources(result);
    return result;
}

void verify_opening_sources(const OpeningCopy& copy) {
    require(fs::canonical(copy.original) == copy.original && fs::canonical(copy.runtime) == copy.runtime,
            "Opening project roots changed identity or became aliases.");
    const auto pristine = roster(copy.original);
    require(pristine.size() == copy.sources.size(), "The pristine source closure changed.");
    for (std::size_t i = 0; i < copy.sources.size(); ++i) {
        const auto& source = copy.sources[i];
        require(pristine[i].relative == source.relative && pristine[i].sha256 == source.sha256 &&
                pristine[i].bytes == source.bytes && pristine[i].permissions == source.permissions,
                "The pristine source changed after capture.");
        const auto runtime = copy.runtime / source.relative;
        // Canonical parent validation prevents an import from redirecting an
        // original source into a generated directory or external symlink.
        require(fs::canonical(runtime.parent_path()) == runtime.parent_path() &&
                fs::symlink_status(runtime).permissions() == source.permissions &&
                sha256(read(runtime)) == source.sha256,
                "An original runtime source changed during import or startup.");
    }
}

OpeningResume copy_opening_resume(const fs::path& original, const fs::path& incoming) {
    path_shape(original);
    path_shape(incoming);
    require(fs::canonical(original) == original &&
            fs::is_directory(incoming.parent_path()) &&
            fs::canonical(incoming.parent_path()) == incoming.parent_path(),
            "Resume input and destination parent must be canonical.");
    require(original != incoming && !fs::exists(fs::symlink_status(incoming)),
            "The resume copy must be a fresh separate file.");
    const auto content = read(original);
    require(!content.empty(), "The resume binary must not be empty.");
    OpeningResume result{original, incoming, sha256(content), content.size(),
                         fs::symlink_status(original).permissions()};
    require(fs::copy_file(original, incoming, fs::copy_options::none),
            "Cannot preserve the original resume binary.");
    fs::permissions(incoming, fs::perms::owner_read);
    verify_opening_resume(result);
    return result;
}

void verify_opening_resume(const OpeningResume& resume) {
    require(fs::canonical(resume.original) == resume.original &&
            fs::canonical(resume.incoming) == resume.incoming &&
            fs::symlink_status(resume.original).permissions() == resume.original_permissions &&
            fs::symlink_status(resume.incoming).permissions() == fs::perms::owner_read,
            "The original resume input or read-only copy changed path or mode.");
    const auto original = read(resume.original);
    const auto incoming = read(resume.incoming);
    require(original.size() == resume.bytes && incoming.size() == resume.bytes &&
            sha256(original) == resume.sha256 && sha256(incoming) == resume.sha256,
            "The original resume binary or incoming copy changed.");
}

std::vector<OpeningExternalResource> copy_opening_extension(
    const OpeningCopy& copy, const OpeningExtensionInputs& inputs) {
    verify_opening_sources(copy);
    require(!fs::exists(fs::symlink_status(copy.runtime / ".godot")),
            "Declare the extension before import in a fresh generated cache.");
    const std::array sources{inputs.descriptor, inputs.library};
    const std::array targets{inputs.descriptor_relative, inputs.library_relative};
    const std::array pins{inputs.descriptor_sha256, inputs.library_sha256};
    require(targets[0].extension() == ".gdextension" && targets[1].extension() == ".so",
            "Use an explicit GDExtension descriptor and Linux shared-library destination.");
    std::vector<OpeningExternalResource> resources;
    for (std::size_t i = 0; i < sources.size(); ++i) {
        const auto& source = sources[i];
        const auto& relative = targets[i];
        path_shape(source);
        require(fs::canonical(source) == source, "Native resource inputs must be canonical.");
        require(!relative.empty() && !relative.is_absolute() && relative.lexically_normal() == relative &&
                std::distance(relative.begin(), relative.end()) <= 32,
                "Native resource destinations must be normalized project-relative paths.");
        for (const auto& component : relative)
            require(component != "." && component != ".." && component != ".git" &&
                    component != ".beads" && component != ".godot",
                    "Native resources cannot target private metadata, caches or parent paths.");
        path_shape(copy.runtime / relative);
        const auto content = read(source, i == 0 ? 64 * 1024 : 64 * 1024 * 1024);
        require(!content.empty() && sha256(content) == pins[i],
                "A native resource differs from its explicit SHA256 pin.");
        const auto destination = copy.runtime / relative;
        const auto tracked = std::find_if(copy.sources.begin(), copy.sources.end(), [&](const auto& value) {
            return value.relative == relative;
        });
        const bool captured = tracked != copy.sources.end();
        require(!captured || (i == 0 && tracked->sha256 == pins[i]),
                "Native resources cannot replace captured project sources.");
        if (!captured) {
            require(!fs::exists(fs::symlink_status(destination)),
                    "Native resource destinations must be fresh.");
            fs::create_directories(destination.parent_path());
            require(fs::canonical(destination.parent_path()) == destination.parent_path(),
                    "Native resources cannot follow runtime directory aliases.");
            require(fs::copy_file(source, destination, fs::copy_options::none),
                    "Cannot copy the pinned native resource.");
            fs::permissions(destination, fs::perms::owner_read);
        }
        resources.push_back({source, destination, relative, pins[i], content.size(),
                             fs::symlink_status(source).permissions(),
                             fs::symlink_status(destination).permissions()});
    }
    verify_opening_sources(copy);
    write_extension_catalogue(copy.runtime, inputs.descriptor_relative);
    verify_opening_extension(resources);
    return resources;
}

void verify_opening_extension(const std::vector<OpeningExternalResource>& resources) {
    require(resources.size() == 2, "Verify both native extension resources together.");
    for (const auto& resource : resources) {
        require(fs::canonical(resource.original) == resource.original &&
                fs::canonical(resource.runtime) == resource.runtime &&
                fs::symlink_status(resource.original).permissions() == resource.original_permissions &&
                fs::symlink_status(resource.runtime).permissions() == resource.runtime_permissions,
                "A native extension resource changed its path or mode.");
        const auto original = read(resource.original, 64 * 1024 * 1024);
        const auto runtime = read(resource.runtime, 64 * 1024 * 1024);
        require(original.size() == resource.bytes && runtime.size() == resource.bytes &&
                sha256(original) == resource.sha256 && sha256(runtime) == resource.sha256,
                "A native extension resource changed after it was pinned.");
    }
    verify_extension_catalogue(resources.front());
}

OpeningCommands opening_commands(const fs::path& engine, const fs::path& project,
                                 const fs::path& save_slot, const fs::path& resume_input) {
    path_shape(engine);
    path_shape(project);
    path_shape(save_slot);
    require(engine != save_slot && !within(project, engine) && !within(project, save_slot),
            "Engine and save output must be separate from the captured project.");
    OpeningCommands result{{engine.string(), "--headless", "--path", project.string(), "--editor", "--import", "--quit"},
            {engine.string(), "--headless", "--path", project.string(), "res://opening/opening.tscn",
             "--quit-after", "60", "--", "--save-slot=" + save_slot.string()}};
    if (!resume_input.empty()) {
        path_shape(resume_input);
        require(resume_input != engine && resume_input != save_slot && !within(project, resume_input),
                "Resume input must be separate from the engine, project and new save slot.");
        result.startup.push_back("--resume-input=" + resume_input.string());
    }
    return result;
}
} // namespace factory_launch
