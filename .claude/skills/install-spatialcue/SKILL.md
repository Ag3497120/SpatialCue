---
name: install-spatialcue
description: Build and install (or reinstall) SpatialCue on the user's iPhone and Apple Watch with their own Apple ID, including the weekly re-sign needed with a free Apple ID, and set up or stop automatic reinstalls. Use when the user asks to install, reinstall, refresh, re-sign or update SpatialCue on their devices, or when the app stopped opening because the 7-day signature expired.
---

# Install SpatialCue on iPhone and Apple Watch

SpatialCue has no App Store build, so it is built with the user's own Apple ID. With a free Apple ID the signature lasts 7 days; reinstalling renews it.

## 1. Check the one-time setup

Run these from the repository root. Fix anything missing before building, and ask the user to do steps only they can do (signing in, tapping on their devices).

- `xcodebuild -version` works (Xcode 26 or later) and `xcrun simctl list runtimes | grep -i watch` shows a watchOS runtime. If not: Xcode → Settings → Components → watchOS.
- `Config/Local.xcconfig` exists. If not, copy `Config/Local.example.xcconfig` and ask the user for their Team ID (Xcode → Settings → Accounts) and a unique bundle ID such as `com.theirname.spatialcue`. Never invent a Team ID.
- The user's Apple ID is signed in to Xcode (Settings → Accounts). Only the user can do this.
- Developer Mode is on for the iPhone and the Watch (Settings → Privacy & Security → Developer Mode). Only the user can do this.

## 2. Build and install

```bash
./Tools/install.sh            # full edition
./Tools/install.sh --stable   # stable edition (same features as TestFlight)
```

The script finds the paired iPhone and Watch, builds for each (this registers the devices and renews the signature), and installs with retries. The full log is in `build/install/last.log`.

## 3. When it fails

Read `build/install/last.log` and match the error:

| Error in the log | What to do |
|---|---|
| `may need to be unlocked`, `Timed out waiting for all destinations` | Ask the user to unlock the Watch, take it off the charger, and keep it near the Mac on the same Wi-Fi. Then run the script again. |
| `This provisioning profile cannot be installed on this device` (Watch) | The Watch isn't registered yet. Have the user unlock it, then run again so the Watch build registers it. |
| `No Account for Team`, `No signing certificate` | The Apple ID isn't signed in to Xcode, or `SC_TEAM_ID` is wrong. |
| `bundle identifier ... is not available` | `SC_BUNDLE_ID` is taken. Pick another unique one. |
| HealthKit / `com.apple.developer.healthkit` with a free Apple ID | Set `SC_WATCH_ENTITLEMENTS =` (empty) in `Config/Local.xcconfig`. Workout mode will be unavailable. |
| `The device disconnected`, `tunnel connection failed`, `CoreDeviceError error 4000` | Transient Wi-Fi issue with the Watch. Run again; the script already retries. |
| `Developer Mode` | Ask the user to turn on Developer Mode on that device and restart it. |
| Watch shows no app after install | In the iPhone Watch app → My Watch, find SpatialCue and tap Install, or run the script again. |

A free Apple ID allows only 3 of your own apps per device at a time, and SpatialCue uses 2 of them (iPhone + Watch). If installs fail with an app-limit error, ask the user which of their own apps to remove.

## 4. Automatic reinstalls (free Apple ID)

Ask before turning this on: it adds a launchd agent to the user's Mac.

```bash
./Tools/schedule-reinstall.sh on 20:00   # check daily at 20:00, reinstall when 6+ days have passed
./Tools/schedule-reinstall.sh status
./Tools/schedule-reinstall.sh off
```

It retries the next day if the Watch was locked or away, and shows a macOS notification with the result. The log is `build/install/scheduled.log`.
