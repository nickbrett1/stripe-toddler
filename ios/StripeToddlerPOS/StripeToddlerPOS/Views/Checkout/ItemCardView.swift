import SwiftUI

struct ItemCardView: View {
    let item: POSInventoryItem
    let onRemove: () -> Void
    @State private var appeared = false
    
    var body: some View {
        HStack(spacing: ToddlerLayout.gridUnit * 3) {
            // Async product image with fallback (Rule 3.4 / Rule 7)
            AsyncImage(url: item.imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                case .failure, .empty:
                    // Color background placeholder
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.toddlerSurfaceRaised)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .foregroundColor(.toddlerTextSecondary)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 100, height: 100)
            
            // Product Name and Price Details (Rule 6.1)
            VStack(alignment: .leading, spacing: ToddlerLayout.gridUnit) {
                Text(item.name)
                    .font(.system(size: 22, weight: .bold)) // Rule 6.1 card floor
                    .foregroundColor(.toddlerText)
                    .lineLimit(1)
                
                Text(formatPrice(item.priceCents))
                    .font(.system(size: 28, weight: .heavy)) // Rule 6.1 price floor
                    .foregroundColor(.toddlerBlue)
            }
            
            Spacer()
            
            // Destructive Action: Remove item button (Rule 2.1/2.2: xmark.circle.fill, Rule 1.3: 120pt touch target padding)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72) // Visible icon size (Appendix B)
                    .foregroundColor(.toddlerRed)
                    .frame(width: ToddlerLayout.minTouchTarget, height: ToddlerLayout.minTouchTarget) // 120pt touch zone
                    .contentShape(Rectangle())
            }
            .buttonStyle(ToddlerButtonStyle())
        }
        .padding(ToddlerLayout.gridUnit * 2)
        .frame(minHeight: ToddlerLayout.minTouchTarget) // Rule 1.4: 120pt min height
        .background(Color.toddlerSurface)
        .cornerRadius(ToddlerLayout.cornerRadiusCard) // Rule 7
        .shadow(
            color: Color.black.opacity(ToddlerLayout.shadowOpacity),
            radius: ToddlerLayout.shadowRadius,
            x: 0,
            y: ToddlerLayout.shadowY
        ) // Rule 3.4
        // Bounce-in animation on appearance (Rule 4.2)
        .scaleEffect(appeared ? 1.0 : 0.5)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.60)) {
                appeared = true
            }
        }
    }
    
    private func formatPrice(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }
}

struct ItemCardView_Previews: PreviewProvider {
    static var previews: some View {
        ItemCardView(
            item: POSInventoryItem(
                barcode: "123",
                name: "Red Fire Truck",
                priceCents: 500,
                imageUrl: URL(string: "https://placehold.co/400")!
            ),
            onRemove: {}
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
