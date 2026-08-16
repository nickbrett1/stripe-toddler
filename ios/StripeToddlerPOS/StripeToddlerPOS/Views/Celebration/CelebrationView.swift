import SwiftUI

// MARK: - Payment Success (Celebration) Screen
//
// After a successful payment, celebrates by parading every purchased item
// through a big, toddler-friendly auto-rotating carousel over fireworks.
// Toddlers can also swipe, tap a toy (advances the parade), or use the huge
// side arrows to explore what they "got".
struct CelebrationView: View {
    let itemsSold: [POSInventoryItem]
    let onDismiss: () -> Void

    @State private var selectedIndex = 0
    @State private var showResetButton = false
    @State private var carouselTimer: Timer?

    private var totalCents: Int {
        itemsSold.reduce(0) { $0 + $1.priceCents }
    }

    private var hasMultipleItems: Bool {
        itemsSold.count > 1
    }

    var body: some View {
        ZStack {
            // Dark overlay background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            // Particle fireworks background
            FireworksEffect()
                .ignoresSafeArea()

            // GeometryReader sizes the carousel to the *available* height (safe
            // areas excluded) so the screen fits in landscape without clipping
            // at the bottom. ScrollView is a safety net for very short screens.
            GeometryReader { geo in
                let availableHeight = max(0, geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom)
                let carouselHeight = min(440, max(240, availableHeight - 370))
                let cardImageHeight = max(170, carouselHeight - 100)

                ScrollView {
                    VStack(spacing: ToddlerLayout.gridUnit * 3) {
                        header

                        if itemsSold.isEmpty {
                            emptyFallback
                        } else {
                            carousel(height: carouselHeight, imageHeight: cardImageHeight)
                            pageDots
                        }

                        Spacer(minLength: ToddlerLayout.gridUnit * 2)

                        goAgainButton
                    }
                    .frame(maxWidth: .infinity, minHeight: availableHeight)
                    .padding(.vertical, ToddlerLayout.gridUnit * 3)
                    .padding(.horizontal, ToddlerLayout.gridUnit * 3)
                }
            }
        }
        .onAppear {
            startCarouselAutoRotation()
            // Auto-reveal the "Go Again!" CTA after a beat so the celebration
            // gets a moment to land before the next action appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring()) {
                    showResetButton = true
                }
            }
        }
        .onDisappear {
            carouselTimer?.invalidate()
            carouselTimer = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: ToddlerLayout.gridUnit * 1.5) {
            Text("🎉 Yay! All Done! 🎉")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)

            Text("You got \(itemsSold.count) \(itemsSold.count == 1 ? "item" : "items")!")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.toddlerYellow)

            if totalCents > 0 {
                // Yellow (not green) so it reads as a celebratory tag, never a button
                Text("Total: \(formatPrice(totalCents))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.toddlerText)
                    .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                    .padding(.vertical, ToddlerLayout.gridUnit * 1.5)
                    .background(Capsule().fill(Color.toddlerYellow))
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Item Carousel

    private func carousel(height: CGFloat, imageHeight: CGFloat) -> some View {
        ZStack {
            // Auto-rotating parade of everything in the basket
            TabView(selection: $selectedIndex) {
                ForEach(Array(itemsSold.enumerated()), id: \.offset) { index, item in
                    CelebrationItemCardView(item: item, imageHeight: imageHeight)
                        .tag(index)
                        .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                        .onTapGesture {
                            // Tap-to-explore: tapping a toy advances the parade
                            advanceToNextItem()
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)

            // Big toddler-safe arrows on either side
            if hasMultipleItems {
                HStack {
                    carouselArrow(systemName: "chevron.left", action: goToPreviousItem)
                    Spacer()
                    carouselArrow(systemName: "chevron.right", action: advanceToNextItem)
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 2)
            }
        }
    }

    private func carouselArrow(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: ToddlerLayout.minTouchTarget, height: ToddlerLayout.minTouchTarget)
                .background(Circle().fill(Color.white.opacity(0.18)))
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 3))
        }
        .buttonStyle(ToddlerButtonStyle())
    }

    // MARK: - Page Dots

    @ViewBuilder
    private var pageDots: some View {
        // Cap the visible dots (7 + a "+N" badge) so the row can never grow
        // unbounded: with 12+ items the uncapped row of dots is wider than the
        // screen and shoves the celebration text off the right edge.
        let visibleDotCount = min(itemsSold.count, 7)
        let highlightedDot = min(selectedIndex, visibleDotCount - 1)

        HStack(spacing: ToddlerLayout.gridUnit * 2) {
            ForEach(0..<visibleDotCount, id: \.self) { index in
                Circle()
                    .fill(index == highlightedDot ? Color.toddlerYellow : Color.white.opacity(0.35))
                    .frame(
                        width: index == highlightedDot ? 22 : 14,
                        height: index == highlightedDot ? 22 : 14
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedIndex)
            }

            // Overflow badge: still communicates "there are more toys coming"
            // once the dot cap is reached, without overflowing the screen.
            if itemsSold.count > visibleDotCount {
                Text("+\(itemsSold.count - visibleDotCount)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity) // never exceed the container width
        .frame(height: 24)
        .clipped()
    }

    // MARK: - Fallback (empty basket — should not normally happen)

    private var emptyFallback: some View {
        VStack(spacing: ToddlerLayout.gridUnit * 5) {
            Image(systemName: "hand.thumbsup.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .foregroundColor(.toddlerYellow)

            Text("Great job!")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: - CTA

    private var goAgainButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: ToddlerLayout.gridUnit * 2) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                Text("Go Again!")
                    .font(.system(size: 24, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, ToddlerLayout.gridUnit * 6)
            .frame(height: 96)
            .background(Color.toddlerGreen)
            .cornerRadius(ToddlerLayout.cornerRadiusButton)
        }
        .buttonStyle(ToddlerButtonStyle())
        .opacity(showResetButton ? 1.0 : 0.0)
        .scaleEffect(showResetButton ? 1.0 : 0.7)
        .allowsHitTesting(showResetButton)
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: showResetButton)
    }

    // MARK: - Carousel Rotation

    private func startCarouselAutoRotation() {
        guard hasMultipleItems else { return }
        carouselTimer?.invalidate()
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: true) { _ in
            advanceToNextItem()
        }
    }

    private func advanceToNextItem() {
        guard hasMultipleItems else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            selectedIndex = (selectedIndex + 1) % itemsSold.count
        }
    }

    private func goToPreviousItem() {
        guard hasMultipleItems else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            selectedIndex = (selectedIndex - 1 + itemsSold.count) % itemsSold.count
        }
    }

    // MARK: - Formatting

    private func formatPrice(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }
}

// MARK: - Single Celebrated Item Card
struct CelebrationItemCardView: View {
    let item: POSInventoryItem
    /// Height of the hero photo; sized to match the adaptive carousel frame.
    var imageHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // Hero photo with a gold thumbs-up badge (no text — toddlers don't
            // read; gold instead of green so it never reads as a button)
            ZStack(alignment: .topTrailing) {
                RemoteProductImageView(item: item, imageHeight: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: ToddlerLayout.cornerRadiusModal))

                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.toddlerYellow))
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                    .padding(16)
                    .accessibilityLabel("Got it!")
            }

            // Name + price
            HStack(alignment: .center) {
                Text(item.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.toddlerText)
                    .lineLimit(1)

                Spacer()

                Text(formatPrice(item.priceCents))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.toddlerBlue)
            }
            .padding(.horizontal, ToddlerLayout.gridUnit * 4)
            .padding(.vertical, ToddlerLayout.gridUnit * 3)
            .background(Color.toddlerSurface)
        }
        .background(Color.toddlerSurface)
        .cornerRadius(ToddlerLayout.cornerRadiusModal)
        .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
    }

    private func formatPrice(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }
}

// MARK: - Previews
struct CelebrationView_Previews: PreviewProvider {
    static var previews: some View {
        CelebrationView(
            itemsSold: [
                POSInventoryItem(barcode: "TOY001", name: "Red Fire Truck", priceCents: 500, imageUrl: URL(string: "https://placehold.co/400")!),
                POSInventoryItem(barcode: "TOY002", name: "Wooden Blocks", priceCents: 1200, imageUrl: URL(string: "https://placehold.co/400")!),
                POSInventoryItem(barcode: "TOY003", name: "Teddy Bear", priceCents: 800, imageUrl: URL(string: "https://placehold.co/400")!)
            ],
            onDismiss: {}
        )
        .previewInterfaceOrientation(.landscapeLeft)
    }
}

struct CelebrationItemCardView_Previews: PreviewProvider {
    static var previews: some View {
        CelebrationItemCardView(
            item: POSInventoryItem(
                barcode: "TOY001",
                name: "Red Fire Truck",
                priceCents: 500,
                imageUrl: URL(string: "https://placehold.co/400")!
            )
        )
        .padding()
        .background(Color.black.opacity(0.85))
        .previewLayout(.sizeThatFits)
    }
}

// MARK: - Large-basket preview (12+ items) to catch horizontal overflow
struct CelebrationViewLargeBasket_Previews: PreviewProvider {
    static var previews: some View {
        CelebrationView(
            itemsSold: (1...15).map { index in
                POSInventoryItem(
                    barcode: "TOY\(String(format: "%03d", index))",
                    name: "Toy Item \(index)",
                    // Invalid data URI fails fast so the preview renders quickly
                    // with fallback tiles instead of waiting on network images.
                    priceCents: 500 + index * 100,
                    imageUrl: URL(string: "data:image/jpeg;base64,AAAA")!
                )
            },
            onDismiss: {}
        )
        .frame(width: 390, height: 844)
        .previewLayout(.sizeThatFits)
    }
}
