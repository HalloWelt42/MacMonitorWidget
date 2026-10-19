#!/usr/bin/env bash
# Baut MacMonitorWidget (Menüleisten-Programm + Schreibtisch-Widget) über XcodeGen und
# xcodebuild, signiert beide Teile mit den passenden Entitlements und installiert
# nach /Applications. Aufruf: scripts/make_app.sh [Release|Debug]
#
# Hintergrund: Ein WidgetKit-Widget braucht eine eingebettete App-Erweiterung; das
# geht nicht mit reinem SwiftPM. Die Erweiterung MUSS in der Sandbox laufen (sonst
# weist macOS sie ab) - deshalb teilt das (unsandboxed) Programm die Messwerte über
# eine App-Gruppe mit dem (sandboxed) Widget.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
config="${1:-Release}"
derived=".build-xcode"
app="${derived}/Build/Products/${config}/MacMonitorWidget.app"

# Stabile Signaturidentität bevorzugen, sonst ad-hoc.
if [ -n "${MACMONITORWIDGET_SIGN_ID:-}" ]; then
    SIGN_ID="$MACMONITORWIDGET_SIGN_ID"
elif security find-identity -p codesigning -v 2>/dev/null | grep -q "Lichtspiel Dev"; then
    SIGN_ID="Lichtspiel Dev"
else
    SIGN_ID="-"
fi

version="$(python3 -c 'import json; print(json.load(open("version.json"))["version"])')"
echo "version: ${version}"

xcodegen generate
xcodebuild -project MacMonitorWidget.xcodeproj -scheme MacMonitorWidget -configuration "$config" \
    -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$version" build

echo "signing as: ${SIGN_ID}"
# Erst die eingebettete Erweiterung (mit Sandbox + App-Gruppe), dann die App.
codesign --force --sign "$SIGN_ID" --entitlements Sources/Widget/Widget.entitlements \
    "${app}/Contents/PlugIns/MacMonitorWidgetExtension.appex"
codesign --force --sign "$SIGN_ID" --entitlements Sources/App/App.entitlements "$app"
codesign --verify --deep --strict "$app" && echo "Signatur gültig"

# Nach /Applications installieren und laufende Instanz ersetzen.
dest="/Applications/MacMonitorWidget.app"
pkill -f "${dest}/Contents/MacOS/MacMonitorWidget" 2>/dev/null || true
rm -rf "$dest"
ditto "$app" "$dest"
xattr -cr "$dest" >/dev/null 2>&1 || true

LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$dest"

echo "installed ${dest}"
open "$dest"
