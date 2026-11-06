import CoreGraphics

/// The Ansomnia mark as pure geometry: a crescent moon, and a slash through
/// it that says "no sleep". The menu bar draws the crescent alone while the
/// Mac sleeps as usual and draws the slash in while a session holds sleep
/// off; the app icon is the slashed moon.
///
/// Everything is laid out on a 24-unit grid and scaled into whatever rect it
/// is asked for, so the same numbers draw the 17-point status item and the
/// 1024-pixel app icon: scripts/generate-app-icon.sh compiles this file
/// straight into the icon generator. CoreGraphics only, no SwiftUI or
/// AppKit, so the file builds standalone. Coordinates are y-down.
enum MoonMarkGeometry {
    static let designSize: CGFloat = 24
    /// Line weight in grid units: 1.5 of 24, the menu bar's line weight.
    static let strokeUnits: CGFloat = 1.5
    /// The clear band either side of the slash where it crosses the
    /// crescent, in grid units, so the two lines read apart at 16 pixels.
    static let gapUnits: CGFloat = 1.25

    /// The moon's disc, and the disc that bites the crescent out of it,
    /// offset up and to the right so the lit side faces down and left.
    static let moonCenter = CGPoint(x: 12, y: 12)
    static let moonRadius: CGFloat = 8.5
    static let biteCenter = CGPoint(x: 16.2, y: 7.8)
    static let biteRadius: CGFloat = 7

    /// The slash, corner to corner along the bite's axis, bottom left to top
    /// right: it crosses the crescent's body once and runs on through the bite.
    static let slashStart = CGPoint(x: 3.5, y: 20.5)
    static let slashEnd = CGPoint(x: 20.5, y: 3.5)

    /// Maps the design grid onto `rect`: uniformly scaled, centred.
    static func gridTransform(in rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / designSize
        let side = designSize * scale
        return CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
    }

    /// Stroke weight for a mark drawn into a square of `size`.
    static func lineWidth(for size: CGFloat) -> CGFloat {
        strokeUnits * size / designSize
    }

    /// Width of the clear band cut under the slash, for a square of `size`.
    static func gapWidth(for size: CGFloat) -> CGFloat {
        (strokeUnits + 2 * gapUnits) * size / designSize
    }

    /// The two points where the bite's circle crosses the moon's, on the
    /// grid: the crescent's horns.
    static var horns: (CGPoint, CGPoint) {
        let dx = biteCenter.x - moonCenter.x, dy = biteCenter.y - moonCenter.y
        let d = (dx * dx + dy * dy).squareRoot()
        let a = (moonRadius * moonRadius - biteRadius * biteRadius + d * d) / (2 * d)
        let h = (moonRadius * moonRadius - a * a).squareRoot()
        let ux = dx / d, uy = dy / d
        let base = CGPoint(x: moonCenter.x + a * ux, y: moonCenter.y + a * uy)
        return (CGPoint(x: base.x - h * uy, y: base.y + h * ux), CGPoint(x: base.x + h * uy, y: base.y - h * ux))
    }

    /// The crescent's closed outline, meant to be stroked: the moon's rim
    /// from horn to horn the long way round, then the bite's edge back.
    static func crescent(in rect: CGRect) -> CGPath {
        let t = gridTransform(in: rect)
        let (p, q) = horns
        // Both arcs bow away from the bite, towards the moon's far side.
        let away = atan2(moonCenter.y - biteCenter.y, moonCenter.x - biteCenter.x)
        let path = CGMutablePath()
        path.move(to: p, transform: t)
        addArc(to: path, center: moonCenter, radius: moonRadius, from: p, to: q, through: away, transform: t)
        addArc(to: path, center: biteCenter, radius: biteRadius, from: q, to: p, through: away, transform: t)
        path.closeSubpath()
        return path
    }

    /// The slash as one open line, meant to be stroked with round caps.
    static func slash(in rect: CGRect) -> CGPath {
        let t = gridTransform(in: rect)
        let path = CGMutablePath()
        path.move(to: slashStart, transform: t)
        path.addLine(to: slashEnd, transform: t)
        return path
    }

    /// Adds the arc of the circle from `a` to `b` that passes the direction
    /// `through` (radians, as seen from the centre).
    private static func addArc(
        to path: CGMutablePath, center: CGPoint, radius: CGFloat,
        from a: CGPoint, to b: CGPoint, through: CGFloat, transform: CGAffineTransform
    ) {
        let start = atan2(a.y - center.y, a.x - center.x)
        let end = atan2(b.y - center.y, b.x - center.x)
        // Increasing angles from start: does `through` come before `end`?
        func ahead(_ angle: CGFloat) -> CGFloat {
            let turn = 2 * CGFloat.pi
            let x = (angle - start).truncatingRemainder(dividingBy: turn)
            return x < 0 ? x + turn : x
        }
        let increasing = ahead(through) < ahead(end)
        // With a y-down grid and no flip, `clockwise: false` runs the angle up.
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: !increasing, transform: transform)
    }
}
