#!/bin/zsh

# copied from Loop where this definition was used by more than one script
# initially we probably will not need that capability, but does no harm to keep it
# define parameters and arrays used by more than one script
#   These are always capitalized
#      TRIO_PROJECTS

# include this file in each script using
#   source scripts/define_commont_trio.sh

# define the TRIO_PROJECTS used by Trio where for Trio the .gitmodules points
#   to the downstream fork of loopandlearn (SyaiKit: nightscout)
#
# Kits track trio-next-dev (upstream next-dev plus Trio carries); OmnipodKit and
#   dexcom-share-client-swift track next-dev and RoundWhiteDiscKit main
#
# There are scripts available in LoopWorkspace that update translations and make
#   sure the loopandlearn branches are up to date
TRIO_PROJECTS=( \
    loopandlearn:AccuChekKit:trio-next-dev \
    loopandlearn:CGMBLEKit:trio-next-dev \
    loopandlearn:DanaKit:trio-next-dev \
    loopandlearn:dexcom-share-client-swift:next-dev \
    loopandlearn:EversenseKit:trio-next-dev \
    loopandlearn:G7SensorKit:trio-next-dev \
    loopandlearn:LibreLoop:trio-next-dev \
    loopandlearn:LibreTransmitter:trio-next-dev \
    loopandlearn:LoopKit:trio-next-dev \
    loopandlearn:MedtrumKit:trio-next-dev \
    loopandlearn:MinimedKit:trio-next-dev \
    loopandlearn:OmnipodKit:next-dev \
    loopandlearn:RileyLinkKit:trio-next-dev \
    loopandlearn:RoundWhiteDiscKit:main \
    nightscout:SyaiKit:trio-next-dev \
    loopandlearn:TidepoolService:trio-next-dev \
)
