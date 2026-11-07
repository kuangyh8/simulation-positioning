import Foundation
import CoreGraphics
import ImageIO

let S: CGFloat = 1024

func makeContext() -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r/255, g/255, b/255, a])!
}

func linearGradient(_ c0: CGColor, _ c1: CGColor, from p0: CGPoint, to p1: CGPoint) -> CGGradient {
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [c0, c1] as CFArray,
                      locations: [0, 1])!
}

let ctx = makeContext()

// ---- Squircle background ----
let corner: CGFloat = 232
let bgRect = CGRect(x: 0, y: 0, width: S, height: S)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// diagonal gradient: indigo (top-left) -> cyan (bottom-right)
let topLeft = CGPoint(x: 0, y: S)
let bottomRight = CGPoint(x: S, y: 0)
let bgGrad = linearGradient(rgb(79, 70, 229), rgb(34, 211, 238), from: topLeft, to: bottomRight)
ctx.drawLinearGradient(bgGrad, start: topLeft, end: bottomRight, options: [])

// soft radial highlight (glass feel) near top-left
let hlCenter = CGPoint(x: 340, y: 740)
let hlGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [rgb(255,255,255,0.28), rgb(255,255,255,0.0)] as CFArray,
                        locations: [0, 1])!
ctx.drawRadialGradient(hlGrad, startCenter: hlCenter, startRadius: 0,
                       endCenter: hlCenter, endRadius: 640, options: [])

ctx.restoreGState()

// ---- Location pin (white teardrop, top circle + tangent tail) ----
let cx: CGFloat = 512
let cy: CGFloat = 594      // head center (CG coords, y up)
let r: CGFloat = 235
let tipY: CGFloat = 169    // pin tip

// tangent geometry (tip directly below head center)
let d = cy - tipY                       // center -> tip distance
let tY = cy + (r * r) / d               // tangent chord height
let tX = r * sqrt(d * d - r * r) / d    // half-chord width

let leftTangent = CGPoint(x: cx - tX, y: tY)
let rightTangent = CGPoint(x: cx + tX, y: tY)
let tip = CGPoint(x: cx, y: tipY)

// sample the top arc (from left tangent over the top to right tangent), clockwise
let aStart = atan2(leftTangent.y - cy, leftTangent.x - cx)   // ~213.6 deg
let aEnd   = atan2(rightTangent.y - cy, rightTangent.x - cx) // ~ -33.6 deg
let N = 140
var pts: [CGPoint] = [leftTangent]
for i in 1...N {
    let t = CGFloat(i) / CGFloat(N)
    let a = aStart + (aEnd - aStart) * t
    pts.append(CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
}
pts.append(rightTangent)
pts.append(tip)
pts.append(leftTangent)

let pinPath = CGMutablePath()
pinPath.move(to: pts[0])
for p in pts.dropFirst() { pinPath.addLine(to: p) }
pinPath.closeSubpath()

// pin drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 55, color: rgb(0, 0, 0, 0.32))
ctx.addPath(pinPath)
ctx.setFillColor(rgb(255, 255, 255))
ctx.fillPath()
ctx.restoreGState()

// pin fill: subtle white -> light gray gradient for depth
ctx.saveGState()
ctx.addPath(pinPath)
ctx.clip()
let pinGrad = linearGradient(rgb(255, 255, 255), rgb(228, 236, 246),
                             from: CGPoint(x: cx, y: cy + r), to: CGPoint(x: cx, y: tipY))
ctx.drawLinearGradient(pinGrad, start: CGPoint(x: cx, y: cy + r), end: CGPoint(x: cx, y: tipY), options: [])
ctx.restoreGState()

// ---- Center "location" dot + ring ----
// colored dot (reveals background gradient)
let dotCenter = CGPoint(x: cx, y: cy)
let dotR: CGFloat = 108
let dotRect = CGRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2)
ctx.saveGState()
ctx.addEllipse(in: dotRect)
ctx.clip()
let dotGrad = linearGradient(rgb(79, 70, 229), rgb(6, 182, 212),
                             from: CGPoint(x: dotRect.minX, y: dotRect.maxY),
                             to: CGPoint(x: dotRect.maxX, y: dotRect.minY))
ctx.drawLinearGradient(dotGrad, start: CGPoint(x: dotRect.minX, y: dotRect.maxY),
                       end: CGPoint(x: dotRect.maxX, y: dotRect.minY), options: [])
ctx.restoreGState()

// thin white ring around the dot
let ringR: CGFloat = 140
let ringRect = CGRect(x: dotCenter.x - ringR, y: dotCenter.y - ringR, width: ringR * 2, height: ringR * 2)
ctx.saveGState()
ctx.setStrokeColor(rgb(255, 255, 255))
ctx.setLineWidth(12)
ctx.strokeEllipse(in: ringRect)
ctx.restoreGState()

// write PNG
let cg = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png") as CFURL
let dest = CGImageDestinationCreateWithURL(out, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
