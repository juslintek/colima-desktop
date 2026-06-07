#!/usr/bin/env bash
#
# Generate the Colima Desktop app icon: an isometric cube on a teal->blue squircle.
# Original artwork (no third-party marks). Produces:
#   packaging/AppIcon.icns                         (standalone, for DMG volume icon)
#   Sources/Assets.xcassets/AppIcon.appiconset/    (wired into the app via project.yml)
#
# Headless CoreGraphics rendering — no window server needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SWIFT="$WORK/gen.swift"
ICONSET="$WORK/AppIcon.iconset"
APPICONSET="$ROOT/Sources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET" "$APPICONSET"

cat > "$SWIFT" <<'SWIFT'
import CoreGraphics
import ImageIO
import Foundation

func render(_ size: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let S = CGFloat(size)

    // Rounded-rect "body" with macOS-style margin + corner radius.
    let margin = S * 0.092
    let body = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
    let radius = body.width * 0.2237
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Gradient fill (teal -> blue).
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let colors = [CGColor(red: 0.13, green: 0.70, blue: 0.78, alpha: 1),
                  CGColor(red: 0.03, green: 0.34, blue: 0.70, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Soft top highlight.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fill(CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height/2))
    ctx.restoreGState()

    // Isometric cube, centered.
    let cx = S/2, cy = S/2
    let a = S * 0.205          // horizontal half-width of the top diamond
    let b = a * 0.5            // iso vertical squash
    let h = S * 0.23           // side-face height
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    let tTop = P(cx, cy + h/2 + b)
    let tRight = P(cx + a, cy + h/2)
    let tBot = P(cx, cy + h/2 - b)
    let tLeft = P(cx - a, cy + h/2)
    let bRight = P(cx + a, cy - h/2)
    let bBot = P(cx, cy - h/2 - b)
    let bLeft = P(cx - a, cy - h/2)
    func face(_ pts: [CGPoint], _ alpha: CGFloat) {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.beginPath(); ctx.move(to: pts[0])
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.closePath(); ctx.fillPath()
    }
    face([tTop, tRight, tBot, tLeft], 1.00)        // top
    face([tLeft, tBot, bBot, bLeft], 0.62)         // left
    face([tRight, tBot, bBot, bRight], 0.80)       // right

    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    _ = CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments[1]
for n in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(render(n), "\(outDir)/png_\(n).png")
}
SWIFT

echo "==> Rendering PNGs"
xcrun swift "$SWIFT" "$WORK"

echo "==> Building .iconset + .icns"
cp "$WORK/png_16.png"   "$ICONSET/icon_16x16.png"
cp "$WORK/png_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$WORK/png_32.png"   "$ICONSET/icon_32x32.png"
cp "$WORK/png_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$WORK/png_128.png"  "$ICONSET/icon_128x128.png"
cp "$WORK/png_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$WORK/png_256.png"  "$ICONSET/icon_256x256.png"
cp "$WORK/png_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$WORK/png_512.png"  "$ICONSET/icon_512x512.png"
cp "$WORK/png_1024.png" "$ICONSET/icon_512x512@2x.png"
mkdir -p "$ROOT/packaging"
iconutil -c icns "$ICONSET" -o "$ROOT/packaging/AppIcon.icns"

echo "==> Populating asset catalog: $APPICONSET"
for n in 16 32 64 128 256 512 1024; do cp "$WORK/png_$n.png" "$APPICONSET/icon_$n.png"; done
cat > "$APPICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16.png" },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_64.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

rm -rf "$WORK"
echo "==> Done: packaging/AppIcon.icns + Sources/Assets.xcassets/AppIcon.appiconset"
