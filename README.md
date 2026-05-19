# Trio &nbsp;&nbsp;&nbsp;[![Discord](https://img.shields.io/discord/1020905149037813862?label=Discord&logo=discord&logoColor=white&color=5865F2)](https://discord.triodocs.org)

## Introduction

Trio is an open source automated insulin delivery (OS-AID) system for iOS based on the OpenAPS algorithm, with [adaptations for Trio](https://github.com/nightscout/trio-oref).

Trio builds on years of work from the #WeAreNotWaiting diabetes community. Trio emerged from that broader body of work and is now developed as its own independent open-source project with the backing and support of the Nightscout Foundation. Since then, it has seen substantial contributions from many developers, resulting in a wide range of new features and enhancements.

Its roots trace back to Ivan Valkou’s [FreeAPS X](https://github.com/ivalkou/freeaps), an iPhone implementation of the [OpenAPS algorithm](https://github.com/openaps/oref0), as well as subsequent community development (later known as iAPS), the [LoopKit](https://github.com/LoopKit) set of tools for building AID systems on iOS, and a broad set of open source pump and CGM drivers developed by the wider OS-AID contributor community.

Trio is developed in active collaboration with the wider open source AID ecosystem across both iOS and Android. The project is committed not only to building Trio itself, but also to enabling collaboration across communities, platforms, and contributor groups in support of stronger and more accessible OS-AID solutions.

In parallel, Trio contributors are actively involved in collaboration with researchers and healthcare professionals to help push the boundaries of what open source AID can achieve.

Trio continues to evolve through contributions from developers, testers, documentation writers, translators, and community members across the open source diabetes ecosystem.

### Mission

Trio aims to make open source automated insulin delivery safer and more accessible for people with diabetes who are willing to learn, including those supported by experienced users and healthcare professionals, while continuing to support the experienced users and contributors who help build and improve it.

### Target Audience

Today, Trio primarily serves:
- people with diabetes (PwD) who are experienced users and want a highly configurable system they can fine-tune
- PwD who already have good control and want a system that requires less day-to-day intervention
- PwD coming from commercial systems who discover open source AID through community support, advocacy, and social channels
- PwD who are learning Trio with support from experienced users or healthcare professionals

### Direction

Over time, Trio aims to work safely for **any** person with diabetes who is willing to learn, while continuing to bring along the experienced users, "super users", and contributors who help shape and improve the project and the OS-AID ecosystem as a whole.

---

## To download this repo:

You can either use the Build Script or you can run each command manually.

### Build Script:

If you copy, paste, and run the following script in Terminal, it will guide you through downloading and installing Trio. More information about the script can be found [here](https://triodocs.org/install/build/mac/build/).

```
/bin/bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/loopandlearn/lnl-scripts/main/TrioBuildSelectScript.sh)"
```

### Command Line Interface (CLI):

In Terminal, `cd` to the folder where you want your download to reside, change `<branch>` in the command below to the branch you want to download (ie. `dev`), and press `return`.

```
git clone --branch=<branch> --recurse-submodules https://github.com/nightscout/Trio.git && cd Trio
```

Create a ConfigOverride.xcconfig file that contains your Apple Developer ID (something like `123A4BCDE5`). This will automate signing of the build targets in Xcode:

Copy the command below, and replace `xxxxxxxxxx` by your Apple Developer ID before running the command in Terminal.

```
echo 'DEVELOPER_TEAM = xxxxxxxxxx' > ConfigOverride.xcconfig
```

Then launch Xcode and build the Trio app:

```
xed .
```

---

## To build directly in GitHub, without using Xcode:

**Instructions**:

- For **`main`** branch:  
   https://github.com/nightscout/Trio/blob/main/fastlane/testflight.md
- For **`dev`** branch:
  https://github.com/nightscout/Trio/blob/dev/fastlane/testflight.md

Instructions in **greater detail**:

- https://triodocs.org/install/build/browser/browser-build-overview/

---

## Please understand that Trio is:

- an open-source system developed by enthusiasts and for use at your own risk
- not CE or FDA approved for therapy.

## Documentation

- [Trio documentation](https://triodocs.org/)
- [OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)
- [Crowdin](https://crowdin.triodocs.org/) is the collaborative platform we are using to manage the **translation** and localization of the Trio App.
- [Loop lokalise](https://loopkit.github.io/loopdocs/faqs/app-translation/#code-translation) is the collaborative platform used to manage the translations and localizations from shared pump managers, CGM managers, and services.

## Support

- [Trio Facebook Group](https://facebook.triodocs.org/)
- [Loop and Learn Facebook Group](https://m.facebook.com/groups/LOOPandLEARN/)
- [Looped Facebook Group](https://m.facebook.com/groups/TheLoopedGroup/)

For questions or contributions, please join our [Discord server](https://discord.triodocs.org).
