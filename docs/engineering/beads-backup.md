# Portable Beads gist backup

The user chose an unlisted GitHub gist for the text-based tracker backup. All
`.beads` files remain local and ignored in project Git; linked worktrees continue
to share the main checkout's directory/database. This updater does not create a
gist, initialize a database, change authentication, or operate on Git history.

The integration owner seeds and restore-tests the approved gist separately.
Keep its ID/URL and account telemetry out of public source, issue comments and
routine logs. [Unlisted gists are accessible to anyone with their URL](https://docs.github.com/en/get-started/writing-on-github/editing-and-sharing-content-with-gists/creating-gists);
they are not access-controlled private storage.

## Configuration and use

Use existing `gh` authentication with gist write permission. The private local
JSON configuration has exactly these keys, with real values supplied locally:

```json
{"gist_id": "<existing hexadecimal gist ID>", "root": "<absolute main checkout>", "visibility": "unlisted"}
```

The file must be owned by the current user, mode `0600`, and reached without
symlinks. Store it outside all registered project worktrees. The explicitly
supported Git-admin exception is the main checkout's
`.git/factory-ops/beads-backup.json`, which the integration owner configured.
No configuration file, ID, URL, credential or downloaded gist belongs in source
control. The updater pins API calls to `github.com`.

From any project checkout:

```bash
python3 -B scripts/backup_beads.py --config /absolute/private/beads-backup.json
```

For the configured Git-admin location, pass the absolute common Git directory
followed by `/factory-ops/beads-backup.json`. Do not copy the private configuration
into a linked worktree. Backups are separate, serialized manual operations with
no automatic schedule or retry. The hourly PM timer is retired; disabling it
does not create a backup schedule or authorize an upload outside the existing
privacy and export constraints.

The updater resolves the main checkout through Git, validates metadata paths,
and runs `br sync --flush-only` with the explicit canonical database and without
force flags or `BEADS_` environment overrides. It then reads exactly
`issues.jsonl`, `config.yaml` and
`metadata.json` from canonical `.beads`. It accepts regular UTF-8 text files of
at most 8 MiB each, valid nonempty JSONL with unique Factory IDs/titles, and
metadata naming `beads.db`/`issues.jsonl`. At 6 MiB (75% of the cap) it warns to
review export growth; above 8 MiB it stops before upload, never truncates.
Configuration YAML is copied as text, not parsed. Review what is written into
issues/configuration before authorizing remote storage. There is no generic
content secret detector: ordinary task discussion of token/credential handling
is valid, and the filename allowlist cannot make sensitive issue prose safe.
Keep actual credentials and account telemetry out of the tracker.

The tool GETs the explicitly configured existing gist, requires `public=false`
and exactly those three filenames, then PATCHes those file contents in one
request. It reads the gist back with a separate GET, rechecks visibility and
filenames, and compares each complete UTF-8 file's SHA-256 against the submitted
bytes. A truncated **file list** still fails: the allowlist is not verified.
For file-level content truncation, read the API's `raw_url` only if it names the
same configured gist/file at a fixed 40-hex revision on
`https://gist.githubusercontent.com`. Reject other hosts, credentials, ports,
queries, fragments, unpinned paths and redirects. The raw request sends no
account authentication or cookies, uses bounded binary chunks before UTF-8
decoding, and rejects over-limit, malformed or mismatched content. It has a
10-second socket inactivity timeout and a 30-second deadline checked after
connection setup and between body reads. DNS, HTTP headers and chunk framing can
overrun that deadline before control returns; this is not a strict total network
time bound. The byte limits remain enforced on returned body data. These are
cooperating network checks, not a host quota or guarantee of availability.

GitHub documents up to 1 MB of inline API content per file, full `raw_url`
retrieval above that, and cloning for files larger than 10 MB. The 8 MiB bound
stays below the clone-only range. No new gist, clone, sharded format or restore
migration is required; the same three portable files remain the backup.
Success prints only a UTC verification timestamp. API output, ledger contents
and gist identifiers/URLs are not printed. See the
[GitHub Gists API truncation contract](https://docs.github.com/en/rest/gists/gists#truncation).

## Failure, freshness and restore

A flush, validation, authentication, upload or readback failure exits nonzero and
does not report a verified backup. A failed/timed-out PATCH or readback can follow
an actual remote update: inspect the configured gist before retrying. Source
database and Git index are never copied, replaced, imported or reset by this
tool. A flush can update the local portable export through Beads' normal rules.
The tool never deletes gist files/revisions or performs retention cleanup.

The backup includes issues, comments and relationships represented in the
portable export plus the two named tracker settings files. It excludes the live
SQLite database, WAL/SHM, `.br_history`, locks, transient state and account
telemetry. It does not promise preservation of SQLite-only audit/runtime state.
The export is coherent as produced by `br`; the settings and export are separate
reads, not an atomic cross-file/database snapshot. Changes after that export
need a later backup. A success timestamp is not continuous protection, and local
config loss, GitHub availability, access loss or concurrent visibility changes
remain recovery limits. Keep the destination discoverable through the owner's
GitHub account independently of this machine.

For a restore drill, download the three named files privately, check visibility,
truncation and hashes, and validate the export. Use a new standalone disposable
directory outside every project worktree; never point it at canonical `.beads`
or a shared symlink. Initialize its independent tracker with `br init --prefix
factory`, place the reviewed portable files in that new tracker's `.beads`, then
run `br sync --import-only` there. Inspect representative `br show` records and
compare IDs, scalar fields, dependencies and comments with the downloaded
export. Preserve the original database, exports and gist throughout. Actual
replacement of a live tracker is a separate integration-owner operation.

`tests/test_beads_backup.py` uses disposable files and fake `br`/`gh` executables,
including linked-checkout source resolution, flush/upload order, visibility,
payload allowlisting, private paths and failures, and full readback of a
simulated >1 MB UTF-8 export. Additional tests distinguish file/list truncation,
reject unsafe raw URLs without network access, and cover raw transport,
deadline/size/text failures, redirects and authentication-header absence.
It performs no real GitHub writes and no real tracker import. The owner records
the actual seeded-gist restore evidence and latest successful backup privately
in Beads after integration; fixture checks alone do not establish recoverability
of the live tracker.
