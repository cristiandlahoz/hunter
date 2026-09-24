import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let houndURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let hound = NSImage(contentsOf: houndURL) else {
    fatalError("Could not load bloodhound SVG")
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(
    roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960),
    xRadius: 220,
    yRadius: 220
)
NSColor(calibratedRed: 16 / 255, green: 47 / 255, blue: 73 / 255, alpha: 1).setFill()
background.fill()

let inset = NSBezierPath(
    roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840),
    xRadius: 184,
    yRadius: 184
)
NSColor(calibratedRed: 24 / 255, green: 63 / 255, blue: 94 / 255, alpha: 1).setFill()
inset.fill()

hound.draw(
    in: NSRect(x: 142, y: 142, width: 740, height: 740),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
try png.write(to: outputURL)
