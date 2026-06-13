#!/usr/bin/env swift
// Generates the PulseVM app icon (navy→electric gradient rounded square + white
// bolt) at all macOS sizes into the asset catalog. Run: swift scripts/make-icon.swift
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : (FileManager.default.currentDirectoryPath + "/apps/macos/Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let S = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext

    // Rounded-rect "squircle"-ish background with macOS-style padding.
    let pad = S * 0.085
    let rect = CGRect(x: pad, y: pad, width: S - 2 * pad, height: S - 2 * pad)
    let radius = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.043, green: 0.078, blue: 0.215, alpha: 1), // navy #0B1437
        CGColor(red: 0.137, green: 0.282, blue: 0.784, alpha: 1), // primary #2348C8
        CGColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1),     // accent #4F7CFF
    ] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: pad, y: S - pad), end: CGPoint(x: S - pad, y: pad), options: [])
    ctx.restoreGState()

    // White lightning bolt (SF Symbol), centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: S * 0.48, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let bs = sym.size
        let r = NSRect(x: (S - bs.width) / 2, y: (S - bs.height) / 2, width: bs.width, height: bs.height)
        sym.draw(in: r)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// macOS icon set: (filename, pixel size)
let items: [(String, Int)] = [
    ("icon_16.png", 16), ("icon_16@2x.png", 32),
    ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256),
    ("icon_256.png", 256), ("icon_256@2x.png", 512),
    ("icon_512.png", 512), ("icon_512@2x.png", 1024),
]
for (name, px) in items {
    try! render(px).write(to: URL(fileURLWithPath: out + "/" + name))
}

let contents = """
{
  "images" : [
    { "idiom":"mac", "scale":"1x", "size":"16x16", "filename":"icon_16.png" },
    { "idiom":"mac", "scale":"2x", "size":"16x16", "filename":"icon_16@2x.png" },
    { "idiom":"mac", "scale":"1x", "size":"32x32", "filename":"icon_32.png" },
    { "idiom":"mac", "scale":"2x", "size":"32x32", "filename":"icon_32@2x.png" },
    { "idiom":"mac", "scale":"1x", "size":"128x128", "filename":"icon_128.png" },
    { "idiom":"mac", "scale":"2x", "size":"128x128", "filename":"icon_128@2x.png" },
    { "idiom":"mac", "scale":"1x", "size":"256x256", "filename":"icon_256.png" },
    { "idiom":"mac", "scale":"2x", "size":"256x256", "filename":"icon_256@2x.png" },
    { "idiom":"mac", "scale":"1x", "size":"512x512", "filename":"icon_512.png" },
    { "idiom":"mac", "scale":"2x", "size":"512x512", "filename":"icon_512@2x.png" }
  ],
  "info" : { "author":"xcode", "version":1 }
}
"""
try! contents.write(toFile: out + "/Contents.json", atomically: true, encoding: .utf8)
print("✓ wrote \(items.count) icons + Contents.json to \(out)")
