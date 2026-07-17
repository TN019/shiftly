#!/usr/bin/swift
// Generates assets/AppIcon.icns: a macOS-style squircle with a calendar
// grid and a highlighted shift day. Run from the repo root:
//   swift scripts/make_icon.swift
// Requires only AppKit (Command Line Tools are enough).

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// macOS icon grid: 824pt squircle centered on a 1024 canvas.
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185, yRadius: 185
)

// Background gradient: indigo → sky.
NSGradient(colors: [color(0x5B5BD6), color(0x0E9FE8)])!
    .draw(in: squircle, angle: -60)

// Soft inner highlight at the top.
squircle.addClip()
NSGradient(colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0.0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

// Calendar body.
let cal = NSRect(x: 262, y: 258, width: 500, height: 470)
let calPath = NSBezierPath(roundedRect: cal, xRadius: 56, yRadius: 56)
color(0xFFFFFF, 0.96).setFill()
calPath.fill()

// Calendar header band (clipped to the rounded top).
NSGraphicsContext.saveGraphicsState()
calPath.addClip()
color(0x1E2A78, 0.92).setFill()
NSRect(x: cal.minX, y: cal.maxY - 118, width: cal.width, height: 118).fill()
NSGraphicsContext.restoreGraphicsState()

// Binding rings.
for x: CGFloat in [cal.minX + 120, cal.maxX - 120] {
    let ring = NSBezierPath(
        roundedRect: NSRect(x: x - 17, y: cal.maxY - 40, width: 34, height: 96),
        xRadius: 17, yRadius: 17
    )
    color(0xFFFFFF, 0.95).setFill()
    ring.fill()
    let hole = NSBezierPath(
        roundedRect: NSRect(x: x - 7, y: cal.maxY - 30, width: 14, height: 76),
        xRadius: 7, yRadius: 7
    )
    color(0x35429E).setFill()
    hole.fill()
}

// Day grid: 4 columns × 3 rows of rounded squares.
let cell: CGFloat = 76
let gapX = (cal.width - 4 * cell - 2 * 58) / 3
let startX = cal.minX + 58
let startY = cal.minY + 52
for row in 0..<3 {
    for col in 0..<4 {
        let rect = NSRect(
            x: startX + CGFloat(col) * (cell + gapX),
            y: startY + CGFloat(2 - row) * (cell + 26),
            width: cell, height: cell
        )
        let day = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        let isShift = (row == 0 && col == 1) || (row == 1 && col == 3) || (row == 2 && col == 0)
        let isToday = row == 1 && col == 1
        if isToday {
            color(0xFF9F0A).setFill() // highlighted shift day
            day.fill()
        } else if isShift {
            color(0x0A84FF, 0.55).setFill()
            day.fill()
        } else {
            color(0x1E2A78, 0.12).setFill()
            day.fill()
        }
    }
}

image.unlockFocus()

// Write the master PNG.
let iconsetDir = "assets/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not render icon")
}
let master = "\(iconsetDir)/icon_512x512@2x.png"
try! png.write(to: URL(fileURLWithPath: master))
print("rendered \(master)")
