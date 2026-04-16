#!/bin/zsh

# copied from Loop where this definition was used by more than one script
# initially we probably will not need that capability, but does no harm to keep it
# define parameters and arrays used by more than one script
#   These are always capitalized
#      TRIO_PROJECTS

# include this file in each script using
#   source scripts/define_commont_trio.sh

# define the TRIO_PROJECTS used by Trio where for Trio the .gitmodules points
#   to the downstream fork of loopandlearn in all cases
#
# The only submodule that needs a special trio branch (at this time) is LoopKit
#    put that repository first in the list
#
# The scrips in LoopWorkspace are used to update translations and make
#   sure the loopandlearn branches are up to date
# Even though EversenseKit is only found in a feature branch
#   it does no harm to update extra repositories using this script
TRIO_PROJECTS=( \
    loopandlearn:LoopKit:trio \
    loopandlearn:CGMBLEKit:dev \
    loopandlearn:dexcom-share-client-swift:dev \
    loopandlearn:G7SensorKit:main \
    loopandlearn:LibreTransmitter:main \
    loopandlearn:MinimedKit:main \
    loopandlearn:OmniBLE:dev \
    loopandlearn:OmniKit:main \
    loopandlearn:RileyLinkKit:dev \
    loopandlearn:TidepoolService:dev \
    loopandlearn:DanaKit:dev \
    loopandlearn:EversenseKit:dev \
    loopandlearn:MedtrumKit:dev \
)
