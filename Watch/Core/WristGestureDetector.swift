import Foundation

struct MotionSample {
    var t: TimeInterval
    var gravity: Vec3   // 手首フレーム: +x = 指先方向, +z = 文字盤の外向き
    var accel: Vec3     // userAcceleration（G）
    var gyro: Vec3      // rad/s
    var forearm = Vec3(x: 1, y: 0, z: 0)   // 世界座標での前腕の向き（肘 → 指先、z = 上）
}

/// 装着の向きの差を吸収する。竜頭が肘側を向いていたら z 軸まわりに 180° 回す。
struct WristFrame {
    var crownTowardHand = true

    func apply(_ v: Vec3) -> Vec3 { crownTowardHand ? v : Vec3(x: -v.x, y: -v.y, z: v.z) }
}

enum WristPose: String {
    case faceUp, side, palmUp, vertical

    var title: String {
        switch self {
        case .faceUp: return tr("文字盤が上", "Face up")
        case .side: return tr("横向き", "Sideways")
        case .palmUp: return tr("手のひらが上", "Palm up")
        case .vertical: return tr("腕が垂直", "Arm vertical")
        }
    }
}

enum WristEvent: Equatable {
    case glanceBegan, glanceEnded       // 文字盤を見ている
    case palmUpBegan, palmUpEnded       // 手のひらを上に向けて腕を上げている（表に返した場合は flipToFace のみ）
    case palmGazeBegan, palmGazeEnded   // その手のひらを見ている
    case flipToFace                     // 手のひら → 表へ素早く返した
    case flick(Int)                     // 手首を左右に払う（+1 / -1）
}

/// 「手のひらを見ている」と判定した姿勢を基準として記録したもの
struct PalmCalibration: Codable {
    var headPitch = 0.0
    var headYaw = 0.0
    var palmElevation = 0.0
    var palmAzimuth = 0.0
    var yawSign = 1.0
}

/// 頭の向き（AirPods）
struct HeadSample {
    var pitch: Double
    var yaw: Double
    var look: Double       // 0…1（時計を見ている度合い）
    var downSign: Double   // 下を向くとピッチが増えるなら +1
}

struct WristReading {
    var roll = 0.0       // 前腕のひねり（度）: 文字盤が上 = 0, 手のひらが上 = ±180
    var elevation = 0.0  // 前腕の上下（度）: 指先が上 = +90
    var pose = WristPose.vertical
    var gyro = 0.0       // 回転の速さ（rad/s, 平滑化）
    var glancing = false
    var palmUp = false
    var palmGaze = false
    var palmElevation = 0.0   // 目から見た手のひら（推定）の仰角
    var palmAzimuth = 0.0     // 同じく方位角
    var gazeError: Double?    // 頭の向きと手のひら方向のずれ（度）
    var jerk = 0.0
}

/// Vision Pro の「手を見る・裏返す」を、手首の姿勢と AirPods の頭の向きで再現する状態機械。
final class WristGestureDetector {
    struct Config {
        var useHead = true                // false なら頭の向き（AirPods）を使わず手首の動きだけで判定
        var requireHeadLook = false
        var headLookThreshold = 0.5
        var flickThreshold = 5.0          // rad/s
        var palmCalibration: PalmCalibration?
        var gazeThreshold = 25.0          // 度
    }

    /// 目 → 手のひらの位置を推定するための体の簡易モデル（メートル）
    static let elbowDrop = 0.45       // 目から肘までの高さ
    static let elbowForward = 0.20    // 目から肘までの前方距離
    static let forearmReach = 0.33    // 肘から手のひら（時計の少し先）まで

    var config = Config()
    var head: () -> HeadSample? = { nil }
    private(set) var reading = WristReading()

    private var rawPose = WristPose.vertical
    private var rawSince: TimeInterval = 0
    private var stablePose = WristPose.vertical

    private var glancing = false
    private var glanceCandidateSince: TimeInterval?
    private var lastLookTime: TimeInterval = -10

    private var palmCandidateSince: TimeInterval?
    private var palmOn = false
    private var lastPalmTime: TimeInterval = -10
    private var gazeOn = false
    private var gazeChangeSince: TimeInterval?

    private var lastFlick: TimeInterval = -10
    private var smoothGyro = 0.0

    func feed(_ s: MotionSample) -> [WristEvent] {
        var events: [WristEvent] = []
        let n = max(s.gravity.length, 1e-6)
        let gx = s.gravity.x / n, gy = s.gravity.y / n, gz = s.gravity.z / n
        let roll = atan2(gy, -gz) * 180 / .pi
        let elevation = asin(clamp(-gx, -1, 1)) * 180 / .pi
        smoothGyro = smoothGyro * 0.8 + s.gyro.length * 0.2

        let pose: WristPose
        if elevation < -55 || elevation > 70 { pose = .vertical }   // 腕が垂直だとひねり角が定まらない
        else if abs(roll) < 55 { pose = .faceUp }
        else if abs(roll) > 125 { pose = .palmUp }
        else { pose = .side }

        if pose != rawPose { rawPose = pose; rawSince = s.t }
        if rawPose != stablePose && s.t - rawSince >= 0.06 { stablePose = rawPose }

        let headSample = config.useHead ? head() : nil
        let headOK: Bool
        if config.requireHeadLook, let h = headSample {
            headOK = h.look >= config.headLookThreshold
        } else {
            headOK = true
        }
        let raised = elevation > -40

        // 目から見た手のひらの方向（体の簡易モデル）
        let f = s.forearm
        let fl = max(f.length, 1e-6)
        let forearmElev = asin(clamp(f.z / fl, -1, 1))
        let palmHeight = -Self.elbowDrop + Self.forearmReach * sin(forearmElev)
        let palmDist = Self.elbowForward + Self.forearmReach * cos(forearmElev)
        let palmElevation = atan2(palmHeight, palmDist) * 180 / .pi
        let palmAzimuth = atan2(f.y, f.x) * 180 / .pi

        // MARK: 手のひら

        if palmOn {
            if stablePose == .palmUp {
                lastPalmTime = s.t
            } else if stablePose == .faceUp && s.t - lastPalmTime < 0.5 {
                // 手のひら → 表へ素早く返した
                palmOn = false
                endGaze(&events)
                events.append(.flipToFace)
                glancing = true
                lastLookTime = s.t
                events.append(.glanceBegan)
            } else if s.t - lastPalmTime > 0.4 {
                palmOn = false
                endGaze(&events)
                events.append(.palmUpEnded)
            }
        } else if stablePose == .palmUp && raised {
            let since = palmCandidateSince ?? s.t
            palmCandidateSince = since
            if s.t - since >= 0.25 {
                palmOn = true
                lastPalmTime = s.t
                if glancing { glancing = false; events.append(.glanceEnded) }
                events.append(.palmUpBegan)
            }
        } else {
            palmCandidateSince = nil
        }

        // MARK: 手のひらを見ているか

        var gazeError: Double?
        var gazeNow = false
        if palmOn {
            if let h = headSample {
                if let c = config.palmCalibration {
                    let elH = c.palmElevation - h.downSign * (h.pitch - c.headPitch)
                    let azH = c.palmAzimuth + c.yawSign * wrapDegrees(h.yaw - c.headYaw)
                    let err = Self.angularDistance(az1: azH, el1: elH, az2: palmAzimuth, el2: palmElevation)
                    gazeError = err
                    gazeNow = err < config.gazeThreshold
                } else {
                    gazeNow = h.look >= config.headLookThreshold
                }
            } else {
                gazeNow = true   // AirPods なし: 手のひらを上げているだけで「見ている」とみなす
            }
        }
        if palmOn && gazeNow != gazeOn {
            let since = gazeChangeSince ?? s.t
            gazeChangeSince = since
            if s.t - since >= (gazeNow ? 0.2 : 0.3) {
                gazeOn = gazeNow
                gazeChangeSince = nil
                events.append(gazeNow ? .palmGazeBegan : .palmGazeEnded)
            }
        } else {
            gazeChangeSince = nil
        }

        // MARK: 文字盤を見る

        if !palmOn {
            let lookingAtFace = stablePose == .faceUp && gz < -0.3 && raised && headOK
            if glancing {
                if lookingAtFace {
                    lastLookTime = s.t
                    if abs(s.gyro.z) > config.flickThreshold && abs(s.gyro.z) > 1.5 * abs(s.gyro.x)
                        && s.t - lastFlick > 0.6 {
                        lastFlick = s.t
                        events.append(.flick(s.gyro.z > 0 ? 1 : -1))
                    }
                } else if s.t - lastLookTime > 0.4 {
                    glancing = false
                    glanceCandidateSince = nil
                    events.append(.glanceEnded)
                }
            } else if lookingAtFace && gz < -0.45 && s.gyro.length < 1.2 {
                let since = glanceCandidateSince ?? s.t
                glanceCandidateSince = since
                if s.t - since >= 0.2 {
                    glancing = true
                    lastLookTime = s.t
                    events.append(.glanceBegan)
                }
            } else {
                glanceCandidateSince = nil
            }
        }

        reading.roll = roll
        reading.elevation = elevation
        reading.pose = stablePose
        reading.gyro = smoothGyro
        reading.glancing = glancing
        reading.palmUp = palmOn
        reading.palmGaze = gazeOn
        reading.palmElevation = palmElevation
        reading.palmAzimuth = palmAzimuth
        reading.gazeError = gazeError
        return events
    }

    private func endGaze(_ events: inout [WristEvent]) {
        if gazeOn { gazeOn = false; events.append(.palmGazeEnded) }
        gazeChangeSince = nil
        palmCandidateSince = nil
    }

    static func angularDistance(az1: Double, el1: Double, az2: Double, el2: Double) -> Double {
        let r = Double.pi / 180
        let c = sin(el1 * r) * sin(el2 * r) + cos(el1 * r) * cos(el2 * r) * cos(wrapDegrees(az1 - az2) * r)
        return acos(clamp(c, -1, 1)) / r
    }
}
