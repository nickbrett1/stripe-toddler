import SwiftUI

/// Word-light "Keep Scanning!" cue built for toddlers (who can't read yet).
/// One big, unmissable visual: an animated barcode scanner with a sweeping
/// laser and "beep" sonar rings. No small icons, no arrows — the scanner
/// itself is the message.
struct KeepScanningBanner: View {
    @State private var animate = false

    // UPC-style bar widths (points). Values repeat, so we key by index.
    private let bars: [CGFloat] = [2, 1, 3, 1, 1, 2, 1, 4, 1, 2, 1, 1, 3, 1, 2, 2, 1, 1, 4, 1, 2, 1, 3, 1, 1, 2]

    var body: some View {
        HStack(spacing: ToddlerLayout.gridUnit * 6) {
            Spacer(minLength: 0)

            scannerCard

            // Short title — grown-ups read it, toddlers get the motion.
            HStack(spacing: ToddlerLayout.gridUnit * 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.toddlerYellow)

                Text("Keep Scanning!")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(.toddlerBlueDark)

                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.toddlerYellow)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ToddlerLayout.gridUnit * 4)
        .padding(.vertical, ToddlerLayout.gridUnit * 3)
        .background(
            RoundedRectangle(cornerRadius: ToddlerLayout.cornerRadiusCard)
                .fill(Color.toddlerBlue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToddlerLayout.cornerRadiusCard)
                .stroke(Color.toddlerBlue.opacity(0.30), lineWidth: 2)
        )
        .padding(.horizontal, ToddlerLayout.gridUnit * 4)
        .padding(.top, ToddlerLayout.gridUnit * 3)
        .onAppear { animate = true }
    }

    // MARK: - Animated scanner card (the whole message)

    private var scannerCard: some View {
        ZStack {
            // "Beep" sonar rings radiating out from the scanner
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.toddlerGreen.opacity(0.55 - Double(i) * 0.15), lineWidth: 5)
                    .frame(width: 160, height: 160)
                    .scaleEffect(animate ? 1.0 + CGFloat(i) * 0.6 : 0.55)
                    .opacity(animate ? 0.0 : 1.0)
                    .animation(
                        .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.4),
                        value: animate
                    )
            }

            // White barcode card
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .frame(width: 300, height: 130)
                .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 6)
                .overlay(
                    ZStack {
                        // The bars
                        HStack(spacing: 3) {
                            ForEach(Array(bars.enumerated()), id: \.offset) { _, width in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.black)
                                    .frame(width: width * 3.5, height: 84)
                            }
                        }

                        // Sweeping red laser
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.toddlerRed)
                                .frame(width: 6, height: 96)
                                .shadow(color: Color.toddlerRed.opacity(0.9), radius: 10)
                                .position(
                                    x: animate ? geo.size.width - 8 : 8,
                                    y: geo.size.height / 2
                                )
                                .animation(
                                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                    value: animate
                                )
                        }
                    }
                    .padding(.vertical, 14)
                )
        }
    }
}
