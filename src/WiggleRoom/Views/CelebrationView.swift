//
//  CelebrationView.swift
//  WiggleRoom
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A one-shot, full-screen celebratory moment shown when a tracker closes
/// (its period ends) still under budget/on track — the "completing a video
/// game" flourish the calm, everyday dashboard deliberately doesn't reach
/// for anywhere else (§3.1's steady, non-alarming tone is about the
/// *ongoing* pace read, not about genuinely finishing well). Auto-dismisses
/// after a few seconds, or on tap. See `TrackerDetailView` for the
/// one-shot trigger (`Tracker.hasCelebratedCompletion`).
struct CelebrationView: View {
    let tracker: Tracker
    let status: PaceStatus
    var onDismiss: () -> Void

    @State private var isAnimating = false

    private var headline: String {
        tracker.usesBudgetLanguage ? "Closed Under Budget!" : "Closed On Track!"
    }

    private var subheadline: String {
        let name = tracker.name
        return tracker.usesBudgetLanguage
            ? "\(name) wrapped up with room to spare. Nicely paced."
            : "\(name) wrapped up right on target. Nicely paced."
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isAnimating ? 0.4 : 0)
                .ignoresSafeArea()

            ConfettiView(colors: [
                WiggleRoomColors.good,
                WiggleRoomColors.brand,
                WiggleRoomColors.brandWarm,
                WiggleRoomColors.paceRing,
            ])
            .allowsHitTesting(false)
            .opacity(isAnimating ? 1 : 0)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(WiggleRoomColors.good.opacity(0.16))
                        .frame(width: 132, height: 132)
                        .scaleEffect(isAnimating ? 1 : 0.4)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(WiggleRoomColors.good)
                        .symbolEffect(.bounce, value: isAnimating)
                }

                Text(headline)
                    .font(WiggleRoomFont.headline(28, weight: 700))
                    .multilineTextAlignment(.center)

                Text(subheadline)
                    .font(WiggleRoomFont.aside(16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Button("Nice!") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(WiggleRoomColors.good)
                .padding(.top, 6)
            }
            .padding(28)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 32)
            .scaleEffect(isAnimating ? 1 : 0.75)
            .opacity(isAnimating ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                isAnimating = true
            }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            isAnimating = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

/// A one-shot burst of falling confetti pieces — randomized start position,
/// fall duration, drift, and spin, each computed once at init and then
/// animated to their end state via a single `withAnimation` per piece
/// (rather than a continuous physics loop), which is plenty convincing for
/// a few seconds of celebration and far simpler than a `Canvas`-driven
/// simulation.
private struct ConfettiView: View {
    struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let startX: CGFloat // fraction of width, 0...1
        let delay: Double
        let fallDuration: Double
        let horizontalDrift: CGFloat
        let rotationDegrees: Double
        let size: CGFloat
    }

    let pieces: [Piece]

    init(colors: [Color], count: Int = 50) {
        pieces = (0..<count).map { _ in
            Piece(
                color: colors.randomElement() ?? WiggleRoomColors.good,
                startX: CGFloat.random(in: 0...1),
                delay: Double.random(in: 0...0.5),
                fallDuration: Double.random(in: 1.8...3.2),
                horizontalDrift: CGFloat.random(in: -90...90),
                rotationDegrees: Double.random(in: 180...900) * (Bool.random() ? 1 : -1),
                size: CGFloat.random(in: 6...12)
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiPieceView(piece: piece, containerSize: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct ConfettiPieceView: View {
    let piece: ConfettiView.Piece
    let containerSize: CGSize

    @State private var hasFallen = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 0.45)
            .rotationEffect(.degrees(hasFallen ? piece.rotationDegrees : 0))
            .position(
                x: piece.startX * containerSize.width + (hasFallen ? piece.horizontalDrift : 0),
                y: hasFallen ? containerSize.height + 40 : -20
            )
            .onAppear {
                withAnimation(.easeIn(duration: piece.fallDuration).delay(piece.delay)) {
                    hasFallen = true
                }
            }
    }
}

#Preview {
    CelebrationView(tracker: PreviewData.makeSampleTracker(), status: .good, onDismiss: {})
}
