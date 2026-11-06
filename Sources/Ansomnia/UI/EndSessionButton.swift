import SwiftUI

/// The × that sits to the right of the countdown in the status item. One
/// click ends the session.
///
/// The click fires on mouse-up inside the button, the way an AppKit button
/// does: pressing and dragging away before releasing cancels it, so a drag
/// that happens to start on the × does not end the session.
struct EndSessionButton: View {
    let reduceMotion: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    private let diameter: CGFloat = 18
    private let lineWidth: CGFloat = 1.6
    /// Releasing farther than this from where the press began cancels it.
    private let cancelDistance: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(pressed ? 0.22 : (hovering ? 0.14 : 0)))
            Circle()
                .stroke(Color.white.opacity(hovering ? 0.3 : 0.14), lineWidth: lineWidth)
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
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pressed = hypot(value.translation.width, value.translation.height) <= cancelDistance
                }
                .onEnded { value in
                    let inside = hypot(value.translation.width, value.translation.height) <= cancelDistance
                    pressed = false
                    if inside { action() }
                }
        )
        .help("End the session")
        .accessibilityLabel("End session")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
