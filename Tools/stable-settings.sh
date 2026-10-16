#!/bin/sh
# 安定版（TestFlight で配る版）のビルド設定を出力する。xcodebuild の引数にそのまま渡す。
#   xcodebuild ... $(./Tools/stable-settings.sh)
#
# 審査で指摘されそうな機能を外す:
# - 非公開 API（MediaRemote）
# - ワークアウトモード（HealthKit の権限）
# - Watch のバックグラウンドモード（延長実行・ワークアウト）とヘルスケアの説明文
# - iPhone の無音再生による常駐（コード側で STABLE_EDITION のとき無効）
set -e
cd "$(dirname "$0")/.."
PLIST=build/stable/Watch-Info.plist
mkdir -p build/stable
cp Watch/Info.plist "$PLIST"
for key in WKBackgroundModes NSHealthShareUsageDescription NSHealthUpdateUsageDescription; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
done
echo "SC_STABLE=STABLE_EDITION SC_PRIVATE_API= SC_WATCH_ENTITLEMENTS= SC_WATCH_INFOPLIST=$PLIST SC_DISPLAY_NAME=SpatialCue"
