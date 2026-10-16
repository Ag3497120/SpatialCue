// SpatialCue のアプリアイコンを描いて PNG に書き出す。
// 実行: swift Tools/MakeIcon.swift <出力先.png>
//
// 手のひら（手前）と、裏返る途中の手の甲（奥）、手首を回る楕円の矢印で「手を裏表に返す」動きを表す。
// SF Symbols はアイコンに使えないので、手の形は図形の組み合わせで描く。

import AppKit
import CoreGraphics

let size = 1024.0

func handPath() -> CGPath {
    // 指先が上、原点は手のひらの中心あたり（y は上向き）
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: -150, y: -230, width: 300, height: 300), cornerWidth: 95, cornerHeight: 95)
    // 指（人差し指 → 小指）
    let fingers: [(x: Double, top: Double)] = [(-108, 300), (-36, 335), (36, 312), (108, 255)]
    for f in fingers {
        p.addRoundedRect(in: CGRect(x: f.x - 31, y: 0, width: 62, height: f.top), cornerWidth: 31, cornerHeight: 31)
    }
    // 手首
    p.addRoundedRect(in: CGRect(x: -105, y: -330, width: 210, height: 160), cornerWidth: 40, cornerHeight: 40)
    return p
}

func thumbPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -95, y: -150))
    p.addLine(to: CGPoint(x: -245, y: 30))
    return p.copy(strokingWithWidth: 72, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func drawHand(_ ctx: CGContext, color: CGColor) {
    // 重なりが穴にならないよう、透明度のある色はレイヤーにまとめてから塗る
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(color.copy(alpha: 1)!)
    ctx.addPath(handPath())
    ctx.fillPath(using: .winding)
    ctx.addPath(thumbPath())
    ctx.fillPath(using: .winding)
    ctx.endTransparencyLayer()
}

func ellipsePoint(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ deg: Double) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
}

func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, from: Double, to: Double) -> CGPath {
    let p = CGMutablePath()
    let steps = 120
    for i in 0...steps {
        let d = from + (to - from) * Double(i) / Double(steps)
        let pt = ellipsePoint(cx, cy, rx, ry, d)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    return p
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// 背景: 藍色 → 水色
let bg = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.20, green: 0.15, blue: 0.62, alpha: 1),
    CGColor(red: 0.13, green: 0.62, blue: 0.90, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// 中央の柔らかい光
let glow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.18), CGColor(red: 1, green: 1, blue: 1, alpha: 0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 540), endRadius: 430, options: [])

// 手の配置（Watch の円形マスクに収まるよう中央 8 割に）
let scale = 0.95
let handCenter = CGPoint(x: 545, y: 540)
let ring = (cx: 512.0, cy: 300.0, rx: 300.0, ry: 78.0)

// 楕円の矢印（奥側の半分）
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.addPath(arc(ring.cx, ring.cy, ring.rx, ring.ry, from: 15, to: 165))
ctx.strokePath()

// 裏返る途中の手の甲（奥・半透明・横に細い）
ctx.saveGState()
ctx.setAlpha(0.35)
ctx.translateBy(x: 330, y: 545)
ctx.scaleBy(x: 0.38 * scale, y: 0.92 * scale)
ctx.scaleBy(x: -1, y: 1)
drawHand(ctx, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.restoreGState()

// 手のひら（手前）
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(red: 0.05, green: 0.02, blue: 0.25, alpha: 0.45))
ctx.translateBy(x: handCenter.x, y: handCenter.y)
ctx.scaleBy(x: scale, y: scale)
drawHand(ctx, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.restoreGState()

// 手のひらの中心の「合図」の点
let dotCenter = CGPoint(x: handCenter.x, y: handCenter.y - 75 * scale)
let dotGlow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.20, green: 0.80, blue: 1, alpha: 0.55), CGColor(red: 0.20, green: 0.80, blue: 1, alpha: 0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(dotGlow, startCenter: dotCenter, startRadius: 0, endCenter: dotCenter, endRadius: 110, options: [])
ctx.setFillColor(CGColor(red: 0.16, green: 0.62, blue: 0.95, alpha: 1))
ctx.fillEllipse(in: CGRect(x: dotCenter.x - 46, y: dotCenter.y - 46, width: 92, height: 92))

// 楕円の矢印（手前側の半分）と矢じり
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(34)
ctx.addPath(arc(ring.cx, ring.cy, ring.rx, ring.ry, from: 190, to: 335))
ctx.strokePath()
let tip = ellipsePoint(ring.cx, ring.cy, ring.rx, ring.ry, 352)
let back = ellipsePoint(ring.cx, ring.cy, ring.rx, ring.ry, 330)
let dir = CGVector(dx: tip.x - back.x, dy: tip.y - back.y)
let len = (dir.dx * dir.dx + dir.dy * dir.dy).squareRoot()
let ux = dir.dx / len, uy = dir.dy / len
let head = CGMutablePath()
head.move(to: CGPoint(x: tip.x + ux * 30, y: tip.y + uy * 30))
head.addLine(to: CGPoint(x: tip.x - ux * 40 - uy * 52, y: tip.y - uy * 40 + ux * 52))
head.addLine(to: CGPoint(x: tip.x - ux * 40 + uy * 52, y: tip.y - uy * 40 - ux * 52))
head.closeSubpath()
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addPath(head)
ctx.fillPath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
