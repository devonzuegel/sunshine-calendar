#!/bin/zsh
set -eu
cd "${0:A:h}"
signing_identity="${CALENDAR_STUDIO_SIGNING_IDENTITY:-Calendar Studio Local Development}"
if [[ "${1:-}" == '--temporary-signing' ]]; then
    signing_identity='-'
    echo 'Using temporary signing; Calendar permission may be requested again after this update.'
fi
if [[ "$signing_identity" != '-' ]] && ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$signing_identity\""; then
    echo "No persistent signing identity found: $signing_identity" >&2
    echo 'Run ./setup-signing.sh once before building. Temporary signing causes repeated Calendar permission prompts.' >&2
    exit 1
fi
mkdir -p build
app_destination="$PWD/build/Sunshine Calendar.app"
build_stage=$(mktemp -d "$PWD/build/.calendar-build.XXXXXX")
trap 'rm -rf "$build_stage"' EXIT
app_stage="$build_stage/Sunshine Calendar.app"
mkdir -p "$app_stage/Contents/MacOS" "$app_stage/Contents/Resources"
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PWD/build/ModuleCache" Sources/*.swift -o "$app_stage/Contents/MacOS/CalendarStudio" -framework SwiftUI -framework AppKit -framework EventKit -framework CoreLocation
cp Info.plist "$app_stage/Contents/Info.plist"
cp Resources/Relaunch.sh "$app_stage/Contents/Resources/Relaunch.sh"
cp Resources/CalendarStudio.icns "$app_stage/Contents/Resources/CalendarStudio.icns"
codesign --force --sign "$signing_identity" --identifier com.devon.calendarstudio "$app_stage"
codesign --verify --strict "$app_stage"
# Build and sign a fresh bundle rather than changing a running executable in place.
if [[ -d "$app_destination" ]]; then mv "$app_destination" "$build_stage/previous.app"; fi
if ! mv "$app_stage" "$app_destination"; then
    if [[ -d "$build_stage/previous.app" ]]; then mv "$build_stage/previous.app" "$app_destination"; fi
    exit 1
fi
# Retire the old app name only after the renamed bundle is safely installed.
if [[ -d "$PWD/build/Calendar Studio.app" ]]; then
    mv "$PWD/build/Calendar Studio.app" "$build_stage/old-name.app"
fi
echo 'Built Sunshine Calendar.app in the build folder.'
