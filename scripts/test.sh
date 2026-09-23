#!/bin/bash
# Runs the unit tests.
#
# On machines with only the Command Line Tools installed, SwiftPM sometimes fails to locate the
# swift-testing macro plugin ("external macro implementation type 'TestingMacros...' could not be
# found"). Pointing at the plugin explicitly works around it; with full Xcode, plain `swift test`
# is enough.
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

PLUGIN="$(xcrun --find swift | xargs dirname)/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
    exec swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
fi
exec swift test "$@"
