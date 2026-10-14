import AppKit

// Resize the approved artwork only. Do not replace it with a drawn approximation.
let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = project.appendingPathComponent("Resources", isDirectory: true)
let sourceURL = resources.appendingPathComponent("AppIconSource.png")
guard let source = NSImage(contentsOf: sourceURL), source.size.width == source.size.height else {
    fatalError("Resources/AppIconSource.png must be the approved square artwork")
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("spacebar-icon-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func resizedPNG(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: size, height: size)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    return bitmap.representation(using: .png, properties: [:])!
}

for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32),
                      ("icon_32x32", 32), ("icon_32x32@2x", 64),
                      ("icon_128x128", 128), ("icon_128x128@2x", 256),
                      ("icon_256x256", 256), ("icon_256x256@2x", 512),
                      ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try resizedPNG(size: size).write(to: iconset.appendingPathComponent(name + ".png"), options: .atomic)
}
let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
let converted = temporary.appendingPathComponent("AppIcon.icns")
converter.arguments = ["-c", "icns", "-o", converted.path, iconset.path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else { fatalError("Icon conversion failed") }
try resizedPNG(size: 512).write(to: resources.appendingPathComponent("AppIcon.png"), options: .atomic)
try Data(contentsOf: converted).write(to: resources.appendingPathComponent("AppIcon.icns"), options: .atomic)
print("Approved SpaceBar artwork converted to all native app-icon sizes.")
