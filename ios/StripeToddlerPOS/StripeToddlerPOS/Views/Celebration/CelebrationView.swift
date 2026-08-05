import SwiftUI

struct CelebrationView: View {
    let itemsSold: [POSInventoryItem]
    let onDismiss: () -> Void
    
    @State private var pulse = false
    @State private var showResetButton = false
    
    var body: some View {
        ZStack {
            // Dark overlay background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            // Particle fireworks background
            FireworksEffect()
                .ignoresSafeArea()
            
            VStack(spacing: ToddlerLayout.gridUnit * 5) {
                Spacer()
                
                // Pulsing Gold Thumbs Up
                Image(systemName: "hand.thumbsup.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .foregroundColor(.toddlerYellow)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear {
                        pulse = true
                    }
                
                Spacer()
                
                // Go Again! CTA button
                if showResetButton {
                    Button(action: onDismiss) {
                        HStack(spacing: ToddlerLayout.gridUnit * 2) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                            Text("Go Again!")
                                .font(.system(size: 24, weight: .black))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                        .frame(height: 120)
                        .background(Color.toddlerGreen)
                        .cornerRadius(ToddlerLayout.cornerRadiusButton)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.bottom, ToddlerLayout.gridUnit * 5)
        }
        .onAppear {
            // Auto reveal reset action after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring()) {
                    showResetButton = true
                }
            }
        }
    }
}

struct CelebrationView_Previews: PreviewProvider {
    static var previews: some View {
        CelebrationView(
            itemsSold: [
                POSInventoryItem(barcode: "1", name: "Fire Truck", priceCents: 500, imageUrl: URL(string: "https://placehold.co/400")!)
            ],
            onDismiss: {}
        )
        .previewInterfaceOrientation(.landscapeLeft)
    }
}
