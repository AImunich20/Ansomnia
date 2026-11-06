import SwiftUI

/// The × that sits to the right of the countdown in the status item. One
/// click ends the session.
///
/// The click is not a SwiftUI gesture: inside a status item a gesture can
/// lose the click to the status bar button, which left the × showing its
/// press and doing nothing, or passed the click on to the mark beside it.
/// `StatusItemController` takes any click inside `frameReported` in a local
/// event monitor, before the rest of the app sees it, and tracks it to
/// mouse-up (`EndClickTracker`). This view only draws the hover and the
/// press it is told about, and reports where it is and whether the pointer
/// is over it.
struct EndSessionButton: View {
    let reduceMotion: Bool
    let pressed: Bool
    let action: () -> Void
    /// Where the × is, in `StatusRootView.coordinateSpace`; nil once it has gone.
    let frameReported: (CGRect?) -> Void
    /// Whether the pointer is over the ×. The menu bar hands the app a
    /// click on the status item at the item's centre, so the controller
    /// trusts this, not the click's location.
    let hoverReported: (Bool) -> Void

    @State private var hovering = false

    private let diameter: CGFloat = 18
    private let lineWidth: CGFloat = 1.6

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(pressed ? 0.22 : (hovering ? 0.14 : 0)))
            Circle()
                .stroke(Color.white.opacity(hovering || pressed ? 0.3 : 0.14), lineWidth: lineWidth)
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pressed && !reduceMotion ? 0.9 : 1)
        .animation(Motion.snappy(reduceMotion: reduceMotion), value: pressed)
        .animation(Motion.snappy(reduceMotion: reduceMotion), value: hovering)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
        .onHover { hovering = $0; hoverReported($0) }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(StatusRootView.coordinateSpace))
        } action: { frame in
            frameReported(frame)
        }
        .onDisappear { frameReported(nil); hoverReported(false) }
        .help("End the session")
        .accessibilityLabel("End session")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
