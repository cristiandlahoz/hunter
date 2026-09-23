import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let outer = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 16/255, green: 47/255, blue: 73/255, alpha: 1).setFill()
outer.fill()

let inner = NSBezierPath(roundedRect: NSRect(x: 138, y: 138, width: 748, height: 748), xRadius: 188, yRadius: 188)
NSColor(calibratedRed: 24/255, green: 63/255, blue: 94/255, alpha: 1).setFill()
inner.fill()

let track = NSBezierPath()
track.move(to: NSPoint(x: 240, y: 520))
track.curve(to: NSPoint(x: 784, y: 520), controlPoint1: NSPoint(x: 370, y: 700), controlPoint2: NSPoint(x: 654, y: 340))
track.lineWidth = 64
track.lineCapStyle = .round
NSColor(calibratedRed: 139/255, green: 61/255, blue: 255/255, alpha: 1).setStroke()
track.stroke()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 546, y: 800))
bolt.line(to: NSPoint(x: 354, y: 493))
bolt.line(to: NSPoint(x: 484, y: 493))
bolt.line(to: NSPoint(x: 448, y: 224))
bolt.line(to: NSPoint(x: 674, y: 568))
bolt.line(to: NSPoint(x: 538, y: 568))
bolt.close()
NSColor(calibratedRed: 120/255, green: 184/255, blue: 51/255, alpha: 1).setFill()
bolt.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
