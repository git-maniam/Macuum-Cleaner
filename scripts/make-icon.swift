#!/usr/bin/env swift
// Usage: swift scripts/make-icon.swift AppImage.png "Macuum Cleaner/Resources/Assets.xcassets/AppIcon.appiconset"
// Fits the (non-square) source on a transparent square canvas and writes all macOS icon sizes + Contents.json.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon <source.png> <appiconset dir>\n".utf8)); exit(1)
}
let outDir = args[2]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = CGFloat(pixels)
    let inset = canvas * 0.06
    let box = canvas - inset * 2
    let scale = min(box / src.size.width, box / src.size.height)
    let w = src.size.width * scale, h = src.size.height * scale
    src.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: base * scale).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
        images.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(base)x\#(base)"}"#)
    }
}
let contents = #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
try contents.write(toFile: outDir + "/Contents.json", atomically: true, encoding: .utf8)
