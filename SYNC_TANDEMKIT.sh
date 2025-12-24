#!/bin/bash
set -euxo pipefail

TRIO=$(git rev-parse --show-superproject-working-tree)
if [[ "$TRIO" == "" ]]; then TRIO=$(git rev-parse --show-toplevel); fi

echo "TRIO=$TRIO"


cd $TRIO/TandemKit
rsync --exclude '.build' --exclude '.git' -av . ../../TandemKit/
