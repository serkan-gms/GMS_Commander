#!/usr/bin/env swift
//
//  generate_icon.swift
//  GMS Commander
//
//  Uygulama simgesini (çift panel motifi) AppKit çizimi ile üretir.
//  Kullanım: swift Scripts/generate_icon.swift <çıktı-klasörü>
//

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("Kullanım: swift generate_icon.swift <çıktı-klasörü>\n".data(using: .utf8)!)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// Tek bir boyutta simge çizer.
func renderIcon(size: CGFloat) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: size, height: size)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let scale = size / 1024.0
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // Yuvarlatılmış gövde (macOS simge ızgarasına uygun pay bırakılır).
    let inset = 64 * scale
    let bodyRect = bounds.insetBy(dx: inset, dy: inset)
    let radius = 200 * scale
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.09, green: 0.20, blue: 0.36, alpha: 1.0),
        NSColor(srgbRed: 0.11, green: 0.44, blue: 0.52, alpha: 1.0)
    ])
    gradient?.draw(in: bodyPath, angle: -90)

    // Üst ışık efekti.
    NSColor(white: 1.0, alpha: 0.10).setFill()
    NSBezierPath(roundedRect: NSRect(
        x: bodyRect.minX,
        y: bodyRect.midY,
        width: bodyRect.width,
        height: bodyRect.height / 2
    ), xRadius: radius, yRadius: radius).fill()

    // İki panel motifi.
    let panelWidth = bodyRect.width * 0.36
    let panelHeight = bodyRect.height * 0.52
    let gap = bodyRect.width * 0.06
    let totalWidth = panelWidth * 2 + gap
    let originX = bodyRect.midX - totalWidth / 2
    let originY = bodyRect.midY - panelHeight / 2

    let leftPanel = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)
    let rightPanel = NSRect(x: originX + panelWidth + gap, y: originY, width: panelWidth, height: panelHeight)

    NSColor(white: 1.0, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: leftPanel, xRadius: 26 * scale, yRadius: 26 * scale).fill()

    NSColor(white: 1.0, alpha: 0.55).setFill()
    NSBezierPath(roundedRect: rightPanel, xRadius: 26 * scale, yRadius: 26 * scale).fill()

    // Satır çizgileri.
    if size >= 64 {
        NSColor(srgbRed: 0.11, green: 0.44, blue: 0.52, alpha: 0.85).setFill()
        let lineHeight = 22 * scale
        let lineInset = 34 * scale
        var y = leftPanel.maxY - 52 * scale
        for _ in 0..<4 {
            let lineRect = NSRect(
                x: leftPanel.minX + lineInset,
                y: y,
                width: leftPanel.width - lineInset * 2,
                height: lineHeight
            )
            NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
            y -= 62 * scale
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Boyut listesi (dosya adı, piksel).
let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in variants {
    guard let rep = renderIcon(size: size), let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Simge üretilemedi: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = outputDirectory.appendingPathComponent(name)
    try data.write(to: url)
    print("✓ \(name) (\(Int(size))px)")
}
