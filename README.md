# SpatialCue

SpatialCue brings the Apple Vision Pro "look at your hand, flip your palm" interaction to **Apple Watch motion sensors and AirPods head tracking**. Without looking at a screen, you can hear the time and control the music playing on your iPhone using wrist movements and finger pinches.

- An Apple Watch app (gesture recognition, haptics, time) and an iPhone app (AirPods head-motion relay, settings, music control) work together.
- Requirements: iPhone with iOS 17 or later, Apple Watch with watchOS 11 or later. AirPods Pro / Max / 3rd generation or later are recommended.
- The UI and speech are available in English and Japanese, and you can switch them independently.

> This is a personal experiment. Gesture thresholds were tuned on synthetic data and may need adjusting on real devices.

## What it does

| Gesture | Result |
|---|---|
| Turn your palm up and look at it | A "pop" tells you it's ready |
| Flip your palm back face-down quickly | Tells the time once with haptics (Digits or Morse code) and/or speech |
| Lower your hand or break the pose while it's talking | Speech and haptics stop |
| On the clock, Double Tap | Play/pause right away |
| On the clock, flick your wrist right / left | Next / previous track |
| On the clock, turn the Digital Crown | Volume, announced every 10% |
| Make a fist or shake your head | Close |

With **Skip the menu** turned off in the iPhone app, a pinch on the clock opens a menu instead (pinch once / twice / three times for play-pause / next / previous), and pinching then moving sets the volume.

A pinch can come from any of these:
- Double Tap (Series 9 / Ultra 2 or later). While the clock is shown, a visible **Pinch** button receives it.
- **Accessibility Quick Actions** (Watch Settings → Accessibility → Quick Actions). This uses the system's double-pinch detection and is the most reliable option.
- Nodding with AirPods
- **Experimental, off by default:** a pinch estimated from the impact on your wrist. The wrist sensors only see a small shock, so opening your hand or moving your fingers can also trigger it. If you turn it on, record pinches and "None" samples (opening your hand, moving your fingers) in **Training** on the Watch.

All settings live in the iPhone app and sync to the Watch automatically.

### Telling the time
- Choose **Vibration**, **Voice**, or **Both**. Speech can also be turned off entirely.
- There are two vibration patterns, both 24-hour:
  - **Digits** (same idea as Apple Watch Taptic Time): long taps for the tens digit, short taps for the ones digit.
  - **Morse code**: each digit in Morse code. Tens are strong taps, ones are light taps.

### Safety (iPhone settings, all on by default)

| Setting | What it does |
|---|---|
| Use gestures | Turn off to stop all air gestures (kill switch) |
| Media controls only with AirPods in | Menu actions are ignored unless the iPhone audio output is AirPods |
| Vibration only without AirPods | No speech or sound effects; the time is conveyed by vibration |
| Ignore while arm is moving | Wrist impacts while swinging your arms (walking, running) aren't treated as pinches |
| Max volume (default 80%) | The volume slider never goes above this |

AirPods switch the audio output back to the speaker when you take them out, so SpatialCue treats them as worn while the output is AirPods.

### Controlling what's playing on the iPhone
- **Music app**: controlled with the public API (`MPMusicPlayerController`).
- **Other apps (Spotify, etc.)**: SpatialCue tries iOS's private MediaRemote framework.
  - If pausing doesn't work, it activates a non-mixable audio session so the other app gets interrupted and pauses.
  - Pinching once again ends the interruption. Whether the app resumes depends on that app.
  - This feature can be left out of the build (see **Build settings** below).

## Installing (build from source)

iOS and watchOS apps must be signed by Apple, so you build them in Xcode on a Mac with your own Apple ID.

1. **Prepare**
   - Install Xcode 26 or later.
   - In Xcode → Settings → Components, install the **watchOS** platform.
   - In Xcode → Settings → Accounts, add your Apple ID and note your **Team ID**.
2. **Clone and create your config**
   ```bash
   git clone https://github.com/Ag3497120/SpatialCue.git
   cd SpatialCue
   cp Config/Local.example.xcconfig Config/Local.xcconfig
   ```
3. **Fill in your values**: set `SC_TEAM_ID` and `SC_BUNDLE_ID` (a unique ID such as `com.yourname.spatialcue`) in `Config/Local.xcconfig`.
4. **Run**: open `SpatialCue.xcodeproj`, choose the `SpatialCue` scheme with your paired iPhone as the destination, and run.
   - If the Watch app isn't installed automatically, run the `SpatialCueWatch` scheme with your Apple Watch as the destination.
   - Developer Mode must be on for both the iPhone and the Watch (Settings → Privacy & Security).

**With a free Apple ID**, the signature expires after 7 days and you need to build again. If signing fails for workout mode (HealthKit), clear `SC_WATCH_ENTITLEMENTS` (below).

### Build settings (`Config/Local.xcconfig`)

| Setting | Default | Purpose |
|---|---|---|
| `SC_TEAM_ID` | empty | Your Apple Developer Team ID |
| `SC_BUNDLE_ID` | `com.example.spatialcue` | iPhone app bundle ID (the Watch app appends `.watchkitapp`) |
| `SC_PRIVATE_API` | `PRIVATE_MEDIAREMOTE` | Clear to build without the private API (required for TestFlight and the App Store) |
| `SC_WATCH_ENTITLEMENTS` | `Watch/SpatialCueWatch.entitlements` | Clear to build without the workout-mode (HealthKit) entitlement |

If you change `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)), regenerate the project with `xcodegen generate`.

### First-time setup
1. On the Watch, turn on Quick Actions (Settings → Accessibility → Quick Actions).
2. Wear your AirPods, open the iPhone app, and allow motion and Music access.
3. In **Head calibration** on the iPhone, tap ① while looking straight ahead, then ② while looking at your Watch.
4. Tap **Calibrate palm**, then turn your palm up and look at it during the Watch countdown.

## How it works

- **Wrist pose** (`Watch/Core/WristGestureDetector.swift`): derives forearm roll and elevation from the gravity vector to detect "looking at the watch face", "palm up / looking at palm", and "quick flip back".
- **Are you looking at your palm?** The positions of your AirPods and hand can't be measured. Instead, a simple body model estimates the direction of your palm as seen from your eyes, using the arm direction. The model assumes your elbow is 0.45 m below and 0.20 m in front of your eyes, and your palm is 0.33 m from the elbow. This direction is compared with the AirPods head direction, and you count as looking when the difference is within the tolerance (25° by default).
- **Audio/haptic interaction** (`Watch/Core/AirController.swift`): "pinch once" and "pinch and move" are told apart by whether your wrist moves more than 6° within 0.6 s of the pinch.
- **Pinch learning** (`Watch/Core/PinchDetector.swift`, `GestureClassifier.swift`): wrist impacts are cut into 0.5 s windows (100 Hz × 6 channels). These are classified as pinch / fist / none with 36 features and k-nearest neighbors. Training finishes on the Watch itself.
- **AirPods** (`iOS/PhoneHub.swift`): the iPhone reads head motion and relays it to the Watch at 15 Hz. Nods and head shakes are also used as input.
- **Staying in the background**: either **workout mode** (`HKWorkoutSession`; runs until you stop it and saves nothing to Health) or an extended runtime session (up to 1 hour). With your arm down for 3 seconds, sampling drops from 100 Hz to 25 Hz. The magnetometer and GPS are not used.
- **Localization** (`Shared/Localization.swift`): strings are written inline as `tr("日本語", "English")` so the language can be switched inside the app.

## Tests

The gesture detection and the interaction state machine can be tested on a Mac with synthetic motion data.

```bash
./Tests/run.sh
```

## Limitations
- Hand position in space (XYZ) isn't available, only angles and motion waveforms.
- Controlling apps other than Music relies on a private API and may not work on every iOS version.
- System volume is changed by moving a hidden `MPVolumeView` on the iPhone, which may not work while the iPhone app is in the background.
- AirPods yaw drifts over time, so the left/right part of gaze detection may need recalibration.
- In workout mode, the system turns on the heart-rate sensor.

## License

[MIT](LICENSE)

## Trademarks

Apple, Apple Watch, AirPods, iPhone, and Apple Vision Pro are trademarks of Apple Inc. This project is not affiliated with Apple Inc.
