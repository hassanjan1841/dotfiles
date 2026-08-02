#!/bin/sh
# -framework Carbon links IsSecureEventInputEnabled, which is declared by hand in
# human.swift rather than imported: the Carbon module's namespace collides with names
# used here (it defines its own typeText).
#
# The self test runs on every build, because "I meant to run it" is how a broken
# correction path or a dead command ships. Pass --no-test to skip it.
set -e
cd "$(dirname "$0")"
swiftc -O human.swift -o human -framework Carbon 2>&1 | grep -v 'SwiftUICore' || true
[ -x ./human ] || { echo "build failed"; exit 1; }
case "$*" in
  *--no-test*) exit 0 ;;
esac
./human selftest
