# Trio

## Introduction

Trio - an automated insulin delivery system for iOS based on the OpenAPS algorithm with [adaptations for Trio](https://github.com/nightscout/trio-oref).

The project started as Ivan Valkou's FreeAPS X implementation of the OpenAPS algorithm for iPhone, and was later forked and rebranded as iAPS. The project has since seen substantial contributions from many developers, leading to a range of new features and enhancements.

Following the release of iAPS version 3.0.0, due to differing views on development, open source, and peer review, there was a significant shift in the project's direction. This led to the separation from the [Artificial-Pancreas/iAPS](https://github.com/Artificial-Pancreas/iAPS) repository, and the birth of [Trio](https://github.com/nightscout/Trio.git) as a distinct entity. This transition marks a new phase for the project, symbolizing both its evolution and the dynamic nature of collaborative development.

Trio continues to leverage a variety of frameworks from the DIY looping community and remains at the forefront of DIY diabetes management solutions, constantly evolving with valuable contributions from its community.

## To download this repo:

There is also a script available, but if you prefer the manual process:

In Terminal:

Configure a folder where you want your download to reside:

```
cd <your desired folder name>
git clone --branch=<<branch>> --recurse-submodules https://github.com/nightscout/Trio.git
cd Trio
```

modify Config.xconfig to replace ##TEAM_ID## with your Apple Developer ID.

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

[Discord Trio - Server ](https://discord.gg/KepAG6RdYZ)

TODO: Add link: Trio documentation (under development, not existing yet)

TODO: Add link: Trio Website (under development, not existing yet)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

TODO: Add link and status graphic: Crowdin Project for translation of Trio (not existing yet)

# Support

[Trio Facebook Group](https://m.facebook.com/groups/1351938092206709/)

[Loop and Learn Facebook Group](https://m.facebook.com/groups/LOOPandLEARN/)

[Looped Facebook Group](https://m.facebook.com/groups/TheLoopedGroup/)

# Contribute

Code contributions as PRs are welcome!

Translators can click the Crowdin link above.

For questions or contributions, please join our [Discord server](https://discord.gg/KepAG6RdYZ).
