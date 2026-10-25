#!/usr/bin/env swift
// Package the supplied artwork at standard macOS icon sizes.
// Usage: swift Scripts/make-icon.swift [output.icns] [source.png]
import AppKit
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Resources/AppIcon.icns")
let source = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : root.appendingPathComponent("Resources/AppIcon.png")

guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      image.width == image.height else {
    fputs("Expected a readable square image at \(source.path)\n", stderr)
    exit(1)
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Sandy-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for (size, name) in [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
        fatalError("Could not create the \(size)px icon representation")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode the \(size)px icon representation")
    }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
print("wrote \(output.path)")
