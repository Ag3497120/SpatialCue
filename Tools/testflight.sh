#!/bin/sh
# TestFlight 用にアーカイブして .ipa を書き出す。
#   ./Tools/testflight.sh            # build/testflight に .ipa を書き出すだけ
#   ./Tools/testflight.sh --upload   # App Store Connect にアップロードする
#
# - バンドル ID は Config/Local.xcconfig の SC_RELEASE_BUNDLE_ID（無ければ SC_BUNDLE_ID）
# - 非公開 API（MediaRemote）は外してビルドする（審査で却下されるため）
# - ビルド番号は日時（例: 202610171230）で毎回自動的に増える
set -e
cd "$(dirname "$0")/.."

read_cfg() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^/[:space:]]*\).*/\1/p" Config/Local.xcconfig 2>/dev/null | tail -1
}

TEAM=$(read_cfg SC_TEAM_ID)
BUNDLE=$(read_cfg SC_RELEASE_BUNDLE_ID)
[ -n "$BUNDLE" ] || BUNDLE=$(read_cfg SC_BUNDLE_ID)
if [ -z "$TEAM" ] || [ -z "$BUNDLE" ]; then
    echo "Config/Local.xcconfig に SC_TEAM_ID と SC_RELEASE_BUNDLE_ID（または SC_BUNDLE_ID）を書いてください" >&2
    exit 1
fi

DESTINATION=export
[ "$1" = "--upload" ] && DESTINATION=upload
BUILD=$(date +%Y%m%d%H%M)
OUT=build/testflight
ARCHIVE="$OUT/SpatialCue.xcarchive"
mkdir -p "$OUT"

echo "▶ アーカイブ: $BUNDLE（ビルド $BUILD）"
xcodebuild archive \
    -project SpatialCue.xcodeproj -scheme SpatialCue -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    SC_BUNDLE_ID="$BUNDLE" SC_PRIVATE_API= CURRENT_PROJECT_VERSION="$BUILD" \
    | grep -E "error:|warning: |ARCHIVE (SUCCEEDED|FAILED)" || true
[ -d "$ARCHIVE" ] || { echo "アーカイブに失敗しました" >&2; exit 1; }

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

echo "▶ 書き出し（$DESTINATION）"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates \
    | grep -E "error:|EXPORT (SUCCEEDED|FAILED)|Upload|Progress" || true

if [ "$DESTINATION" = upload ]; then
    echo "完了: App Store Connect の TestFlight に、処理が終わるとビルド $BUILD が表示されます"
else
    ls -la "$OUT"/*.ipa
fi
