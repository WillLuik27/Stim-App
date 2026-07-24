import SwiftUI

/// The grey orb itself: a shaded sphere that squashes into its direction of
/// travel and is lit from a direction pinned to the real world.
struct OrbView: View {

    @ObservedObject var controller: OrbController

    private let diameter = OrbController.orbDiameter

    /// How far off-centre the shading gradient's hot spot sits, as a fraction of
    /// the sphere. Too much and the sphere reads as a flat disc with a smudge.
    private let shadingThrow: CGFloat = 0.17
    /// Distance of the specular highlight from centre, as a fraction of diameter.
    private let highlightThrow: CGFloat = 0.29

    var body: some View {
        ZStack {
            sphere
            highlight
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(controller.isDragging ? 0.97 : 1.0)
        .modifier(StretchEffect(offset: controller.offset, amount: stretchAmount))
        .offset(controller.offset)
        // Cast shadow falls away from the light; the glow spills toward it.
        .shadow(color: .black.opacity(0.55),
                radius: 26,
                x: -light.dx * 14,
                y: -light.dy * 14 + 8)
        .shadow(color: .white.opacity(0.10 + controller.speed * 0.22),
                radius: 34 + controller.speed * 26,
                x: light.dx * 10,
                y: light.dy * 10)
        .animation(.easeOut(duration: 0.18), value: controller.isDragging)
        // Long enough to smooth the remaining sensor jitter, short enough that
        // the light still feels attached to the room rather than trailing you.
        .animation(.easeOut(duration: 0.12), value: controller.light)
    }

    private var light: CGVector { controller.light }

    /// How far the orb deforms — grows with both pull and speed, but stays subtle
    /// enough that it reads as a sphere flexing rather than turning into an oval.
    private var stretchAmount: CGFloat {
        min(controller.pull * 0.035 + controller.speed * 0.030, 0.055)
    }

    private var sphere: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(white: 0.62),
                        Color(white: 0.44),
                        Color(white: 0.26),
                        Color(white: 0.15)
                    ],
                    center: UnitPoint(x: 0.5 + light.dx * shadingThrow,
                                      y: 0.5 + light.dy * shadingThrow),
                    startRadius: 4,
                    endRadius: diameter * 0.92
                )
            )
            .overlay(
                // Rim light: bright where the light strikes, dim on the far side,
                // with a faint bounce coming back off the opposite edge.
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.34),
                            .white.opacity(0.04),
                            .white.opacity(0.16)
                        ],
                        startPoint: unitPoint(towards: light),
                        endPoint: unitPoint(towards: CGVector(dx: -light.dx, dy: -light.dy))
                    ),
                    lineWidth: 1.2
                )
            )
    }

    private var highlight: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.42), .white.opacity(0.0)],
                    startPoint: unitPoint(towards: light),
                    endPoint: unitPoint(towards: CGVector(dx: -light.dx, dy: -light.dy))
                )
            )
            .frame(width: diameter * 0.46, height: diameter * 0.30)
            .blur(radius: 10)
            // The highlight rotates with the light so its long axis always lies
            // across the direction the light arrives from.
            .rotationEffect(.radians(atan2(light.dy, light.dx) + .pi / 2))
            .offset(x: light.dx * diameter * highlightThrow,
                    y: light.dy * diameter * highlightThrow)
            .blendMode(.plusLighter)
    }

    /// Converts a direction vector into the `UnitPoint` on the unit square that
    /// a gradient should start from.
    private func unitPoint(towards vector: CGVector) -> UnitPoint {
        UnitPoint(x: 0.5 + vector.dx * 0.5, y: 0.5 + vector.dy * 0.5)
    }
}

/// Squashes the orb along its direction of travel, like a soft body under load.
private struct StretchEffect: ViewModifier {
    let offset: CGSize
    let amount: CGFloat

    func body(content: Content) -> some View {
        let angle = Angle(radians: atan2(Double(offset.height), Double(offset.width)))
        return content
            .rotationEffect(-angle)
            .scaleEffect(x: 1 + amount, y: 1 - amount * 0.75)
            .rotationEffect(angle)
    }
}
