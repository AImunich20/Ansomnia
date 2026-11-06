import SwiftUI

/// The crescent's outline, for stroking.
struct MoonCrescent: Shape {
    func path(in rect: CGRect) -> Path {
        Path(MoonMarkGeometry.crescent(in: rect))
    }
}

/// The slash, for stroking.
struct MoonSlash: Shape {
    func path(in rect: CGRect) -> Path {
        Path(MoonMarkGeometry.slash(in: rect))
    }
}

/// The mark as it appears in the status item: a crescent moon while the Mac
/// sleeps as usual, and the same moon slashed through while a session holds
/// sleep off. The slash draws itself in from its lower end as a session
/// starts and wipes back out as it ends, cutting its own gap in the crescent
/// as it goes; under Reduce Motion it fades in and out whole instead.
/// Everything is drawn in `.primary`, so the mark follows the light or dark
/// menu bar and never takes a tint.
struct MoonMarkView: View {
    /// 0 the plain crescent, 1 slashed.
    let progress: CGFloat
    let reduceMotion: Bool
    var size: CGFloat = 17

    /// What the slash's animation is keyed on. Keying on both means a
    /// Reduce Motion change mid-stroke is itself a value change, so it
    /// crossfades from the current presentation instead of jumping.
    struct SlashState: Equatable {
        var progress: CGFloat
        var reduceMotion: Bool
    }

    init(isRunning: Bool, reduceMotion: Bool, size: CGFloat = 17) {
        self.init(progress: isRunning ? 1 : 0, reduceMotion: reduceMotion, size: size)
    }

    /// One frozen frame of the slash, for previews and tests.
    init(progress: CGFloat, reduceMotion: Bool = true, size: CGFloat = 17) {
        self.progress = progress
        self.reduceMotion = reduceMotion
        self.size = size
    }

    static func stroke(size: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: MoonMarkGeometry.lineWidth(for: size), lineCap: .round, lineJoin: .round)
    }

    static func gap(size: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: MoonMarkGeometry.gapWidth(for: size), lineCap: .round)
    }

    private var state: SlashState { SlashState(progress: progress, reduceMotion: reduceMotion) }
    private var clamped: CGFloat { min(max(progress, 0), 1) }
    /// How much of the slash is drawn: all of it under Reduce Motion, where
    /// it fades instead.
    var slashLength: CGFloat { reduceMotion ? 1 : clamped }
    /// The slash's opacity: it only fades under Reduce Motion.
    var slashOpacity: CGFloat { reduceMotion ? clamped : (clamped > 0 ? 1 : 0) }

    var body: some View {
        // The layers are drawn opaque and used as a mask over a single
        // `.primary` fill: the label colour is translucent, and this keeps
        // the crescent and the slash from doubling up where they cross.
        Rectangle()
            .fill(.primary)
            .mask { layers }
            .frame(width: size, height: size)
            .animation(Motion.blink(opening: progress > 0.5, reduceMotion: reduceMotion), value: state)
    }

    private var layers: some View {
        ZStack {
            MoonCrescent()
                .stroke(.black, style: Self.stroke(size: size))
            Group {
                MoonSlash()
                    .trim(from: 0, to: slashLength)
                    .stroke(.black, style: Self.gap(size: size))
                    .blendMode(.destinationOut)
                MoonSlash()
                    .trim(from: 0, to: slashLength)
                    .stroke(.black, style: Self.stroke(size: size))
            }
            .opacity(slashOpacity)
        }
        .compositingGroup()
    }
}
