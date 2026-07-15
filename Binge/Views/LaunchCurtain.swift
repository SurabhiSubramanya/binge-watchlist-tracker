import SwiftUI

/// The launch screen, continued — and then lifted.
///
/// `LaunchScreen.storyboard` is a *still image* iOS puts up while the app boots. It
/// cannot animate, and it disappears the instant the first SwiftUI frame is ready.
/// That, on its own, is the jolt: a static wordmark, then the Library, with nothing
/// in between.
///
/// So this redraws that same wordmark in SwiftUI and animates it *away*. Because the
/// curtain's first frame is identical to the storyboard, the hand-off is invisible —
/// what the user sees is one continuous screen that then lifts, rather than two
/// screens swapped.
///
/// **The geometry below is load-bearing.** A 100×120 mark, "Binge" in 46pt bold, a
/// 44×3 rule, 16pt apart, centred — `LaunchScreen.storyboard` carries exactly the same
/// numbers. If the two ever drift apart, the app will visibly jump at the moment of
/// launch, which is the one thing this view exists to prevent.
struct LaunchCurtain: View {
    /// Called when the curtain is done and the app should be revealed.
    let onFinish: () -> Void

    /// Drives the exit. Starts `false` — the storyboard's state — and animates away
    /// from it, never toward it.
    @State private var isLeaving = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.bingeGround.ignoresSafeArea()

            VStack(spacing: 16) {
                // The app-icon emblem (the popcorn-B), matched pixel-for-pixel to
                // `LaunchMark` in LaunchScreen.storyboard: 100x120, scale-aspect-fit.
                // It lifts with the wordmark via the `scaleEffect` below.
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 120)

                Text("Binge")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)

                // A plain rectangle, not a capsule, purely so it matches the
                // storyboard: a launch screen can't round a corner without runtime
                // attributes, which iOS doesn't apply when it renders one.
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: isLeaving ? 132 : 44, height: 3)
            }
            .scaleEffect(isLeaving ? 1.04 : 1)
        }
        // One thing, "Binge" — not a wordmark and a stray decorative bar.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Binge")
        .task { await lift() }
    }

    /// Hold on the launch image for a beat, open the rule out, then get out of the
    /// way. The whole thing is under a second — a splash that outstays its welcome is
    /// worse than no splash at all.
    private func lift() async {
        guard !reduceMotion else {
            // No flourish, and barely a pause: someone who has asked the system for
            // less movement is not asking to be shown a logo for longer.
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.25)) { onFinish() }
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { isLeaving = true }

        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 0.4)) { onFinish() }
    }
}

#Preview {
    LaunchCurtain(onFinish: {})
        .preferredColorScheme(.dark)
}
