import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath + "/MusicDossierIcon.png"
let outputURL = URL(fileURLWithPath: outputPath)

let canvasSize = CGSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to allocate bitmap image rep.\n", stderr)
    exit(1)
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer {
    NSGraphicsContext.restoreGraphicsState()
}

let context = graphicsContext.cgContext

context.interpolationQuality = .high
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, gradient: NSGradient, angle: CGFloat) {
    gradient.draw(in: path, angle: angle)
}

func drawShadow(path: NSBezierPath, color: NSColor, blur: CGFloat, offset: CGSize) {
    context.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    path.fill()
    context.restoreGState()
}

let bounds = CGRect(origin: .zero, size: canvasSize)
let backgroundPath = roundedRect(bounds.insetBy(dx: 52, dy: 52), radius: 224)
let backgroundGradient = NSGradient(colors: [
    color(252, 248, 238),
    color(235, 222, 206),
    color(223, 209, 190)
])!
drawShadow(path: backgroundPath, color: color(114, 78, 46, 0.18), blur: 34, offset: CGSize(width: 0, height: -10))
fill(backgroundPath, gradient: backgroundGradient, angle: -35)

let overlayOne = NSBezierPath(ovalIn: CGRect(x: 74, y: 640, width: 360, height: 260))
color(255, 255, 255, 0.28).setFill()
overlayOne.fill()

let overlayTwo = NSBezierPath(ovalIn: CGRect(x: 624, y: 136, width: 280, height: 220))
color(124, 89, 56, 0.10).setFill()
overlayTwo.fill()

for index in 0 ..< 18 {
    let alpha = 0.025 + CGFloat(index) * 0.003
    let inset = CGFloat(index) * 10
    let ringRect = CGRect(x: 562 + inset, y: 178 + inset, width: 314 - inset * 2, height: 314 - inset * 2)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = 1
    color(255, 255, 255, alpha).setStroke()
    ring.stroke()
}

let recordRect = CGRect(x: 528, y: 142, width: 360, height: 360)
let recordPath = NSBezierPath(ovalIn: recordRect)
let recordGradient = NSGradient(colors: [
    color(31, 45, 41),
    color(18, 25, 23)
])!
drawShadow(path: recordPath, color: color(26, 20, 17, 0.26), blur: 34, offset: CGSize(width: 0, height: -12))
fill(recordPath, gradient: recordGradient, angle: -65)

for groove in stride(from: 12 as CGFloat, through: 132, by: 16) {
    let grooveRect = recordRect.insetBy(dx: groove, dy: groove)
    let groovePath = NSBezierPath(ovalIn: grooveRect)
    groovePath.lineWidth = groove < 34 ? 1.6 : 1
    color(245, 233, 219, groove < 40 ? 0.16 : 0.08).setStroke()
    groovePath.stroke()
}

let recordInner = NSBezierPath(ovalIn: CGRect(x: 654, y: 268, width: 108, height: 108))
let recordInnerGradient = NSGradient(colors: [
    color(184, 126, 68),
    color(123, 76, 42)
])!
fill(recordInner, gradient: recordInnerGradient, angle: 90)

let recordCenter = NSBezierPath(ovalIn: CGRect(x: 696, y: 310, width: 24, height: 24))
color(247, 239, 229).setFill()
recordCenter.fill()

context.saveGState()
let cardCenter = CGPoint(x: 396, y: 528)
context.translateBy(x: cardCenter.x, y: cardCenter.y)
context.rotate(by: -.pi / 18)
context.translateBy(x: -cardCenter.x, y: -cardCenter.y)

let cardRect = CGRect(x: 188, y: 206, width: 474, height: 578)
let cardPath = roundedRect(cardRect, radius: 68)
drawShadow(path: cardPath, color: color(88, 58, 34, 0.20), blur: 30, offset: CGSize(width: 0, height: -12))
fill(cardPath, gradient: NSGradient(colors: [
    color(255, 252, 246),
    color(243, 232, 219)
])!, angle: -90)
color(175, 136, 98, 0.35).setStroke()
cardPath.lineWidth = 2.5
cardPath.stroke()

let tabRect = CGRect(x: 250, y: 684, width: 172, height: 84)
let tabPath = roundedRect(tabRect, radius: 34)
fill(tabPath, gradient: NSGradient(colors: [
    color(199, 152, 90),
    color(151, 104, 62)
])!, angle: 0)

let tabCutout = NSBezierPath(ovalIn: CGRect(x: 318, y: 708, width: 38, height: 38))
color(248, 241, 232).setFill()
tabCutout.fill()

let portraitFrame = roundedRect(CGRect(x: 248, y: 470, width: 354, height: 230), radius: 48)
fill(portraitFrame, gradient: NSGradient(colors: [
    color(214, 199, 176),
    color(176, 155, 128)
])!, angle: -38)

let portraitInset = roundedRect(CGRect(x: 266, y: 488, width: 318, height: 194), radius: 38)
fill(portraitInset, gradient: NSGradient(colors: [
    color(95, 119, 105),
    color(63, 75, 71)
])!, angle: 90)

let halo = NSBezierPath(ovalIn: CGRect(x: 330, y: 532, width: 188, height: 120))
color(244, 225, 187, 0.18).setFill()
halo.fill()

let head = NSBezierPath(ovalIn: CGRect(x: 372, y: 570, width: 104, height: 104))
fill(head, gradient: NSGradient(colors: [
    color(248, 223, 187),
    color(214, 177, 129)
])!, angle: 90)

let shoulders = NSBezierPath(roundedRect: CGRect(x: 314, y: 506, width: 220, height: 104), xRadius: 52, yRadius: 52)
fill(shoulders, gradient: NSGradient(colors: [
    color(58, 49, 47),
    color(29, 24, 23)
])!, angle: 90)

let labelPill = roundedRect(CGRect(x: 284, y: 430, width: 130, height: 28), radius: 14)
color(191, 142, 92, 0.22).setFill()
labelPill.fill()

let lineColor = color(102, 83, 68, 0.82)
for (index, width) in [258, 210, 226, 168].enumerated() {
    let y = 388 - CGFloat(index) * 44
    let lineRect = CGRect(x: 284, y: y, width: CGFloat(width), height: 14)
    let line = roundedRect(lineRect, radius: 7)
    lineColor.setFill()
    line.fill()
}

let stamp = roundedRect(CGRect(x: 472, y: 258, width: 98, height: 98), radius: 26)
fill(stamp, gradient: NSGradient(colors: [
    color(173, 114, 58),
    color(132, 80, 44)
])!, angle: 90)

let notePath = NSBezierPath()
notePath.move(to: CGPoint(x: 510, y: 330))
notePath.line(to: CGPoint(x: 510, y: 290))
notePath.line(to: CGPoint(x: 548, y: 300))
notePath.line(to: CGPoint(x: 548, y: 340))
notePath.lineWidth = 11
notePath.lineCapStyle = .round
notePath.lineJoinStyle = .round
color(249, 243, 236).setStroke()
notePath.stroke()

let noteOne = NSBezierPath(ovalIn: CGRect(x: 486, y: 272, width: 32, height: 32))
let noteTwo = NSBezierPath(ovalIn: CGRect(x: 524, y: 284, width: 32, height: 32))
color(249, 243, 236).setFill()
noteOne.fill()
noteTwo.fill()

context.restoreGState()

let sparkle = NSBezierPath()
sparkle.move(to: CGPoint(x: 814, y: 696))
sparkle.line(to: CGPoint(x: 826, y: 734))
sparkle.line(to: CGPoint(x: 864, y: 746))
sparkle.line(to: CGPoint(x: 826, y: 758))
sparkle.line(to: CGPoint(x: 814, y: 796))
sparkle.line(to: CGPoint(x: 802, y: 758))
sparkle.line(to: CGPoint(x: 764, y: 746))
sparkle.line(to: CGPoint(x: 802, y: 734))
sparkle.close()
color(191, 142, 92, 0.88).setFill()
sparkle.fill()

let sparkleSmall = NSBezierPath()
sparkleSmall.move(to: CGPoint(x: 716, y: 650))
sparkleSmall.line(to: CGPoint(x: 722, y: 670))
sparkleSmall.line(to: CGPoint(x: 742, y: 676))
sparkleSmall.line(to: CGPoint(x: 722, y: 682))
sparkleSmall.line(to: CGPoint(x: 716, y: 702))
sparkleSmall.line(to: CGPoint(x: 710, y: 682))
sparkleSmall.line(to: CGPoint(x: 690, y: 676))
sparkleSmall.line(to: CGPoint(x: 710, y: 670))
sparkleSmall.close()
color(255, 245, 229, 0.92).setFill()
sparkleSmall.fill()

let border = roundedRect(bounds.insetBy(dx: 60, dy: 60), radius: 216)
border.lineWidth = 2
color(255, 255, 255, 0.46).setStroke()
border.stroke()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG output.\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL, options: .atomic)
print(outputURL.path)
