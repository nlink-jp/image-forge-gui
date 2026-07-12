import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One dab of the mask brush, in **normalized** coordinates (0…1 across the init
/// image) so it is resolution-independent: the on-screen canvas and the exported
/// pixel mask share the same numbers. `radius` is a fraction of the image width.
struct MaskStamp: Equatable {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var erase: Bool
}

/// A resolution-independent inpaint mask: an ordered list of brush/erase dabs
/// plus an `inverted` flag. Rendered to a same-size grayscale PNG where **white =
/// regenerate, black = keep** (image-forge's convention). Pure and value-typed so
/// the rendering is unit-testable without any UI.
struct MaskDrawing: Equatable {
    var stamps: [MaskStamp] = []
    var inverted: Bool = false

    var isEmpty: Bool { stamps.isEmpty }

    mutating func add(_ s: MaskStamp) { stamps.append(s) }
    mutating func clear() { stamps.removeAll() }

    /// Render to a `w`×`h` 8-bit grayscale PNG (white where painted = regenerate,
    /// black elsewhere = keep; `inverted` swaps them). Dabs are replayed in order,
    /// so an erase dab paints the base color back over earlier brush dabs. Returns
    /// nil on a bad size or encode failure. Pure — no UIKit/AppKit drawing state.
    func renderPNG(width w: Int, height h: Int) -> Data? {
        guard w > 0, h > 0 else { return nil }
        let base: CGFloat = inverted ? 1 : 0  // keep
        let brush: CGFloat = inverted ? 0 : 1 // regenerate
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: base, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for s in stamps {
            ctx.setFillColor(gray: s.erase ? base : brush, alpha: 1)
            let px = s.x * CGFloat(w)
            let py = (1 - s.y) * CGFloat(h) // CG origin is bottom-left; our y is top-left
            let r = max(1, s.radius * CGFloat(w))
            ctx.fillEllipse(in: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r))
        }
        guard let cg = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// A mask-drawing overlay on the init image: paint the regions to regenerate.
/// The image is shown at a fixed width (aspect-fit) and a `Canvas` of the exact
/// same rect captures brush strokes as normalized `MaskStamp`s, so screen space
/// maps 1:1 to the image. Tools: brush / eraser, radius, clear, invert.
struct MaskCanvasView: View {
    let initURL: URL
    @Binding var drawing: MaskDrawing

    @State private var erasing = false
    /// Brush radius as a fraction of image width (0.02…0.25).
    @State private var brushFraction: CGFloat = 0.06
    /// Cursor position within the canvas (nil when the mouse is elsewhere), for the
    /// brush-size ring; and whether we've hidden the system arrow over the canvas.
    @State private var cursorLocation: CGPoint?
    @State private var cursorHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            imageWithOverlay
            legend
            Text(drawing.inverted
                 ? "Inverted: brush marks the areas to KEEP — everything else (red) is regenerated."
                 : "Brush the areas to regenerate (shown red). Everything you don't paint keeps the original.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Always-accurate colour key: red always means "will be regenerated",
    /// regardless of the Invert toggle (which only changes *which* area is red).
    private var legend: some View {
        HStack(spacing: 14) {
            Label {
                Text("regenerated")
            } icon: {
                RoundedRectangle(cornerRadius: 2).fill(.red.opacity(0.4)).frame(width: 12, height: 12)
            }
            Label {
                Text("kept (original)")
            } icon: {
                RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary).frame(width: 12, height: 12)
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    // Two compact rows so the tools fit the narrow Composer panel without overflow.
    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: $erasing) {
                    Label("Brush", systemImage: "paintbrush.pointed").tag(false)
                    Label("Erase", systemImage: "eraser").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
                Toggle("Invert", isOn: $drawing.inverted).toggleStyle(.checkbox).fixedSize()
                    .help("Swap the mask: the brush marks what to KEEP; everything else is regenerated.")
            }
            HStack(spacing: 8) {
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                Slider(value: $brushFraction, in: 0.02...0.25)
                Button("Clear") { drawing.clear() }.disabled(drawing.isEmpty).fixedSize()
            }
        }
        .controlSize(.small)
    }

    // The image fills the panel width at its own aspect ratio (no fixed size, so it
    // never overflows). A GeometryReader supplies the actual rendered size, so drag
    // points map 1:1 to normalized image coordinates.
    private var imageWithOverlay: some View {
        let aspect = Self.aspectRatio(of: initURL) ?? 1
        return Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        AsyncImage(url: initURL) { $0.resizable() }
                            placeholder: { Color.gray.opacity(0.2) }
                        MaskStrokeCanvas(drawing: drawing)
                        brushRing(in: geo.size)
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0).onChanged { v in
                                    guard geo.size.width > 0, geo.size.height > 0 else { return }
                                    cursorLocation = v.location
                                    drawing.add(MaskStamp(
                                        x: clamp(v.location.x / geo.size.width),
                                        y: clamp(v.location.y / geo.size.height),
                                        radius: brushFraction, erase: erasing))
                                })
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let p):
                                    cursorLocation = p
                                    if !cursorHidden { NSCursor.hide(); cursorHidden = true }
                                case .ended:
                                    cursorLocation = nil
                                    unhideCursor()
                                }
                            }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            .onDisappear(perform: unhideCursor) // never leave the arrow hidden
    }

    /// A ring at the cursor showing the exact brush footprint (white for erase).
    @ViewBuilder private func brushRing(in size: CGSize) -> some View {
        if let loc = cursorLocation, size.width > 0 {
            let r = brushFraction * size.width
            let color: Color = erasing ? .white : .red
            Circle()
                .fill(color.opacity(0.12))
                .overlay(Circle().strokeBorder(color.opacity(0.9), lineWidth: 1.5))
                .frame(width: 2 * r, height: 2 * r)
                .position(loc)
                .allowsHitTesting(false)
        }
    }

    private func unhideCursor() {
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }

    /// The pixel aspect ratio (w/h) of an image file, or nil if unreadable.
    static func aspectRatio(of url: URL) -> CGFloat? {
        guard let (w, h) = pixelSize(of: url), h > 0 else { return nil }
        return CGFloat(w) / CGFloat(h)
    }

    /// The pixel dimensions of an image file — the mask must be exported at exactly
    /// this size (image-forge requires the mask to match the init image).
    static func pixelSize(of url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}

/// Draws the current mask stamps as a translucent red overlay so the user sees
/// what they've painted. (The exported PNG is rendered separately, in grayscale.)
private struct MaskStrokeCanvas: View {
    let drawing: MaskDrawing

    var body: some View {
        Canvas { ctx, size in
            // Red marks what will be REGENERATED — matching the exported mask. When
            // inverted, the base is red (regenerate everywhere) and brush dabs clear
            // it (paint = keep); otherwise the base is clear and brush dabs add red.
            // Drawn into one layer, composited once at 0.4 so overlaps stay uniformly
            // translucent (you can see the image through them) instead of compounding.
            ctx.opacity = 0.4
            ctx.drawLayer { layer in
                if drawing.inverted {
                    layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red))
                }
                for s in drawing.stamps {
                    let r = s.radius * size.width
                    let rect = CGRect(x: s.x * size.width - r, y: s.y * size.height - r,
                                      width: 2 * r, height: 2 * r)
                    let regenerate = drawing.inverted ? s.erase : !s.erase
                    layer.blendMode = regenerate ? .normal : .clear
                    layer.fill(Path(ellipseIn: rect), with: .color(.red))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
