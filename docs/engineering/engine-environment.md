# Demo environment comparison and first sandbox

Checked 2026-10-15 UTC. User authority: evaluate UE5 and promising free 3D options,
choose a promising reversible route, and establish a sandbox/tests; **prototyping,
not lock-in**. PM recorded trial permission separately from production adoption.
The current target begins collector → machine → product with placeholder art;
later moving factories and responsive multiplayer remain architecture risks.

## Comparison

| Environment | Useful capabilities / cost terms from official sources | Host/setup and judgment for this demo |
| --- | --- | --- |
| **Godot 4.7.2 standard** | Self-contained Linux editor, built-in 3D, scripts and headless CLI; MIT licensed. [Download](https://godotengine.org/download/linux/), [license](https://godotengine.org/license/), [CLI](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) | No SDK/account/global install needed for this GDScript route. Actual renderer + common-rule headless/scene tests now run here. Best first experiment in my judgment because the setup is small and the feedback loop is directly scriptable. No factory-scale or moving-player result yet. |
| **UE5** | Blueprint visual gameplay authoring and a C++/functional/screenshot automation system. Free game development under Epic's published royalty terms, rather than an open-source permissive license. [Blueprints](https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprints-visual-scripting-in-unreal-engine), [tests](https://dev.epicgames.com/documentation/en-us/unreal-engine/automation-test-framework-in-unreal-engine), [terms overview](https://www.unrealengine.com/license) | Serious challenger for richer 3D authoring and later character/physics/network joins. Linux precompiled builds require Epic sign-in; C++ setup uses a dedicated toolchain. The Linux guide recommends 32 GB RAM, an 8 GB-VRAM GPU and Vulkan. No authenticated package footprint or installed editor was obtained; no UE runtime comparison was run. [Linux setup](https://dev.epicgames.com/documentation/en-us/unreal-engine/linux-development-quickstart-for-unreal-engine) |
| **Unity Personal** | Free eligibility currently requires less than $200K revenue/funding in the preceding 12 months. Linux Hub offers a portable AppImage path as well as packages. [Eligibility](https://unity.com/products/unity-personal), [Linux installation](https://docs.unity.com/en-us/hub/install-hub-linux) | Credible editor-based alternative; eligibility/account setup and editor footprint were not established here. No editor installed or timed. Does not presently offer a demonstrated advantage sufficient to add a second setup before feedback on this small scene. This is a prioritization judgment, not a capability rejection. |
| **Bevy** | Rust ECS library with a 3D renderer, MIT/Apache-2.0 choice. Its own introduction warns about missing features and breaking upgrades. [Features](https://bevy.org/), [stability/license](https://bevy.org/learn/quick-start/introduction/), [setup](https://bevy.org/learn/quick-start/getting-started/) | Promising for data-oriented engine work, but Rust/Cargo are absent on this host's PATH and no Bevy build was attempted. Adding toolchain/build/scene-authoring work is less attractive for the first quick demo; ECS alone proves no game-scale performance. |

Only Godot received executable evidence. UE5 is not rejected for the intended
game: a later comparison should run equivalent stock/accounting, placement,
headless/server and real moving-character cases, recording setup and incremental
iteration costs. Use an already accessible installed build when available, or
establish its real archive/unpack/cache/toolchain budget before setup. Do not
use old UE4 disk figures as a UE5 estimate. No Epic login, EULA acceptance, paid
asset purchase, Unity activation or account setting was performed by this trial.

## Chosen reversible baseline and limits

Use Godot 4.7.2 standard + Compatibility renderer + GDScript `RefCounted` rules.
This deliberately tests an **engine-native baseline**, replacing the older
proposed raw-C adapter route for this experiment only. The model runs without
scene nodes but still depends on Godot/GDScript types and runtime. Extracting it
to a native or different-engine core requires real adaptation and verification;
headless parity is not cross-engine portability proof. No generic engine
abstraction or storage framework was built.

The sandbox remains separate under [experiments/engine-environment](../../experiments/engine-environment/README.md).
The chapter worker consumes the same model for opening-specific power/parts/UI;
the platform worker owns separate stationary network/save consumers. Neither
this fixture nor a successful environment check chooses final recipes, unlimited
stock, resource renewability, construction access or progression credit.

The official release API refreshed the pinned asset:
`Godot_v4.7.2-stable_linux.x86_64.zip`, **77,860,424 bytes**, SHA-256
`cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`.
[Release metadata](https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.2-stable).
One transfer completed without retry. Exact length/hash and the sole regular ZIP
entry/path/expanded size were checked before extracting; the binary is
146,414,384 bytes. Installed runtime + retained ZIP total **224,274,808 bytes**.
They stay in an owned external trial directory, never source control.

Recorded stop limits: 100 MiB aggregate runtime downloads, 1.5 GiB peak new
archive/engine/project/cache/output/evidence, setup 30 minutes, trial 120 minutes,
at most three edit/run rounds. Peak categories: 96 MiB archive, 512 engine,
384 project/cache, 128 build/output, 32 source, 128 evidence, 256 contingency.
Start at 22 GiB free, retaining the 20 GiB floor plus planned use/headroom; the
heavy wrapper also requires 8 GiB available memory and eight-job settings.
Individual headless runs cap at 30 seconds, scene/import at 180 seconds. Missing
dependencies, renderer failure or resource/budget excess stops expansion; no
global install, templates, engine source build or unrelated cleanup is included.
At setup approximately 149 GiB disk and 115 GiB memory were available; these
are host observations, not game targets or reservations.

## Actual observations and falsifiers

First run at 04:09:24–04:09:29 UTC: **20 headless assertions passed**. Real scene
buttons issued the same placement/connection/advance/retrieve actions, and its
first-output, full-output/held-work and final-stock projections matched headless.
Eight fixture feed units yielded four retrieved products through the declared
2:1 transformation. Missing input, occupied placement, depleted construction
parts, wrong context, duplicate/changed-payload requests, retained blocked work
and upstream extraction backpressure have explicit observations. A 1:1 fixture
is additional coverage in the final tests, not canonical opening content.

The actual 1280×800 scene rendered using OpenGL 4.2 / Mesa Compatibility through
WSLg's D3D12 NVIDIA GeForce RTX 3090 path. Its PNG was visually inspected. One
unsupported V-Sync-setting warning remains; there were no script errors. This
is a real engine/driver result, not certification of every renderer or native
Windows deployment. Initial version/headless/scene process durations were about
0.17/0.21/4.23 seconds; these include startup and instrumentation, are a single
engineering observation under heavy admission, and are not a performance
benchmark or comparison with UE5/Unity/Bevy.

The second edit/run round changed the scene heading and added a 1:1 constructor
fixture. Exact staged tree `fc18bde6d418` passed **65 tooling tests, editor import,
22 headless assertions and the real scene checks** at 04:13:48 UTC. Its six
runtime-source hashes match the final sources; subsequent edits only finalized
this evidence text. Import/headless/scene took about 4.03/0.22/3.83 seconds in
this run, not a controlled speed comparison. Receipts retain per-file source
hashes, assertions, logs, stage durations and PNG in external directories. See the
sandbox README for explicit canonical and standalone test/run commands. A
requested missing runtime fails; source-only tooling passes make no game claim.

Still unrun: real human editing/play/comfort, competing network clients and
correction/rejoin, save/restore continuation, physical wheel/shaft power,
stopped-edit recovery, character collision, moving harvest/transfers, native
core integration, packaging/distribution, factory scale and comparative engine
iteration. UI/world picking here is a grid-plane intersection, not a tested
player movement/collision join; finite source stock is a fixture, not terrain
harvest eligibility. Source/client assertions are not proof of
adversarial network safety. User feedback and independent review of this exact
sandbox/checker change must precede broader use or production recommendations.
