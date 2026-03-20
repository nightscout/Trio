#!/bin/zsh

source scripts/define_common_trio.sh

for project in ${TRIO_PROJECTS}; do
  echo "Updating to $project"
  IFS=":" read user dir branch <<< "$project"
  echo "Updating to $branch on $user/$project"
  cd $dir
  git checkout $branch
  git pull
  cd -
done
