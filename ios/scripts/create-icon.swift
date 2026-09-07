import AppKit

// A code-drawn vector mark, rendered to the bitmap required by the app icon catalog.
let destination = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.18, green: 0.34, blue: 0.29, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let mark = NSBezierPath()
mark.move(to: NSPoint(x: 512, y: 180))
mark.curve(to: NSPoint(x: 844, y: 512), controlPoint1: NSPoint(x: 555, y: 430), controlPoint2: NSPoint(x: 594, y: 469))
mark.curve(to: NSPoint(x: 512, y: 844), controlPoint1: NSPoint(x: 594, y: 555), controlPoint2: NSPoint(x: 555, y: 594))
mark.curve(to: NSPoint(x: 180, y: 512), controlPoint1: NSPoint(x: 469, y: 594), controlPoint2: NSPoint(x: 430, y: 555))
mark.curve(to: NSPoint(x: 512, y: 180), controlPoint1: NSPoint(x: 430, y: 469), controlPoint2: NSPoint(x: 469, y: 430))
mark.close()
NSColor(red: 0.97, green: 0.965, blue: 0.945, alpha: 1).setFill()
mark.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
