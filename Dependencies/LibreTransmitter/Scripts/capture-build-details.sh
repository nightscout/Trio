#!/bin/sh -e

#  capture-build-details.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

echo "Libretransmitter Gathering build details in ${SRCROOT}"
cd "${SRCROOT}"

plist="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

prefix="com-loopkit-libre"

if [ -e .git ]; then
  rev=$(git rev-parse HEAD)
  dirty=$([[ -z $(git status -s) ]] || echo '-dirty')
  plutil -replace $prefix-git-revision -string "${rev}${dirty}" "${plist}"
  
  branch=$(git branch | grep \* | cut -d ' ' -f2-)
  plutil -replace $prefix-git-branch -string "${branch}" "${plist}"

  remoteurl=$(git config --get remote.origin.url)
  plutil -replace $prefix-git-remote -string "${remoteurl}" "${plist}"
fi;
plutil -replace $prefix-srcroot -string "${SRCROOT}" "${plist}"
plutil -replace $prefix-build-date -string "$(date)" "${plist}"
plutil -replace $prefix-xcode-version -string "${XCODE_PRODUCT_BUILD_VERSION}" "${plist}"

echo "Listing all custom plist properties:"
plutil -p "${plist}"|grep $prefix



