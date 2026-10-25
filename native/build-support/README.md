# Bounded native build runner

`factory-build-run` runs one command synchronously with an inherited heavy
permit. Use `factory-local heavy --inherit-permits --`; do not nest admission.
See the complete [build recipe](../../docs/engineering/native-builds.md).

Options before `-- COMMAND...` are `--artifacts`, `--log`,
`--admission-directory`, `--accounting-mode host|owned-user`, `--seconds`,
`--artifact-bytes`, `--log-bytes` and `--jobs`. Ceilings are 300 seconds,
2 GiB artifacts, 8 MiB logs and eight supported-tool jobs.

The canonical artifact root is owned/private; the log must be fresh and
no-follow. The runner supplies an allowlisted child environment, private
temporary/config/cache locations, umask 077 and job limits without altering the
caller's environment. Arguments must not contain secrets. Only verified permit
descriptors survive beyond standard streams.

The owned child process group is cleaned before reaping its leader on success,
failure, timeout or cancellation. Log truncation, accounting errors and exceeded
limits fail while retaining diagnostics. Escaped processes and a killed host
are outside this cooperative boundary. Embedding is synchronous/single-threaded;
do not install a competing child reaper.

Accounting counts regular files and symlinks without following links, conservatively
including repeated hard-link paths. It tolerates normal cache disappearance,
but refuses I/O/permission errors, root replacement, excess depth/entries and
unsupported types. Scans are periodic snapshots, not quotas.

Bazel may create mode-zero sandbox directories. Optional `owned-user` accounting
uses a short-lived Linux user-namespace worker mapping only the caller's identity;
the build remains outside that namespace. Unsupported mappings refuse without
fallback. The worker reads metadata only, changes no permissions and has a
five-second or remaining-operation timeout.

Keep `--batch` Bazel, cache/output paths inside the family, exact toolchain/source
provenance and all three offline download settings in the central recipe.
A runner failure is not an expected compiler failure.
Targets: `//native/build-support:factory-build-run`, `:runner`, `:runner_test`.
The host test uses disposable utilities and permits, not game acceptance.
