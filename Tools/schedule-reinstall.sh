#!/bin/sh
# Reinstall SpatialCue automatically so a free Apple ID's 7-day signature never runs out.
# 無料の Apple ID の 7 日の署名が切れないよう、自動で入れ直す（macOS の launchd を使う）。
#
#   ./Tools/schedule-reinstall.sh on [HH:MM]   # check every day at HH:MM (default 20:00)
#   ./Tools/schedule-reinstall.sh off          # stop
#   ./Tools/schedule-reinstall.sh status
#
# Every day it runs Tools/install.sh --if-due --notify, which only reinstalls when the last
# success was 6+ days ago, and retries the next day if it fails (e.g. the Watch was locked).
# The Mac must be on, and the iPhone and Watch nearby on the same Wi-Fi.
set -e
cd "$(dirname "$0")/.."
REPO=$(pwd)
LABEL=io.github.spatialcue.reinstall
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

case "${1:-status}" in
on)
    TIME=${2:-20:00}
    HOUR=$(echo "$TIME" | cut -d: -f1 | sed 's/^0//')
    MINUTE=$(echo "$TIME" | cut -d: -f2 | sed 's/^0//')
    [ -n "$HOUR" ] || HOUR=0
    [ -n "$MINUTE" ] || MINUTE=0
    mkdir -p "$HOME/Library/LaunchAgents" build/install
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$REPO/Tools/install.sh</string>
        <string>--if-due</string>
        <string>--notify</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>$HOUR</integer>
        <key>Minute</key><integer>$MINUTE</integer>
    </dict>
    <key>StandardOutPath</key><string>$REPO/build/install/scheduled.log</string>
    <key>StandardErrorPath</key><string>$REPO/build/install/scheduled.log</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "✓ Scheduled: every day at $TIME, reinstalls when 6+ days have passed."
    echo "  Log: $REPO/build/install/scheduled.log"
    ;;
off)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "✓ Stopped automatic reinstalls."
    ;;
status)
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        echo "Scheduled ($PLIST)"
    else
        echo "Not scheduled"
    fi
    if [ -f build/install/last-success ]; then
        echo "Last successful install: $(date -r "$(cat build/install/last-success)")"
    fi
    ;;
*)
    sed -n '2,12p' "$0"
    exit 2
    ;;
esac
