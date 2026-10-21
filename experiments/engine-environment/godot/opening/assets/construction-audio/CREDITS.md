# Construction impact samples

The source is [Kenney's Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds),
released on 19 December 2019 under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The original license is retained alongside these files. The provider identifies
the set as impact/foley audio; its physical recording technique is unverified.

Factory layers selected metal, wood and soft impacts into designed belt,
assembly, coupling and release feedback. These cues approximate mechanical
attachment and removal; they do not identify a particular real fastener or alloy.
The belt combines a soft body impact with a quieter metal latch 35 milliseconds
later. The full layer recipe, including filenames, delays and gains, is defined by
`IMPACT_RECIPE` in [construction_audio_check.gd](../../construction_audio_check.gd).
[source.json](source.json) records original file identities and prepared outputs.

The existing construction fixture's `--prepare-impact-cues SOURCE OUTPUT` mode
pins all seven original Vorbis files, decodes them through the pinned engine's
offline playback API, averages stereo channels, applies the fixed layers and
short attack/tail fades, and normalizes each cue to a 0.62 peak. The output is
44.1 kHz, mono, signed 16-bit PCM WAV. Preparation checks exact PCM roundtrips and
refuses changed source or existing outputs. It is an adaptation, rather than
sample-exact preservation of the original stereo Vorbis signal.

Runtime loads and shares these four clips without regeneration. Existing action
identity, rejection, pending and duplicate guards still own acknowledgement.
Historical captures lacking the entire set retain their earlier synthesized
clips. Partial or invalid sets are explicit errors. The existing -13 dB voice
gain and three-voice limit remain; complete game mix and human listening remain
unassessed. Raw captured-project loading is tested; Godot export packaging is
not established by those checks.
