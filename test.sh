#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PWD/build/ModuleCache" Sources/Daylight.swift Sources/CalendarModel.swift Sources/EventBankStore.swift Sources/WeekCanvas.swift Tests/CalendarTests.swift Tests/EventBankTests.swift -o build/CalendarTests -framework SwiftUI -framework AppKit -framework EventKit -framework CoreLocation
build/CalendarTests
