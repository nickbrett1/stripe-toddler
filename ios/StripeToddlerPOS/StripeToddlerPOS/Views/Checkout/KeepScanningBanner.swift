import SwiftUI

/// Word-light "Keep Scanning!" cue built for toddlers (who can't read yet).
/// One big, unmissable visual: an animated barcode scanner with a sweeping
/// laser and "beep" sonar rings. No small icons, no arrows — the scanner
/// itself is the message.
struct KeepScanningBanner: View {
    @State private var animate = false

    // UPC-style bar widths
    private let bars: [CGFloat] = [2, 1, 3, 1, 1, 2, 1, 4, 1, 2, 1, 1, 3, 1, 2, 2, 1, 1, 4, 1, 2]

    var body: some View {
        HStack(spacing: ToddlerLayout.gridUnit * 3) {
            Spacer(minLength: 0)

            miniScannerCard

            HStack(spacing: ToddlerLayout.gridUnit * 1.5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.toddlerYellow)

                Text("Keep Scanning!")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.toddlerBlueDark)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.toddlerYellow)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ToddlerLayout.gridUnit * 3)
        .padding(.vertical, ToddlerLayout.gridUnit * 1.5)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.toddlerBlue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.toddlerBlue.opacity(0.25), lineWidth: 1.5)
        )
        .padding(.horizontal, ToddlerLayout.gridUnit * 4)
        .padding(.top, ToddlerLayout.gridUnit * 1.5)
        .onAppear { animate = true }
    }

    // MARK: - Compact Animated Scanner Icon
    private var miniScannerCard: some View {
        ZStack {
            // White barcode card
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .frame(width: 80, height: 38)
                .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                .overlay(
                    ZStack {
                        // Barcode lines
                        HStack(spacing: 2) {
                            ForEach(Array(bars.enumerated()), id: \.offset) { _, width in
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(Color.black)
                                    .frame(width: width * 1.8, height: 26)
                            }
                        }

                        // Sweeping red laser
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.toddlerRed)
                                .frame(width: 3, height: 30)
                                .shadow(color: Color.toddlerRed.opacity(0.9), radius: 4)
                                .position(
                                    x: animate ? geo.size.width - 4 : 4,
                                    y: geo.size.height / 2
                                )
                                .animation(
                                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                    value: animate
                                )
                        }
                    }
                )
        }
    }
}
