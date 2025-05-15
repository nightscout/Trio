# Trio

## Introduction

Trio - an automated insulin delivery system for iOS based on the OpenAPS algorithm with [adaptations for Trio](https://github.com/nightscout/trio-oref).

The project started as Ivan Valkou's [FreeAPS X](https://github.com/ivalkou/freeaps) implementation of the [OpenAPS algorithm](https://github.com/openaps/oref0) for iPhone, and was later forked and rebranded as iAPS. The project has since seen substantial contributions from many developers, leading to a range of new features and enhancements.

Following the release of iAPS version 3.0.0, due to differing views on development, open source, and peer review, there was a significant shift in the project's direction. This led to the separation from the [Artificial-Pancreas/iAPS](https://github.com/Artificial-Pancreas/iAPS) repository, and the birth of [Trio](https://github.com/nightscout/Trio.git) as a distinct entity. This transition marks a new phase for the project, symbolizing both its evolution and the dynamic nature of collaborative development.

Trio continues to leverage a variety of frameworks from the DIY looping community and remains at the forefront of DIY diabetes management solutions, constantly evolving with valuable contributions from its community.

## To download this repo:

You can either use the Build Script or you can run each command manually.

### Build Script:

If you copy, paste, and run the following script in Terminal, it will guide you through downloading and installing Trio. More information about the script can be found [here](https://docs.diy-trio.org/operate/build/#build-trio-with-script).

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

## To build directly in GitHub, without using Xcode:

Instructions:

For main branch:
* https://github.com/nightscout/Trio/blob/main/fastlane/testflight.md   

For dev branch:
* https://github.com/nightscout/Trio/blob/dev/fastlane/testflight.md   

Instructions in greater detail, but not Trio-specific:  
* https://loopkit.github.io/loopdocs/gh-actions/gh-overview/

## Please understand that Trio is:
- an open-source system developed by enthusiasts and for use at your own risk
- not CE or FDA approved for therapy.


# Documentation

[Discord Trio - Server ](http://discord.triodocs.org)

[Trio documentation](https://triodocs.org/)

TODO: Add link: Trio Website (under development, not existing yet)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

TODO: Add link and status graphic: Crowdin Project for translation of Trio (not existing yet)

# Support

[Trio Facebook Group](https://facebook.triodocs.org)

[Loop and Learn Facebook Group](https://m.facebook.com/groups/LOOPandLEARN/)

[Looped Facebook Group](https://m.facebook.com/groups/TheLoopedGroup/)

# Contribute

If you would like to give something back to the Trio community, there are several ways to contribute:

## Pay it forward
When you have successfully built Trio and managed to get it working well for your diabetes management, it's time to pay it forward. 
You can start by responding to questions in the Facebook or Discord support groups, helping others make the best out of Trio.

## Translate
Trio is translated into several languages to make sure it's easy to understand and use all over the world. 
Translation is done using [Crowdin](https://crowdin.com/project/trio), and does not require any programming skills.
If your preferred language is missing or you'd like to improve the translation, please sign up as a translator on [Crowdin](https://crowdin.com/project/trio).

## Develop
Do you speak JS or Swift? Do you have UI/UX skills? Do you know how to optimize API calls or improve data storage? Do you have experience with testing and release management?
Trio is a collaborative project. We always welcome fellow enthusiasts who can contribute with new code, UI/UX improvements, code reviews, testing and release management.
If you want to contribute to the development of Trio, please reach out on Discord or Facebook.

For questions or contributions, please join our [Discord server](https://discord.triodocs.org).
