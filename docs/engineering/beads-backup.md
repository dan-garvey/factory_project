# Portable Beads backup

The canonical tracker is private and Git-ignored. The user authorized an existing
**unlisted GitHub gist** for its portable text export; anyone with its URL can
access it. Keep the identifier, credentials and account telemetry out of source
and issue comments. Backups are separate serialized operations, not a schedule.

## Configuration and use

Use existing `gh` authentication with gist write permission. The local JSON file
must be user-owned, mode 0600, reached without symlinks, and outside worktrees.
The supported Git-admin location is
`<common-git-dir>/factory-ops/beads-backup.json`. It contains exactly:

```json
{"gist_id":"<existing ID>","root":"<absolute main checkout>","visibility":"unlisted"}
```

```bash
python3 -B scripts/backup_beads.py --config /absolute/private/beads-backup.json
```

This existing implementation remains in use during native tooling migration.
It flushes canonical Beads and uploads only `issues.jsonl`, `config.yaml` and
`metadata.json` to the configured existing gist. It requires nonpublic visibility,
exact filenames, valid nonempty export, and full SHA-256 readback. Files warn at
6 MiB and refuse above 8 MiB; they are never truncated. No database, WAL, locks,
account telemetry, Git history or other files are uploaded.

A truncated API file list refuses. Truncated file content is read only from the
same gist/file at a pinned 40-hex revision on `gist.githubusercontent.com`,
without credentials, cookies or redirects. Socket/body deadlines are bounded
but not strict whole-network time limits. The tool is not a secret scanner:
keep sensitive material out of tracker prose and configuration.

Failure is nonzero and never reports verified backup. A timed-out update or
readback may follow a real remote change; inspect before retrying. The tool
does not create gists, alter authentication, replace the database or delete
history. Changes after the flushed export need a later backup.

## Restore

Download the three files privately and verify visibility, complete content,
hashes and export validity. In a new disposable standalone directory outside
all worktrees, initialize `br init --prefix factory`, place the reviewed files
in its `.beads`, then run `br sync --import-only`. Compare representative IDs,
fields, dependencies and comments with the export. Never run this drill against
canonical `.beads` or a shared symlink.

Preserve the original tracker, exports and gist throughout. Live replacement
belongs to the integration owner. The export does not retain SQLite-only
runtime/audit state; it and settings are separate reads. Record actual restore
evidence and backup freshness in Beads; mocked tooling tests do not prove live
recoverability. Keep the destination discoverable through the owner's account.
