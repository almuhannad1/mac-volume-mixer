#!/usr/bin/env swift
// Generates Resources/AppIcon.icns: three mixer faders on a rounded-square gradient,
// matching the menu bar glyph. Run: swift scripts/make-app-icon.swift

import AppKit
import Foundation

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = size / 1024

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    // Rounded-square plate with a blue→indigo gradient.
    let plate = CGPath(roundedRect: rect(100, 100, 824, 824), cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil)
    context.saveGState()
    context.addPath(plate)
    context.clip()
    let colors = [
        NSColor(srgbRed: 0.35, green: 0.62, blue: 1.00, alpha: 1).cgColor,
        NSColor(srgbRed: 0.24, green: 0.33, blue: 0.86, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    // Soft highlight across the top.
    context.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
    context.fillEllipse(in: rect(40, 560, 944, 520))
    context.restoreGState()

    // Three faders: track, filled portion, knob. Levels differ, like a real mixer.
    let trackWidth: CGFloat = 30
    let trackBottom: CGFloat = 300
    let trackHeight: CGFloat = 424
    for (index, level) in [0.62, 0.30, 0.48].enumerated() {
        let centerX = 352 + CGFloat(index) * 160
        let x = centerX - trackWidth / 2
        let knobY = trackBottom + trackHeight * CGFloat(level)

        context.setFillColor(NSColor(white: 1, alpha: 0.32).cgColor)
        context.addPath(CGPath(roundedRect: rect(x, trackBottom, trackWidth, trackHeight),
                               cornerWidth: trackWidth / 2 * scale, cornerHeight: trackWidth / 2 * scale, transform: nil))
        context.fillPath()

        context.setFillColor(NSColor(white: 1, alpha: 0.85).cgColor)
        context.addPath(CGPath(roundedRect: rect(x, trackBottom, trackWidth, knobY - trackBottom),
                               cornerWidth: trackWidth / 2 * scale, cornerHeight: trackWidth / 2 * scale, transform: nil))
        context.fillPath()

        context.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 16 * scale,
                          color: NSColor(white: 0, alpha: 0.28).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: rect(centerX - 52, knobY - 52, 104, 104))
        context.setShadow(offset: .zero, blur: 0, color: nil)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (base, scaleFactor) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = base * scaleFactor
    let data = drawIcon(size: CGFloat(pixels)).representation(using: .png, properties: [:])!
    let name = scaleFactor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try data.write(to: iconset.appendingPathComponent(name))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(process.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed (\(process.terminationStatus))")
