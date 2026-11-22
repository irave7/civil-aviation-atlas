import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let resolution = 1024
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: resolution, height: resolution, bitsPerComponent: 8,
                        bytesPerRow: 0, space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func line(_ start: CGPoint, _ end: CGPoint, width: CGFloat, shade: CGColor) {
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setStrokeColor(shade)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
}
func oval(_ rect: CGRect, width: CGFloat, shade: CGColor) {
    context.setStrokeColor(shade)
    context.setLineWidth(width)
    context.strokeEllipse(in: rect)
}
let frame = CGRect(x: 0, y: 0, width: resolution, height: resolution)
let background = CGGradient(colorsSpace: rgb, colors: [color(0.11, 0.26, 0.35), color(0.023, 0.058, 0.10)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(background, startCenter: CGPoint(x: 266, y: 844), startRadius: 75,
                           endCenter: CGPoint(x: 551, y: 491), endRadius: 735, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let center = CGPoint(x: 512, y: 520)
let sphere = CGRect(x: 240, y: 248, width: 544, height: 544)
context.saveGState()
context.addEllipse(in: sphere)
context.clip()
let globe = CGGradient(colorsSpace: rgb, colors: [color(0.19,0.44,0.47), color(0.036,0.14,0.22)] as CFArray, locations: [0,1])!
context.drawRadialGradient(globe, startCenter: CGPoint(x: 382, y: 726), startRadius: 18,
                           endCenter: center, endRadius: 359, options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
let meridianShade = color(0.56, 0.94, 0.85, 0.55)
for width in [CGFloat(202), 365] {
    oval(CGRect(x: center.x - width / 2, y: 248, width: width, height: 544), width: 3, shade: meridianShade)
}
for height in [CGFloat(155), 333, 454] {
    oval(CGRect(x: 240, y: center.y - height / 2, width: 544, height: height), width: 3, shade: meridianShade)
}
context.restoreGState()
oval(sphere, width: 7, shade: color(0.46, 0.92, 0.86, 0.90))
context.saveGState()
context.translateBy(x: 512, y: 520)
context.rotate(by: .pi / 5)
let runway = CGPath(roundedRect: CGRect(x: -299, y: -39, width: 598, height: 78), cornerWidth: 26, cornerHeight: 26, transform: nil)
context.addPath(runway)
context.setShadow(offset: CGSize(width: 0, height: -7), blur: 21, color: color(0,0,0,0.64))
context.setFillColor(color(0.027,0.106,0.15))
context.fillPath()
context.setShadow(offset: .zero, blur: 0)
context.addPath(runway)
context.setStrokeColor(color(0.57,0.98,0.86))
context.setLineWidth(5)
context.strokePath()
for offset in stride(from: -196, through: 181, by: 63) {
    line(CGPoint(x: offset, y: 0), CGPoint(x: offset + 27, y: 0), width: 5, shade: color(0.78,1,0.94))
}
for edge in [-253, 253] {
    for shift in [-14, 0, 14] {
        line(CGPoint(x: edge - 11, y: shift), CGPoint(x: edge + 11, y: shift), width: 3.5, shade: color(0.78,1,0.94))
    }
}
context.restoreGState()
for point in [CGPoint(x: 723, y: 687), CGPoint(x: 298, y: 350)] {
    context.setFillColor(color(0.84, 1, 0.92))
    context.fillEllipse(in: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
