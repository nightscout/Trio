#!/bin/bash
set -euxo pipefail

TRIO=$(git rev-parse --show-superproject-working-tree)
if [[ "$TRIO" == "" ]]; then TRIO=$(git rev-parse --show-toplevel); fi

echo "TRIO=$TRIO"

cd $TRIO/TandemKit
git reset --hard


cd $TRIO
git submodule update --remote TandemKit


cd $TRIO/TandemKit
git show
