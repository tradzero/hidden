#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -swift-version 5 -module-cache-path build/module-cache \
  hidden/Features/StatusBar/CollapseLengthCalibrator.swift \
  tests/CollapseLengthCalibratorTests.swift -o build/tests/calibration-tests
build/tests/calibration-tests
