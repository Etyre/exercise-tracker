// Renders the app icon (white dumbbell on teal) at every size iOS and
// Android need. Run: swift tool/make_icon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func render(_ px: Int, rounded: Bool) -> CGImage {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Background: teal gradient, lighter at the top.
    let full = CGRect(x: 0, y: 0, width: s, height: s)
    if rounded {
        ctx.addPath(CGPath(roundedRect: full, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil))
        ctx.clip()
    }
    let colors = [CGColor(colorSpace: cs, components: [0.16, 0.52, 0.44, 1])!,
                  CGColor(colorSpace: cs, components: [0.08, 0.36, 0.30, 1])!] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Dumbbell, centred, in white. All sizes relative to the canvas.
    ctx.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, 1])!)
    let cy = s * 0.5
    func rr(_ x: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        let rect = CGRect(x: x, y: cy - h / 2, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
    }
    // bar
    rr(s * 0.17, s * 0.66, s * 0.085, s * 0.04)
    // inner plates (tall) and outer plates (shorter), each side
    let innerW = s * 0.085, innerH = s * 0.46
    let outerW = s * 0.065, outerH = s * 0.32
    let gap = s * 0.025
    let innerL = s * 0.25, innerR = s * 0.75 - innerW
    rr(innerL, innerW, innerH, s * 0.025)
    rr(innerR, innerW, innerH, s * 0.025)
    rr(innerL - gap - outerW, outerW, outerH, s * 0.02)
    rr(innerR + innerW + gap, outerW, outerH, s * 0.02)
    return ctx.makeImage()!
}

func write(_ img: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed \(url.path)") }
}

// iOS: every entry in the asset catalog.
let setDir = root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let contents = try! JSONSerialization.jsonObject(with: Data(contentsOf: setDir.appendingPathComponent("Contents.json"))) as! [String: Any]
var done = Set<String>()
for img in contents["images"] as! [[String: Any]] {
    let name = img["filename"] as! String
    if done.contains(name) { continue }
    done.insert(name)
    let pt = Double((img["size"] as! String).split(separator: "x")[0])!
    let scale = Double((img["scale"] as! String).dropLast())!
    let px = Int((pt * scale).rounded())
    write(render(px, rounded: false), to: setDir.appendingPathComponent(name))
    print("ios  \(name) \(px)px")
}

// Android legacy launcher icons.
for (dir, px) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    let url = root.appendingPathComponent("android/app/src/main/res/mipmap-\(dir)/ic_launcher.png")
    write(render(px, rounded: true), to: url)
    print("android mipmap-\(dir) \(px)px")
}
// A preview copy for the README / quick look.
write(render(512, rounded: true), to: root.appendingPathComponent("tool/icon_preview.png"))
