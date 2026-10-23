# Meridian arrival audio

The 2.8-second descent bed and the hub-ready chime are original deterministic PCM
waveforms authored in the `ArrivalRevealAudio` class in `opening/opening.gd`.
The bed combines a falling engine tone, a low motor pulse and seeded filtered
noise. The chime uses three
short decaying tones. They are generated once per process, at 22.05 kHz mono,
and play only during the fresh visual reveal.

Touchdown reuses the prepared `assembly.wav` cue at 0.72 playback speed. The
two deck latches reuse `coupling.wav` at 0.93 and 1.06 playback speed. Those
prepared samples derive from Kenney's CC0 Impact Sounds 1.0; see
[`construction-audio/CREDITS.md`](../construction-audio/CREDITS.md) for source,
license and preparation details. These cues indicate a designed pod mechanism,
not a claim about the sound of a real landing vehicle.

The reveal clock emits one descent, touchdown, port latch, starboard latch and
hub-ready cue. A skipped reveal stops every voice immediately. A naturally
completed reveal fades its descent bed and lets the short final chime end.
Restored and shared work sites never start a new reveal or its score. Native
deployment, construction and material custody do not depend on audio.
