import AppKit
import CoreText
import Foundation

guard CommandLine.arguments.count == 5 else {
  fatalError("Usage: make-icon.swift <mascot.png> <Resources> <output.iconset> <brand-assets>")
}
let resources = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let iconset = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let brandAssets = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)
for directory in [resources, iconset, brandAssets] {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

let forest = NSColor(srgbRed: 18 / 255, green: 59 / 255, blue: 44 / 255, alpha: 1)
let leaf = NSColor(srgbRed: 174 / 255, green: 217 / 255, blue: 120 / 255, alpha: 1)
let eyes = NSColor(srgbRed: 16 / 255, green: 61 / 255, blue: 45 / 255, alpha: 1)

// One fixed silhouette, in a top-down 1,000-unit canvas, for every icon and expression.
let silhouette = CGMutablePath()
silhouette.move(to: CGPoint(x: 580, y: 45))
silhouette.addCurve(to: CGPoint(x: 620, y: 161), control1: CGPoint(x: 690, y: 24), control2: CGPoint(x: 665, y: 95))
silhouette.addCurve(to: CGPoint(x: 703, y: 294), control1: CGPoint(x: 573, y: 231), control2: CGPoint(x: 601, y: 278))
silhouette.addCurve(to: CGPoint(x: 966, y: 596), control1: CGPoint(x: 879, y: 320), control2: CGPoint(x: 964, y: 447))
silhouette.addCurve(to: CGPoint(x: 565, y: 961), control1: CGPoint(x: 969, y: 821), control2: CGPoint(x: 799, y: 955))
silhouette.addCurve(to: CGPoint(x: 77, y: 600), control1: CGPoint(x: 298, y: 969), control2: CGPoint(x: 105, y: 811))
silhouette.addCurve(to: CGPoint(x: 480, y: 59), control1: CGPoint(x: 44, y: 352), control2: CGPoint(x: 254, y: 105))
silhouette.addCurve(to: CGPoint(x: 580, y: 45), control1: CGPoint(x: 517, y: 51), control2: CGPoint(x: 551, y: 46))
silhouette.closeSubpath()

func eyePath(_ expression: String) -> CGPath {
  let path = CGMutablePath()
  let offset: CGFloat = expression == "Turn" ? 30 : 0
  let radiusY: CGFloat = expression == "Blink" ? 10 : 51
  for center in [CGPoint(x: 527 + offset, y: 570), CGPoint(x: 698 + offset, y: 543)] {
    let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -.pi / 18)
    let eye = CGPath(ellipseIn: CGRect(x: -32, y: -radiusY, width: 64, height: radiusY * 2), transform: nil)
    path.addPath(eye, transform: transform)
  }
  return path
}

func drawSpirit(in bounds: CGRect, expression: String = "", outlined: Bool = false) {
  let context = NSGraphicsContext.current!.cgContext
  context.saveGState()
  context.translateBy(x: bounds.minX, y: bounds.maxY)
  context.scaleBy(x: bounds.width / 1_000, y: -bounds.height / 1_000)
  context.addPath(silhouette)
  context.setFillColor(leaf.cgColor)
  context.fillPath()
  if outlined {
    context.addPath(silhouette)
    context.setStrokeColor(forest.cgColor)
    context.setLineWidth(40) // 0.68pt at the menu bar's 18pt display size.
    context.setLineJoin(.round)
    context.strokePath()
  }
  context.addPath(eyePath(expression))
  context.setFillColor(eyes.cgColor)
  context.fillPath()
  context.restoreGState()
}

func writePNG(width: Int, height: Int, to file: URL, draw: (NSRect) -> Void) throws {
  guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot render brand artwork") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  context.cgContext.setShouldAntialias(true)
  let bounds = NSRect(x: 0, y: 0, width: width, height: height)
  context.cgContext.clear(bounds)
  draw(bounds)
  NSGraphicsContext.restoreGraphicsState()
  guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode brand artwork") }
  try data.write(to: file, options: .atomic)
}

func svgPath(_ path: CGPath) -> String {
  var commands: [String] = []
  func point(_ point: CGPoint) -> String { "\(point.x) \(point.y)" }
  path.applyWithBlock { pointer in
    let element = pointer.pointee
    let p = element.points
    switch element.type {
    case .moveToPoint: commands.append("M \(point(p[0]))")
    case .addLineToPoint: commands.append("L \(point(p[0]))")
    case .addQuadCurveToPoint: commands.append("Q \(point(p[0])) \(point(p[1]))")
    case .addCurveToPoint: commands.append("C \(point(p[0])) \(point(p[1])) \(point(p[2]))")
    case .closeSubpath: commands.append("Z")
    @unknown default: break
    }
  }
  return commands.joined(separator: " ")
}

for expression in ["", "Blink", "Turn"] {
  try writePNG(width: 512, height: 512, to: resources.appendingPathComponent("TessAvatar\(expression).png")) {
    drawSpirit(in: $0.insetBy(dx: 12, dy: 12), expression: expression)
  }
  try writePNG(width: 36, height: 36, to: resources.appendingPathComponent("TessMenuBar\(expression).png")) {
    drawSpirit(in: $0.insetBy(dx: 1, dy: 1), expression: expression, outlined: true)
  }
  let suffix = expression.isEmpty ? "" : "-\(expression.lowercased())"
  let svg = """
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
    <path fill="#AED978" d="\(svgPath(silhouette))"/>
    <path fill="#103D2D" d="\(svgPath(eyePath(expression)))"/>
  </svg>
  """
  try svg.write(to: brandAssets.appendingPathComponent("tess-mark\(suffix).svg"), atomically: true, encoding: .utf8)
}
try writePNG(width: 1024, height: 1024, to: brandAssets.appendingPathComponent("tess-mark.png")) {
  drawSpirit(in: $0)
}

guard let mascot = NSImage(contentsOfFile: CommandLine.arguments[1]) else { fatalError("Cannot load Tess mascot") }
try writePNG(width: 512, height: 512, to: resources.appendingPathComponent("TessMascot.png")) { bounds in
  let scale = min(bounds.width / mascot.size.width, bounds.height / mascot.size.height)
  let size = NSSize(width: mascot.size.width * scale, height: mascot.size.height * scale)
  mascot.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                        width: size.width, height: size.height))
}

for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try writePNG(width: pixels, height: pixels, to: iconset.appendingPathComponent(name)) { bounds in
      let edge = CGFloat(pixels)
      forest.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: edge * 0.06, dy: edge * 0.06),
                   xRadius: edge * 0.19, yRadius: edge * 0.19).fill()
      drawSpirit(in: bounds.insetBy(dx: edge * 0.15, dy: edge * 0.15))
    }
  }
}

let fontURL = resources.appendingPathComponent("SourceSans3-Semibold.otf")
guard let provider = CGDataProvider(url: fontURL as CFURL), let graphicsFont = CGFont(provider) else {
  fatalError("Cannot load bundled Source Sans 3 font")
}
let font = CTFontCreateWithGraphicsFont(graphicsFont, 256, nil, nil)
let text = NSAttributedString(string: "tess", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
let line = CTLineCreateWithAttributedString(text)
let outline = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
  let count = CTRunGetGlyphCount(run)
  var glyphs = [CGGlyph](repeating: 0, count: count)
  var positions = [CGPoint](repeating: .zero, count: count)
  CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
  CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
  for index in 0..<count {
    if let path = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
      outline.addPath(path, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
    }
  }
}
let textBounds = outline.boundingBoxOfPath
var textTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 16 - textBounds.minX, ty: 16 + textBounds.maxY)
let wordmark = outline.copy(using: &textTransform)!
let wordmarkWidth = Int(ceil(textBounds.width)) + 32
let wordmarkHeight = Int(ceil(textBounds.height)) + 32
let wordmarkSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(wordmarkWidth) \(wordmarkHeight)">
  <path fill="#123B2C" d="\(svgPath(wordmark))"/>
</svg>
"""
try wordmarkSVG.write(to: brandAssets.appendingPathComponent("tess-wordmark.svg"), atomically: true, encoding: .utf8)
try writePNG(width: wordmarkWidth, height: wordmarkHeight, to: brandAssets.appendingPathComponent("tess-wordmark.png")) { bounds in
  let context = NSGraphicsContext.current!.cgContext
  context.translateBy(x: 0, y: bounds.height)
  context.scaleBy(x: 1, y: -1)
  context.addPath(wordmark)
  context.setFillColor(forest.cgColor)
  context.fillPath()
}
print("Generated Tess spirit icons, fixed-silhouette expressions, mascot and \(CTFontCopyPostScriptName(font)) wordmark.")
