#!/bin/bash
# Source files of the root controller, shared by the build and the probe test.
cd "$(dirname "$0")/.."
printf '%s\n' \
    Sources/TetherlineCore/Command.swift \
    Sources/TetherlineCore/ControlChannel.swift \
    Sources/TetherlineCore/Deployment.swift \
    Sources/TetherlineCore/Errors.swift \
    Sources/TetherlineCore/Localization.swift \
    Sources/TetherlineCore/ServiceState.swift \
    Helper/ControlMain.swift
