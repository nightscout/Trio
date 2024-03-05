# iAPS

## Introduction

iAPS - an artificial pancreas system for iOS based on [Open-iAPS-oref Reference](https://github.com/nightscout/open-iaps-oref) algorithms (Master 0.7.1) and Ivan Valkous stale Swift repo, freeaps.git.

Thousands of commits later, with many new and unique features added, the iOS app has been renamed to iAPS under a new organisation, Artificial Pancreas.

iAPS uses lot of frameworks published by the Loop community.

## To download this repo:

In Terminal:  
git clone --branch=main https://github.com/artificial-pancreas/iaps.git  
cd iaps  
xed .

Or using the GitHub interface:
Download and open in Xcode directly using the Code button: "Open with Xcode".

## To build directly in GitHub, without using Xcode:

Instructions:  
https://github.com/nightscout/Open-iAPS/blob/main/fastlane/testflight.md   
Instructions in greater detail, but not iAPS-specific:  
https://loopkit.github.io/loopdocs/gh-actions/gh-overview/

## Please understand that iAPS is:
- highly experimental and evolving rapidly.
- not CE or FDA approved for therapy.

# Pumps

- Omnipod EROS
- Omnipod DASH
- Medtronic 515 or 715 (any firmware)
- Medtronic 522 or 722 (any firmware)
- Medtronic 523 or 723 (firmware 2.4 or lower)
- Medtronic Worldwide Veo 554 or 754 (firmware 2.6A or lower)
- Medtronic Canadian/Australian Veo 554 or 754 (firmware 2.7A or lower)

# CGM Sensors

- Dexcom G5
- Dexcom G6
- Dexcom ONE
- Dexcom G7
- Libre 1
- Libre 2 (European)
- Medtronic Enlite
- Nightscout as CGM

# iPhone and iPod

iAPS app runs on iPhone or iPod. An iPhone 8 or newer is required. Minimum iOS 16.

# Documentation

[Discord Open-iAPS - Server ](https://discord.gg/s5b6E4vHs3)

[iAPS documentation (under development, not existing yet)](https://open-iaps.readthedocs.io/en/latest/)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

[Crowdin Project for translation of Open-iAPS (not existing yet)](https://crowdin.com/project/open-iaps)  
[![Crowdin (not existing yet)](https://badges.crowdin.net/iaps/localized.svg)](https://crowdin.com/project/open-iaps)

[Middleware code for iAPS (not existing yet)](https://github.com/nightscout/middleware)

[ADD DASH PUMP and SETTINGS](https://loopkit.github.io/loopdocs/loop-3/omnipod/)


# Contribute

Code contributions as PRs are welcome!

Translators can click the Crowdin link above.

For questions or contributions, please join our [Discord server](https://discord.gg/s5b6E4vHs3).
