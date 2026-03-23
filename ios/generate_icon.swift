#!/usr/bin/env swift
// Generates a 1024x1024 RAGFlow app icon and writes it to the asset catalog.
// Run from the repo root: swift ios/generate_icon.swift

import AppKit
import CoreGraphics

let size = 1024
let scale: CGFloat = 1

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // --- Background: indigo → purple diagonal gradient ---
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        CGColor(red: 0.22, green: 0.13, blue: 0.68, alpha: 1), // deep indigo
        CGColor(red: 0.50, green: 0.08, blue: 0.72, alpha: 1), // vivid purple
    ] as CFArray
    let locs: [CGFloat] = [0, 1]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: locs)!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(size)),
        end: CGPoint(x: CGFloat(size), y: 0),
        options: []
    )

    // --- Rounded white card (document stack) ---
    let cardW: CGFloat = 580
    let cardH: CGFloat = 420
    let cardX = (CGFloat(size) - cardW) / 2
    let cardY: CGFloat = 360
    let cardRadius: CGFloat = 48
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    let card = CGPath(roundedRect: CGRect(x: cardX, y: cardY, width: cardW, height: cardH),
                      cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
    ctx.addPath(card)
    ctx.fillPath()

    // Slightly offset second card (stack effect)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    let card2 = CGPath(roundedRect: CGRect(x: cardX + 24, y: cardY - 28, width: cardW, height: cardH),
                       cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
    ctx.addPath(card2)
    ctx.fillPath()

    // Third card
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
    let card3 = CGPath(roundedRect: CGRect(x: cardX + 48, y: cardY - 56, width: cardW, height: cardH),
                       cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
    ctx.addPath(card3)
    ctx.fillPath()

    // --- Front card solid ---
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    let front = CGPath(roundedRect: CGRect(x: cardX, y: cardY, width: cardW, height: cardH),
                       cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
    ctx.addPath(front)
    ctx.fillPath()

    // --- Text lines on the card ---
    let lineColor = CGColor(red: 0.30, green: 0.20, blue: 0.65, alpha: 0.25)
    ctx.setFillColor(lineColor)
    let lineX = cardX + 60
    let lineH: CGFloat = 22
    let lineRadii: CGFloat = 11
    let lineWidths: [CGFloat] = [380, 310, 250]
    for (i, w) in lineWidths.enumerated() {
        let lineY = cardY + 80 + CGFloat(i) * 90
        let line = CGPath(roundedRect: CGRect(x: lineX, y: lineY, width: w, height: lineH),
                          cornerWidth: lineRadii, cornerHeight: lineRadii, transform: nil)
        ctx.addPath(line)
        ctx.fillPath()
    }

    // --- "R" letter mark at top-left of card ---
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 90, weight: .heavy),
        .foregroundColor: NSColor(cgColor: CGColor(red: 0.35, green: 0.20, blue: 0.75, alpha: 0.80))!,
    ]
    let str = NSAttributedString(string: "R", attributes: attrs)
    str.draw(at: NSPoint(x: cardX + 56, y: cardY + cardH - 110))

    // --- Subtle AI sparkle dot cluster bottom-right ---
    let dotColor = CGColor(red: 0.60, green: 0.40, blue: 1.0, alpha: 0.85)
    ctx.setFillColor(dotColor)
    let dotCX = cardX + cardW - 80
    let dotCY = cardY + 70
    let dotSizes: [(CGFloat, CGFloat, CGFloat)] = [
        (0, 0, 18), (-28, 22, 12), (28, 22, 12), (0, 44, 10)
    ]
    for (dx, dy, r) in dotSizes {
        ctx.fillEllipse(in: CGRect(x: dotCX + dx - r/2, y: dotCY + dy - r/2, width: r, height: r))
    }

    return true
}

// Export to PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("ERROR: could not render image")
    exit(1)
}

let outputPath = "ios/RAGFlowMobile/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let url = URL(fileURLWithPath: outputPath)
do {
    try png.write(to: url)
    print("✓ Icon written to \(outputPath)")
} catch {
    print("ERROR writing icon: \(error)")
    exit(1)
}
