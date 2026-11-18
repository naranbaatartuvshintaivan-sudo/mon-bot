#!/bin/bash
# Command Line Tools (Xcode-гүй) орчинд swift-testing-ийн framework замыг заана.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$DEV/Frameworks/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
    -Xlinker -F -Xlinker "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
else
  exec swift test "$@"   # Xcode суусан бол шууд ажиллана
fi
