#!/bin/bash
xcodebuild test -workspace Trio.xcworkspace \
	   -scheme Trio \
	   -destination 'platform=iOS Simulator,name=iPhone 16' \
    | xcpretty
