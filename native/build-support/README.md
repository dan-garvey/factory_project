# Bounded native build runner

This opt-in C++ component passed 40 native controls and supervised the corrected
local Bazel validation on 2026-10-20. Its source has independent review. It does
not replace installed admission, commit checks or game launchers, and does not
repair the original incomplete bootstrap or failed setups.

`factory-build-run` runs one explicit command synchronously through an admitted
heavy entry. With the native `factory-local`, pass `--inherit-permits` before `--`;
the older `scripts/run_local.py heavy` entry also passes these descriptors. It requires the inherited heavy and activity
permit files and preserves only those descriptors in the command. Matching their
identities is not a new lock acquisition or proof that an unwrapped caller owns
the lane. All other descriptors above the standard streams are closed. The child
has its own process group, and its leader remains unreaped until group cleanup.
The caller must not install an automatic or competing child reaper.

The command receives only PATH, LANG, an owned empty child HOME, owned
temporary/config/cache paths and explicit build-job limits. No ambient environment
is read or forwarded. The caller's environment is unchanged. Arguments and source
still need a prospective seal; a secret
passed explicitly as an argument would violate that contract. Umask 077 is inherited
by the command. The library changes and restores umask synchronously and must not
be embedded in a multithreaded caller. All engine resources remain out of scope.

The artifact root must be canonical, owned and private. The log is a fresh no-follow
file under it, mode 0600. Combined output is retained there, not forwarded to chat.
Logs stop at the declared bound, with a retained prefix and a failing supervisor
result. Timeouts, cancellation, scan errors and resource failures terminate the
owned group and wait for the direct child. A normal result also cleans the group
before reaping its still-owned leader. A killed host or escaped process group is
outside this cooperative contract.

Accounting opens directories by descriptor and uses no-follow metadata. Normal
cache disappearance or replacement is skipped; permission, I/O, depth and object
count errors refuse. Regular-file and symlink bytes are counted without following
links, including conservative repeated hard-link paths. The scan has a 128-level
and one-million-entry ceiling. Root replacement refuses. This is a periodic,
non-atomic snapshot, not a filesystem quota or same-user attack boundary. Directory
metadata, unrelated paths and bytes written between snapshots are not hard limited.
The sealed output/cache paths must remain inside the owned family.

### Optional owner-mapped accounting

Host scanning remains the default. Bazel 8.4.2 creates an intentionally mode-zero
sandbox helper directory even while registering its Linux strategy, so an ordinary
reader can refuse before any action finishes. The original failed build is
preserved. Selecting a local action strategy alone does not prevent that strategy
registration. Do not skip unreadable directories or change their permissions.

The optional `--accounting-mode owned-user` adapter creates one short-lived
accounting worker per snapshot. Only that worker enters a Linux user namespace,
mapping the caller's own user and primary group to namespace root. The build and
parent stay in their original namespace and identity. No host account, mount,
network, PID namespace or persistent setting is changed. Unsupported namespace
mapping fails closed, without fallback to incomplete accounting.

The worker retains only its owned root descriptor and a fixed-size result pipe;
it closes inherited admission and unrelated descriptors and all standard streams.
It executes no external command, reads no file contents, changes no artifact
permissions and reports only a count or refusal. The same traversal still counts
regular files and symlinks without following links, rejects other object types,
and enforces depth, entry and byte bounds. The parent validates root identity
after the snapshot. Hidden nonempty directories count toward the same limit.

The worker has a separate owned process group, parent-death protection before
and after namespace setup, and bounded result/reap handling. Timeout, cancellation,
short result, mapping failure or unexpected exit refuses and cleans its group.
It owns no further child. Its limit is five seconds or the remaining operation
budget, whichever is smaller. In this optional mode the operation budget includes
initial accounting; it does not extend the child deadline. The synchronous,
single-threaded embedding restriction still applies.

The original one-directory stock-utility diagnostic established only read-only
access on this host. The later native controls cover protected nonempty data,
unchanged modes/identity, repeated snapshots, byte-cap refusal, special objects,
pre-cancellation and a command kept outside the accounting namespace. The corrected
Bazel campaign separately exercised build/cache behavior with this worker. Neither
result activates a game caller or proves whole-host isolation.

Primary API: [Linux user namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html).
The caller mapping is confined to a child process; it is not host-root authority
or whole-host isolation. The first native fixture requires an ordinary, non-root
Linux caller and actual namespace support, and refuses rather than skipping that
requirement. Public consumers that leave the option false retain host accounting.

The CLI ceilings are 300 seconds, 2 GiB artifacts, 8 MiB logs and an eight-job
supported-tool environment. Actual Bazel job flags must also be sealed; this is
not a kernel process quota. A
specific case may impose lower limits; the prospective campaign still has its
separate twenty-minute deadline and 180-second case limits. No new allowance is
created by these ceilings. A nonzero command exit is retained. Expected compiler
or test failures require the explicit `child_exit` result and matching sanitized
Bazel failure evidence; a runner error must never count as an expected build failure.

The package exposes `:runner`, `:factory-build-run` and `:runner_test`. The test uses
invented permit files and values in the Bazel temporary directory, plus disposable
utility children. It covers environment/descriptor isolation, child errors, limits,
cancellation, cache mutation and refusal to replace a log or follow an owned path
outside the family. It is not an engine, gameplay or original-case replay.

Use relevant automated tests and one independent reviewer for changes. Declare
actual commands and resource bounds before execution; this is not a separate
plan-approval gate or permission to repeat passing validation on unchanged inputs.

The prospective commands bind `offline-downloader.cfg`, explicitly select
`--registry=https://bcr.bazel.build`, and use `--repository_disable_download`.
These three conditions belong together: the flag refuses ordinary repository
downloads after cache lookup, while the configuration blocks the separate
Bzlmod registry fallback at the only permitted registry host. Registry selection
and the pinned dependency/source review must exclude alternative registries and
mirror overrides. Verified local content-addressed dependency
archives and registry files may be copied into the new family; old action results,
raw events and generated host configuration are not prospective evidence. A cache
miss refuses instead of authorizing a download. Ordinary archive URLs remain
intact so cache hits keep the basename needed for extraction. Blocking every URL
caused the first prospective setup to retrieve a valid cached archive under an
extensionless synthetic name and then fail archive-type inference. That original
failure remains intact; the corrected local campaign subsequently passed.
This is not a
whole-host network sandbox: arbitrary repository executables remain outside that
setting and must be covered by the pinned dependency/source review.

Primary source: Bazel 8.4.2's [download manager](https://github.com/bazelbuild/bazel/blob/8.4.2/src/main/java/com/google/devtools/build/lib/bazel/repository/downloader/DownloadManager.java)
checks cached content before downloads; its registry path has separate handling.
The [URL rewrite configuration](https://github.com/bazelbuild/bazel/blob/8.4.2/src/main/java/com/google/devtools/build/lib/bazel/repository/downloader/UrlRewriterConfig.java)
supports the host block. These API facts do not establish a whole-host network
sandbox. The `:runner` library is additionally
visible only to `//native/factory-launch`; this package join does not activate a
launcher or change the command environment, lifetime or limits.
