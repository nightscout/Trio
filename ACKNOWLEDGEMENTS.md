# Acknowledgements

Third-party material bundled with Trio, and the terms it is used under.

## Alarm and alert sounds

The themed alarm sets (Acoustic, Electronic) and the one-off tones were
created for Trio by a sound designer and are distributed as part of Trio.

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
