#!/bin/sh
# -framework Carbon links IsSecureEventInputEnabled, which is declared by hand in
# human.swift rather than imported: the Carbon module's namespace collides with names
# used here (it defines its own typeText).
exec swiftc -O human.swift -o human -framework Carbon "$@"
