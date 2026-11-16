#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
compile_options=()
if [[ "${1:-}" == '--optimized' ]]; then compile_options=(-O); fi
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" swiftc "${compile_options[@]}" -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PWD/build/ModuleCache" Sources/CalendarPicker.swift Sources/LocationAutocomplete.swift Sources/PerformanceSupport.swift Sources/EmojiAutocomplete.swift Sources/WeatherLocationPicker.swift Sources/WeatherWeekStrip.swift Sources/RichNotesEditor.swift Sources/AppTooltip.swift Sources/CalendarViews.swift Sources/WeatherOverlay.swift Sources/TimeZoneChooser.swift Sources/Daylight.swift Sources/CalendarModel.swift Sources/AppTextSize.swift Sources/EventHistory.swift Sources/EventBankStore.swift Sources/WeekCanvas.swift Tests/PerformanceTests.swift Tests/CalendarTests.swift Tests/EventBankTests.swift -o build/CalendarTests -framework SwiftUI -framework AppKit -framework EventKit -framework CoreLocation -framework MapKit
build/CalendarTests
