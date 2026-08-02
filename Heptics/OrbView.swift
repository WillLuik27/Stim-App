import SwiftUI

/// Draws the goo.
///
/// Everything lands in one `Canvas`, in four passes:
///
///  1. a soft glow spilling out underneath, so the goo sits in its own light;
///  2. a cast shadow thrown away from the light;
///  3. **the metaball pass** — every blob and every neck circle is drawn white
///     into an offscreen layer, that layer is blurred, and the blur is cut at a
///     hard alpha threshold. Blurring merges anything close together into one
///     continuous mass and rounds every junction, and the threshold turns the
///     soft result back into a crisp edge. That is what makes two circles a few
///     points apart read as one lump of goo rather than as two circles;
///  4. the shading, drawn *clipped to* that silhouette, so the sphere lighting
///     flows across the bridges instead of stopping at each body's own edge.
struct OrbView: View {

    @ObservedObject var controller: OrbController

    /// How far the blur reaches when merging bodies. This is the only number that
    /// decides how gooey the field looks: too little and blobs stay separate
    /// circles, too much and thin necks are swallowed before they can snap.
    private let mergeBlur: CGFloat = 13
    /// Takes the hard edge off after the threshold has cut it, since a threshold
    /// throws away all the antialiasing.
    private let edgeSoftness: CGFloat = 0.9

    /// The tone the goo falls to where nothing is lighting it — the necks and the
    /// far side of every body.
    private let baseTone = Color(white: 0.145)

    var body: some View {
        Canvas { context, size in
            let time = controller.clock
            let blobs = controller.blobs
            let necks = controller.necks
            let light = controller.light

            let bodies = blobs.map { $0.outline(at: time) }
            let bridges = necks.map { Path(ellipseIn: rect(around: $0.center, radius: $0.radius)) }
            let field = bodies + bridges

            drawGlow(in: context, blobs: blobs)
            drawShadow(in: context, field: field, light: light)

            // Everything from here on is confined to the goo's silhouette.
            context.clipToLayer { mask in
                mask.addFilter(.blur(radius: edgeSoftness))
                mask.addFilter(.alphaThreshold(min: 0.5, color: .white))
                mask.addFilter(.blur(radius: mergeBlur))
                mask.drawLayer { shapes in
                    for path in field { shapes.fill(path, with: .color(.white)) }
                }
            }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(baseTone))
            for neck in necks { shadeNeck(neck, in: context, light: light) }
            for blob in blobs { shadeBody(blob, in: context, light: light) }
            for blob in blobs { drawHighlight(blob, in: context, light: light) }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Passes

    /// A whisper of light thrown onto the background. Grows as the goo is worked,
    /// which is most of what tells you the field is alive while you drag.
    ///
    /// Drawn as a gradient rather than as a blurred disc: a 44-point blur of a
    /// hard edge lands on so few levels of grey at this opacity that it bands into
    /// visible rings.
    private func drawGlow(in context: GraphicsContext, blobs: [Blob]) {
        let strength = 0.16 + Double(controller.speed) * 0.26 + Double(controller.pull) * 0.12
        for blob in blobs {
            let reach = blob.radius * 2.4
            context.fill(
                Path(ellipseIn: rect(around: blob.position, radius: reach)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(white: 0.62).opacity(strength), location: 0.00),
                        .init(color: Color(white: 0.55).opacity(strength * 0.45), location: 0.42),
                        .init(color: Color(white: 0.50).opacity(0), location: 1.00)
                    ]),
                    center: blob.position,
                    startRadius: blob.radius * 0.5,
                    endRadius: reach
                )
            )
        }
    }

    private func drawShadow(in context: GraphicsContext, field: [Path], light: CGVector) {
        context.drawLayer { shadow in
            shadow.addFilter(.blur(radius: 24))
            shadow.opacity = 0.55
            shadow.translateBy(x: -light.dx * 15, y: -light.dy * 15 + 9)
            for path in field { shadow.fill(path, with: .color(.black)) }
        }
    }

    /// A sphere's worth of shading for one body: a radial gradient whose hot spot
    /// sits off-centre toward the light and which falls away to nothing before it
    /// reaches the far edge, leaving the base tone showing as the terminator.
    private func shadeBody(_ blob: Blob, in context: GraphicsContext, light: CGVector) {
        let shown = Double(blob.emergence)
        guard shown > 0.01 else { return }

        let centre = CGPoint(x: blob.position.x + light.dx * blob.radius * 0.34,
                             y: blob.position.y + light.dy * blob.radius * 0.34)
        context.fill(
            Path(ellipseIn: rect(around: blob.position, radius: blob.radius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(white: 0.70).opacity(shown), location: 0.00),
                    .init(color: Color(white: 0.52).opacity(shown), location: 0.34),
                    .init(color: Color(white: 0.30).opacity(shown), location: 0.66),
                    .init(color: Color(white: 0.18).opacity(0), location: 1.00)
                ]),
                center: centre,
                startRadius: blob.radius * 0.04,
                endRadius: blob.radius * 1.32
            )
        )
    }

    /// Necks get a thin cylinder's worth of shading rather than a sphere's, so a
    /// stretched thread reads as a tube of goo and not as a row of beads.
    private func shadeNeck(_ neck: Neck, in context: GraphicsContext, light: CGVector) {
        let centre = CGPoint(x: neck.center.x + light.dx * neck.radius * 0.42,
                             y: neck.center.y + light.dy * neck.radius * 0.42)
        context.fill(
            Path(ellipseIn: rect(around: neck.center, radius: neck.radius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(white: 0.46), location: 0.00),
                    .init(color: Color(white: 0.26), location: 0.55),
                    .init(color: Color(white: 0.16).opacity(0), location: 1.00)
                ]),
                center: centre,
                startRadius: 1,
                endRadius: neck.radius * 1.25
            )
        )
    }

    /// The specular. Its long axis lies across the direction the light arrives
    /// from, so it turns with the light rather than sliding around the body.
    private func drawHighlight(_ blob: Blob, in context: GraphicsContext, light: CGVector) {
        let shown = Double(blob.emergence)
        guard blob.radius > 6, shown > 0.01 else { return }
        context.drawLayer { spec in
            spec.blendMode = .plusLighter
            spec.translateBy(x: blob.position.x + light.dx * blob.radius * 0.52,
                             y: blob.position.y + light.dy * blob.radius * 0.52)
            spec.rotate(by: .radians(atan2(light.dy, light.dx) + .pi / 2))
            spec.addFilter(.blur(radius: blob.radius * 0.14))

            let width = blob.radius * 0.56, height = blob.radius * 0.34
            spec.fill(
                Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2,
                                       width: width, height: height)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.44 * shown), .white.opacity(0)]),
                    center: .zero,
                    startRadius: 0,
                    endRadius: width / 2
                )
            )
        }
    }

    private func rect(around point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }
}
