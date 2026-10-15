# Named candidate trial permission packet

Status: proposal for `factory-yau.3.7`, based on `f06ffaa`. Preparation performed
2026-10-15 UTC. No runtime artifact was fetched, engine executed, dependency
installed, or game code built. This packet requests a possible bounded experiment;
it grants no trial permission and selects no production engine or language.

The user decision is `factory-yau.3.2`. The [core brief](authoritative-core-trial.md)
and [common witness](prototype-witness.md) remain the experiment contracts.

## Proposed option A

Request one Linux x86_64 **Godot 4.7.2-stable standard editor + separate C11 core +
small direct-C GDExtension adapter** trial. Use the installed GCC 11 toolchain;
compile the same core source into a native headless check executable and the
adapter's shared library. Thin Godot scene/GDScript glue supplies intent and displays
results, without a second recipe/quantity implementation. C11 is proposed only
for this experiment, not chosen for the game.

This route can expose whether a portable rule owner feeds a real engine consumer
without requiring a new toolchain or engine source build. Direct C binding has a
real ergonomics cost: Godot's official example warns that it is verbose and
primarily illustrates binding implementation. Its convenient build uses SCons;
the direct GCC commands below are a proposed Linux adaptation, not a tested
official build recipe. Stop if that adaptation exceeds the budget; do not grow a
binding framework to rescue the experiment.
[Official C example](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/gdextension_c_example.html)

The initial result covers one authoritative command/quantity mechanic, native
headless execution, the same rule through Godot headless and a primitive 3D scene,
one failure witness, and a bounded edit/build/run loop. It can begin W-authority
and exact-material observations. It does not complete the combined witness,
moving character/collision integration, two clients, save/rejoin, a chapter,
exported distribution, or any game-scale performance claim. Those retain their
own tasks, budgets, and integration gates.

## Verified official inputs

| Input | Observation checked during preparation | Consequence |
| --- | --- | --- |
| Standard Linux release | The official Linux page and archive name 4.7.2-stable, released 2026-08-18. | Pin that version; do not substitute a preview, .NET package, or later version silently. [Download page](https://godotengine.org/download/linux/), [release archive](https://godotengine.org/download/archive/4.7.2-stable/) |
| Binary package | Official release API lists `Godot_v4.7.2-stable_linux.x86_64.zip`: **77,860,424 bytes**. A redirect-following HTTP HEAD independently returned 200 and that content length. No body was fetched. | About 74.2535 MiB compressed; expanded size remains unmeasured. [Release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), [API metadata](https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.2-stable) |
| Integrity identity | API asset digest is `sha256:cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`. | Verify exact length and digest before extraction/execution. Reconcile changed metadata rather than accepting a different artifact. |
| Native integration | GDExtension loads native shared libraries without rebuilding the engine. The direct-C example needs no godot-cpp checkout and obtains interface metadata from the executable. | No godot-cpp, SCons, package-manager install, or engine compilation is included in A. [GDExtension](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html) |
| CLI consumers | Official help documents headless mode, project/scene/script selection, interface/API dumps and import. It also warns that unknown options may be ignored. | Inspect the downloaded binary's help and verify actual output/assertions, not merely a zero exit code. [CLI reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) |
| Graphics and storage | The official baseline describes simple-project requirements and separate export templates; Compatibility rendering requires OpenGL 3.3. | Installed libraries/display variables do not prove WSL graphics works. No export templates are included. Published generic storage figures are not measurements of this trial. [Requirements](https://docs.godotengine.org/en/stable/about/system_requirements.html) |

Pinned artifact URL, for later approved use only:

```text
https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
```

## Read-only local inventory

Observed in the assigned worktree on Linux x86_64, Ubuntu packages, approximately
02:28–02:31 UTC. Inventory used PATH lookup, symlink resolution, package records,
filesystem metadata, and `/proc` text. No compiler, engine, .NET/Rust launcher,
installer, or bootstrap shim was invoked.

| Item | Observed status |
| --- | --- |
| C/C++ | `/usr/bin/gcc` and `/usr/bin/g++` resolve to GCC/G++ 11; installed version 11.4.0. Development libc and libstdc++ packages exist. A uses the explicit GCC 11 executable, not an inferred default Clang pair. |
| Other build tools | CMake 3.22.1, Ninja 1.10.1, Make 4.3; present but not required by A's initial direct-compiler route. |
| Runtime/retrieval tools | `/usr/bin/python3.10` package version 3.10.12, curl 7.81.0, Git 2.34.1; standard-library `zipfile.py`, `timeout` and `sha256sum` files present. No unzip command was found; Python can inspect/extract the approved archive later. |
| Not found on PATH | `godot`, `godot4`, `Godot`, `UnrealEditor`, `UnrealEditor-Cmd`, `scons`, `dotnet`, `rustc`, `cargo`. This is not an exhaustive search of every disk or Windows installation. |
| Display hints | `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`, WSLg directories and X11 sockets exist. OpenGL/Vulkan and common X11 runtime packages are installed. No graphics context was created; driver/renderer usability is unknown. |
| CPU/memory preconditions | x86_64 reports SSE4.2; MemAvailable was 121,411,368 kB. This is a preparation snapshot, not a game baseline or allocation. Recheck the 8 GiB reserve before heavy work. |
| Initial disk snapshot | Checkout and `/tmp` share `/dev/sdd`. Available at the initial inventory: **24,672,788,480 bytes = 22.9783 GiB**. |
| Disk refresh, 02:36:05 UTC | Same `/dev/sdd` ext4 filesystem: **159,926,448,128 bytes = about 148.9431 GiB free**. Two successive reads confirmed the increase. This task performed no cleanup; its cause was not investigated. The proposed caps stay unchanged. Recheck again before execution. |

Reproduction of the important reads:

```bash
df -B1 --output=source,size,used,avail,target . /tmp
type -P godot godot4 Godot UnrealEditor UnrealEditor-Cmd gcc g++ scons dotnet rustc cargo
readlink -f /usr/bin/gcc /usr/bin/g++ /usr/bin/python3
dpkg-query -W gcc-11 g++-11 libc6-dev libstdc++-11-dev python3.10 curl git
curl --fail --silent --show-error --max-time 20 \
  https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.2-stable
curl --fail --silent --show-error --head --location --max-time 20 \
  https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
```

Missing-command/package queries can return nonzero while reporting the present
subset; that is inventory evidence, not a failed engine test.

## Proposed hard limits for A

These are requested operational stop limits, not measured costs or approved
capacity. The official package bytes are verified; extraction, caches, build
outputs, adapter effort, and startup remain estimates bounded by the limits.

| Allowance | Proposed limit and treatment |
| --- | --- |
| New downloads | **100 MiB total**, one attempt at the one pinned ZIP; automatic retries off. No additional packages, SDKs, bindings, export templates, assets, or source clones. A partial/failed transfer is charged to the allowance; stop instead of automatically retrying. |
| ZIP retained during extraction | 96 MiB, including partial artifact/metadata space; known ZIP fits. No duplicate archive copy. |
| Unpacked engine | 512 MiB cap. Inspect ZIP entries and declared expanded length after download but before extraction. Reject a size above the cap or unexpected/unsafe entries. Actual size is unknown now. |
| Project import/editor/user/shader caches and temporary files | 384 MiB, including data/settings/cache relocated into the trial's owned artifact area. No imported third-party content. |
| Native objects, executable and shared-library outputs | 128 MiB, single configuration; no engine build or second toolchain. |
| Source, manifest, generated interface header/API JSON | 32 MiB. No broad binding generation or catalogue. |
| Logs and review evidence | 128 MiB. Plain logs and small labelled captures; no unbounded movie capture. |
| Unallocated contingency inside the trial | 256 MiB; using it requires a recorded category adjustment, never raising the total. |
| Peak new disk total | **1,536 MiB = 1.5 GiB**, counting all categories simultaneously, including archive plus unpacked engine. |
| Setup and iteration | **120 minutes elapsed after the first admitted setup action**, including retrieval, adapter implementation, first startup and checks. Setup/retrieval first phase at most 30 minutes; at most three edit/build/run cycles. Report the failed boundary at the cap. |
| Individual operations | Retrieval at most 15 minutes; each native compiler invocation at most 2 minutes; each headless assertion run at most 30 seconds; import or visual inspection at most 3 minutes each. These are operational timeouts, not game speed targets. |

The start condition is at least **22 GiB free** on the affected filesystem:
20 GiB existing floor + 1.5 GiB peak allowance + **0.5 GiB extra headroom**.
The initial free-space snapshot passes that arithmetic with about 0.9783 GiB
spare. After a full 1.5 GiB increase, it would leave about 21.4783 GiB. The later
148.9431 GiB reading also passes; it grants no larger allowance or new work.
This is conditional feasibility, not a reservation or an assurance that another
process will not use space. If current capacity cannot preserve the floor and
headroom, defer; do not delete other artifacts or lower a floor to admit A.

Record free space and owned-directory usage before/after every phase; retain
time/download counters and stop on a category or total overrun. Cache/output
growth is not automatically bounded by `run_local.py`. If a phase cannot be kept
within the approved limits, do not launch it as though the wrapper were a quota
system. Use supported-tool eight-job settings; direct GCC below is a single
compiler invocation. Timing comparisons, if later requested, need separate
benchmark admission and quiet-period evidence.

## Intended execution sequence, only after approval

The approval record must name owner, reviewed proposal/witness revisions, a
fresh current-main trial worktree, explicit absolute source/artifact paths,
budget counters, and allowed commands. Immediately link the new worktree's
`.beads`. Do not merge/rebase a live linked worktree to reach main: `factory-wj6.4`
remains open. The integration owner owns any source-only integration.

Below, `resource_runner` is the absolute approved checkout's `scripts/run_local.py`;
`trial_root` is its proposed `experiments/godot-c-core` source directory;
`artifact_root` is a separately named, trial-owned directory on the measured
filesystem; `godot_trial_binary` is the pinned extracted binary's absolute path.
These paths must be filled and checked before running, not guessed from an
untrusted shell environment. The source/project/fixture files below do not exist
yet and are part of the bounded future implementation.

1. Recheck the local inventory, bytes/digest metadata, disk equation, and memory.
   Prepare only the named owned directories; no global PATH/config changes or
   package-manager commands. Relocate Godot data, settings, and caches using
   `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` under `artifact_root`,
   and put temporary files there. Godot documents these Linux overrides.
   [Data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)
2. Fetch exactly the pinned ZIP once under heavy admission. The intended command
   is the following, with the pinned URL above substituted as `artifact_url`:

   ```bash
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 15m \
     /usr/bin/curl --fail --location --retry 0 --max-time 900 \
     --max-filesize 77860424 --output "$artifact_root/Godot_v4.7.2-stable_linux.x86_64.zip" \
     "$artifact_url"
   ```

   Check actual length and `/usr/bin/sha256sum` against the values above. Curl's
   file limit is not aggregate accounting; the owner must retain the byte record.
   Before extraction, inspect entries with `/usr/bin/python3 -B -m zipfile -l`;
   validate total expansion <=512 MiB, the expected binary name, and safe regular
   entry paths/types. Stop on unexpected contents. Extract the verified binary
   only, within the owned area, then make that exact file executable. No archive
   body or central-directory data was inspected by this preparation task.
3. Under the same owned XDG/temp environment, inspect the binary's `--version`
   and `--help` using 30-second timeouts under heavy admission. From a named
   generated-metadata directory, run separately:

   ```bash
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 30s \
     "$godot_trial_binary" --headless --dump-gdextension-interface
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 30s \
     "$godot_trial_binary" --headless --dump-extension-api
   ```

   Verify nonempty expected outputs and version consistency; CLI success alone
   is insufficient. Use that version's header/API facts, not guessed ABI sizes.
4. Implement one small core/manifest/CLI and thin adapter/scene. With directories
   prepared, the intended native build commands are:

   ```bash
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 2m \
     /usr/bin/x86_64-linux-gnu-gcc-11 -std=c11 -O0 -g -Wall -Wextra \
     "$trial_root/core.c" "$trial_root/headless.c" \
     -o "$artifact_root/bin/core-check"
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 2m \
     /usr/bin/x86_64-linux-gnu-gcc-11 -std=c11 -O0 -g -Wall -Wextra -fPIC -shared \
     -I"$artifact_root/generated" "$trial_root/core.c" "$trial_root/adapter.c" \
     -o "$trial_root/project/bin/libfactory_trial.so"
   ```

   The adapter, `.gdextension`, test script and scene are future code. The CLI
   and library use one core implementation; rendering supplies no recipe logic.
   Do not install SCons or silently switch to godot-cpp if the manual route fails.
5. Exercise declared material identities/quantities and outcomes with an
   independent expectation, including the witness's missing, insufficient,
   surplus and equal-total wrong-material cases. The intended consumer commands
   are:

   ```bash
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 30s \
     "$artifact_root/bin/core-check" "$trial_root/fixtures/authority.json"
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 3m \
     "$godot_trial_binary" --headless --path "$trial_root/project" --import
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 30s \
     "$godot_trial_binary" --headless --path "$trial_root/project" \
     --script res://authority_check.gd
   /usr/bin/python3 -B "$resource_runner" heavy -- /usr/bin/timeout 3m \
     "$godot_trial_binary" --path "$trial_root/project" \
     --rendering-method gl_compatibility --scene res://trial.tscn
   ```

   Verify version-specific help, actual state/outcomes, logs and scene behavior.
   These proposed invocations have not been executed. Observe the Compatibility
   renderer first to bound setup, not to select the game's final renderer. A
   driver/display failure is a reported host integration limit, not permission
   to install drivers or substitute a dummy visual pass.
6. At most three bounded edits/runs total; compare one unchanged intent/fixture
   through native CLI, Godot headless and scene-backed single player. Save the
   exact source revision, material ledger, accepted/rejected outcomes, output
   assertions, warning/error logs and iteration observations. Wire real checks
   into the canonical entrypoint as code arrives. Report limits at the end or
   first stop condition; preserve evidence rather than sweeping directories.

The artifact fetch, extraction, compiler and Godot invocations above have not
been run. Only the stated inventory/metadata reads were executed. After approval,
the implementation owner may refine code/file names within the accepted scope,
but changed downloads, routes, dependencies or larger witnesses require a
revised packet rather than an implicit budget increase.

## Choices and honest comparison limits

The user can approve **A only**, defer all executable work, or request another
named packet. A bounded permission should explicitly name its version, C11 trial
language/adapter route with GDScript presentation glue, initial consumers, limits
above, owner and stop conditions.
Completion/review of this document, an agent recommendation, or silence is not
that decision.

An engine-native Godot/GDScript baseline could compare binding effort with engine
coupling. It has not been specified or approved as a second implementation here;
do not quietly replace A's portable core with it and claim the same result.

Unreal remains an alternative, not rejected on game suitability. Epic's Linux
quickstart currently serves Unreal Engine 5.8 documentation, supports installed
or source builds, requires account access for its precompiled ZIP, and describes
a separate compiler setup. No Unreal tool was found on PATH, authenticated
package size/expanded size was not obtained, and no SDK cost is verified. There
is therefore no resource-bounded Unreal execution option in this packet. Do not
guess a download footprint or launch its setup scripts under A's allowance.
[Epic Linux quickstart](https://dev.epicgames.com/documentation/en-us/unreal-engine/linux-development-quickstart-for-unreal-engine)

A's native ABI adaptation, expanded archive footprint, actual shared-library
dependencies, WSL graphics, import/cache size, and implementation effort remain
unproven. If any cannot fit, return the failure and revised options. The verified
small archive and installed compiler make A a concrete candidate for permission;
they do not establish that it will pass or that it is the best production stack.

## Acceptance and next handoff

Preparation acceptance means official metadata/capabilities and local inventory
are traceable, arithmetic and stop limits are reviewable, and uncertainty is
visible. Root must independently review this exact proposal revision before
presenting `factory-yau.3.2`. A future executor must refresh the changing inputs.
Retain the later moving-world, live character/collision, network, save and user
play gates; an initial C/scene join cannot close them. Production selection stays
at `factory-yau.3.5` after combined evidence. No repair to the Beads/worktree
workflow or change to the canonical export policy is included.
