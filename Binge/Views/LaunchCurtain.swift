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

    /// Hold on the launch image, open the rule out, let it rest where the eye can
    /// catch it, then lift away as a slow cross-fade.
    ///
    /// The phases are deliberately **sequential and unhurried**. An earlier version
    /// ran the whole thing under a second and began the exit fade only 350ms into a
    /// 550ms spring — so the open flourish and the fade overlapped, the wordmark was
    /// static-and-readable for barely a quarter-second, and it read as a jolt rather
    /// than a reveal. Now each phase finishes and settles before the next begins, and
    /// the mark is on screen ~1.9s: long enough to actually see, still short enough
    /// not to outstay its welcome.
    private func lift() async {
        guard !reduceMotion else {
            // No flourish, but long enough to read: someone who asked the system for
            // less movement still wants to see the wordmark, not have it flash past.
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeInOut(duration: 0.35)) { onFinish() }
            return
        }

        // 1. Hold on the wordmark, perfectly still, long enough to take it in.
        try? await Task.sleep(for: .milliseconds(650))

        // 2. Open the rule out — a slower, well-damped spring so it glides rather
        //    than snaps. The high damping keeps it from overshooting or bouncing.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { isLeaving = true }

        // 3. Let the opened rule come fully to rest and be seen before anything
        //    leaves — this pause is what stops the flourish and the exit colliding.
        try? await Task.sleep(for: .milliseconds(750))

        // 4. Lift away as a slow, soft cross-fade rather than a quick cut.
        withAnimation(.easeInOut(duration: 0.6)) { onFinish() }
    }
}

#Preview {
    LaunchCurtain(onFinish: {})
        .preferredColorScheme(.dark)
}
