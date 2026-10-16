#!/bin/sh
# Build SpatialCue with your own Apple ID and install it on your iPhone and Apple Watch.
# 自分の Apple ID でビルドして、iPhone と Apple Watch に入れる。
#
#   ./Tools/install.sh               # full edition
#   ./Tools/install.sh --stable      # stable edition (same as TestFlight)
#   ./Tools/install.sh --if-due      # only if the last success was 6+ days ago (for the scheduler)
#   ./Tools/install.sh --notify      # show a macOS notification with the result
#
# With a free Apple ID the signature expires after 7 days. Run this again (or use
# Tools/schedule-reinstall.sh) to renew it. Xcode renews the profile while building.
set -u
cd "$(dirname "$0")/.."

STABLE=0; IF_DUE=0; NOTIFY=0
for arg in "$@"; do
    case "$arg" in
        --stable) STABLE=1 ;;
        --if-due) IF_DUE=1 ;;
        --notify) NOTIFY=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

STATE=build/install
mkdir -p "$STATE"
LOG="$STATE/last.log"
: > "$LOG"

notify() {
    [ "$NOTIFY" = 1 ] && osascript -e "display notification \"$2\" with title \"SpatialCue\" subtitle \"$1\"" >/dev/null 2>&1
    return 0
}

fail() {
    echo "✗ $1"
    shift
    for hint in "$@"; do echo "  - $hint"; done
    echo "  Log: $LOG"
    notify "Install failed" "$1"
    exit 1
}

if [ "$IF_DUE" = 1 ] && [ -f "$STATE/last-success" ]; then
    last=$(cat "$STATE/last-success")
    now=$(date +%s)
    if [ $((now - last)) -lt $((6 * 24 * 3600)) ]; then
        echo "Last install was less than 6 days ago. Nothing to do."
        exit 0
    fi
fi

[ -f Config/Local.xcconfig ] || fail "Config/Local.xcconfig not found" \
    "cp Config/Local.example.xcconfig Config/Local.xcconfig, then set SC_TEAM_ID and SC_BUNDLE_ID"

# --- デバイスを探す ---------------------------------------------------------
echo "▶ Looking for your iPhone and Apple Watch"
JSON="$STATE/devices.json"
xcrun devicectl list devices --json-output "$JSON" >>"$LOG" 2>&1 || fail "Couldn't list devices" "Is Xcode installed and selected (xcode-select -p)?"
DEVICES=$(/usr/bin/python3 - "$JSON" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
best = {}
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {})
    kind = {"iPhone": "phone", "appleWatch": "watch"}.get(hw.get("deviceType"))
    if not kind or dev.get("connectionProperties", {}).get("pairingState") != "paired":
        continue
    # 接続中のものを優先
    score = 1 if dev.get("connectionProperties", {}).get("tunnelState") == "connected" else 0
    if kind not in best or score > best[kind][0]:
        best[kind] = (score, dev["identifier"], hw.get("udid", ""), dev.get("deviceProperties", {}).get("name", ""))
for kind, (_, ident, udid, name) in best.items():
    print(f"{kind}\t{ident}\t{udid}\t{name}")
EOF
)
PHONE_ID=$(echo "$DEVICES" | awk -F'\t' '$1=="phone"{print $2}')
PHONE_UDID=$(echo "$DEVICES" | awk -F'\t' '$1=="phone"{print $3}')
WATCH_ID=$(echo "$DEVICES" | awk -F'\t' '$1=="watch"{print $2}')
WATCH_UDID=$(echo "$DEVICES" | awk -F'\t' '$1=="watch"{print $3}')
[ -n "$PHONE_ID" ] || fail "No paired iPhone found" \
    "Connect the iPhone to this Mac (USB the first time) and tap Trust" \
    "Turn on Developer Mode: Settings → Privacy & Security → Developer Mode"
echo "  iPhone: $(echo "$DEVICES" | awk -F'\t' '$1=="phone"{print $4}')"
if [ -n "$WATCH_ID" ]; then
    echo "  Watch:  $(echo "$DEVICES" | awk -F'\t' '$1=="watch"{print $4}')"
else
    echo "  Watch:  not found (only the iPhone app will be installed)"
fi

# --- ビルド -----------------------------------------------------------------
SETTINGS=""
[ "$STABLE" = 1 ] && SETTINGS=$(./Tools/stable-settings.sh)
DERIVED=build/install/DerivedData

# シーム指定で端末向けにビルドすると、Xcode が端末を登録して署名（7 日間）を更新する
build_for() {
    scheme=$1; udid=$2; label=$3
    echo "▶ Building for $label (this registers the device and renews the signature)"
    # shellcheck disable=SC2086
    xcodebuild -project SpatialCue.xcodeproj -scheme "$scheme" -configuration Debug \
        -destination "id=$udid" -destination-timeout 30 -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration $SETTINGS build >>"$LOG" 2>&1
}

build_for SpatialCue "$PHONE_UDID" "iPhone" || fail "Build for iPhone failed" \
    "Open Xcode → Settings → Accounts and make sure your Apple ID is signed in" \
    "Check SC_TEAM_ID and SC_BUNDLE_ID in Config/Local.xcconfig (the bundle ID must be unique)" \
    "Free Apple ID and HealthKit errors: set SC_WATCH_ENTITLEMENTS = (empty) in Config/Local.xcconfig"
# iPhone 用のビルドで Watch アプリも一緒にできている。Watch を名指しするビルドは
# Watch を署名に登録するための追加の手順なので、Watch の準備ができていなくても先へ進む
if [ -n "$WATCH_UDID" ]; then
    if ! build_for SpatialCueWatch "$WATCH_UDID" "Apple Watch"; then
        echo "  ! Couldn't build for the Watch directly (it may need to be unlocked). Using the Watch app from the iPhone build."
        echo "    If installing on the Watch fails, unlock it and run this again so it gets registered."
    fi
fi

PRODUCTS="$DERIVED/Build/Products/Debug"
PHONE_APP="$PRODUCTS-iphoneos/SpatialCue.app"
WATCH_APP="$PRODUCTS-watchos/SpatialCueWatch.app"

# --- インストール（Watch は通信が不安定なので再試行する） -----------------
install_on() {
    device=$1; app=$2; label=$3
    i=1
    while [ $i -le 5 ]; do
        if xcrun devicectl device install app --device "$device" "$app" >>"$LOG" 2>&1; then
            echo "  ✓ $label"
            return 0
        fi
        echo "  … $label: retry $i/5"
        sleep 3
        i=$((i + 1))
    done
    return 1
}

echo "▶ Installing"
install_on "$PHONE_ID" "$PHONE_APP" "iPhone" || fail "Couldn't install on the iPhone" \
    "Unlock the iPhone" "Turn on Developer Mode on the iPhone"
if [ -n "$WATCH_ID" ]; then
    install_on "$WATCH_ID" "$WATCH_APP" "Apple Watch" || fail "Couldn't install on the Apple Watch" \
        "Unlock the Watch, take it off the charger, and keep it near the Mac on the same Wi-Fi" \
        "Turn on Developer Mode on the Watch: Settings → Privacy & Security → Developer Mode"
fi

date +%s > "$STATE/last-success"
echo "✓ Done. With a free Apple ID, run this again within 7 days."
notify "Installed" "SpatialCue was reinstalled on your iPhone and Watch."
