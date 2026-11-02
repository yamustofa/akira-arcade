#!/bin/sh
# Akira Arcade: point the emulator cores' signing at your own Apple team.
#
# The cores (Cores/*, External/*) are upstream repos we don't fork, and several of
# them pin the upstream author's team. Xcode then fails with "No Account for Team".
# This rewrites that team, locally only, to the DEVELOPMENT_TEAM in
# Akira.local.xcconfig. The parent repo ignores these local edits (`ignore = dirty`
# in .gitmodules). Run it again after `git submodule update`.
set -eu
cd "$(dirname "$0")/.."

team=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p' Akira.local.xcconfig 2>/dev/null | tail -n 1)
if [ -z "$team" ]; then
  echo "Set DEVELOPMENT_TEAM in Akira.local.xcconfig first (see Akira.local.xcconfig.example)." >&2
  exit 1
fi

count=0
for f in $(find Cores External -name project.pbxproj -path '*.xcodeproj/*' 2>/dev/null); do
  if grep -qE '(DEVELOPMENT_TEAM|DevelopmentTeam) = [A-Z0-9]{10};' "$f"; then
    perl -pi -e "s/(DEVELOPMENT_TEAM|DevelopmentTeam) = [A-Z0-9]{10};/\$1 = $team;/g" "$f"
    count=$((count + 1))
  fi
done
echo "Signed $count core project(s) with team $team."
