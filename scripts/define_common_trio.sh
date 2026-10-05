#!/bin/zsh

# copied from Loop where this definition was used by more than one script
# initially we probably will not need that capability, but does no harm to keep it
# define parameters and arrays used by more than one script
#   These are always capitalized
#      TRIO_PROJECTS

# include this file in each script using
#   source scripts/define_commont_trio.sh

# define the TRIO_PROJECTS used by Trio where for Trio the .gitmodules points
#   to the downstream fork of loopandlearn, except LibreLoop (LoopKit) and
#   RoundWhiteDiscKit (airedev326)
#
# LoopKit needs its trio branch, and LibreLoop its legacy-loopkit-compat branch,
#   which builds against that LoopKit
#
# There are scripts available in LoopWorkspace that update translations and make
#   sure the loopandlearn branches are up to date
TRIO_PROJECTS=( \
    loopandlearn:AccuChekKit:master \
    loopandlearn:CGMBLEKit:dev \
    loopandlearn:DanaKit:dev \
    loopandlearn:dexcom-share-client-swift:dev \
    loopandlearn:EversenseKit:dev \
    loopandlearn:G7SensorKit:main \
    LoopKit:LibreLoop:legacy-loopkit-compat \
    loopandlearn:LibreTransmitter:main \
    loopandlearn:LoopKit:trio \
    loopandlearn:MedtrumKit:dev \
    loopandlearn:MinimedKit:main \
    loopandlearn:OmnipodKit:main \
    loopandlearn:RileyLinkKit:dev \
    airedev326:RoundWhiteDiscKit:main \
    loopandlearn:TidepoolService:dev \
    loopandlearn:LoopAlgorithm:main \
)
