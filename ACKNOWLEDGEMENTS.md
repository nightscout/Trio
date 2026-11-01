# Acknowledgements

Third-party material bundled with Trio, and the terms it is used under.

## Alarm and alert sounds

The themed alarm sets (`acoustic_*.caf`, `electronic_*.caf`) and the one-off
tones (`glass_bell.caf`, `harp.caf`, `meow.caf`, `saw_wave.caf`,
`hard_saw_wave.caf`, `sine_wave.caf`, `open_can.caf`, `open_wrapper.caf`) were
created for Trio by **an anonymous diabetes dad and Trio user**.

- Licence: **Creative Commons Zero 1.0 Universal (CC0 1.0)** —
  <https://creativecommons.org/publicdomain/zero/1.0/>
- The author states that they are the author of these files, that they hold
  the right to license them, and that they contain no third-party material
  they cannot license.
- CC0 requires no attribution. The credit above is given at the author's
  request; they have asked to remain anonymous.
- Changes made by Trio: the one-off tones were looped by whole repeats to at
  least five seconds, so that every alarm sounds for a comparable time. The
  themed sets were left exactly as delivered — their length and level are
  part of the design, and carry the urgency along with the timbre.

The spoken alert sounds are generated from third-party voice models and are
*not* covered by that dedication — see below.

## Voice alerts

Trio's spoken alert sounds were generated with
[Piper](https://github.com/rhasspy/piper) using voices from the
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) collection.

### Amy (`voice_*_amy.caf`)

- Model: `en/en_US/amy/medium`
- Source dataset: [MycroftAI/mimic3-voices](https://github.com/MycroftAI/mimic3-voices)
- Licence: **Creative Commons Attribution-ShareAlike 4.0 International
  (CC BY-SA 4.0)** — <https://creativecommons.org/licenses/by-sa/4.0/>
- Changes made by Trio: the generated phrases were looped to a minimum
  duration of five seconds so that a spoken alert lasts long enough to be
  heard as an alarm. No other processing was applied.
- These audio files are made available under CC BY-SA 4.0. This does not
  change the licence of Trio itself.

### Bryce (`voice_*_bryce.caf`)

- Model: `en/en_US/bryce/medium`
- Source: <https://brycebeattie.com> (training data released into the public
  domain by the speaker)
- Licence: **Public domain.** Credited here as a courtesy; no attribution is
  required.
- Changes made by Trio: looped to a minimum duration of five seconds, as above.
