import SwiftUI

struct CelebrationView: View {
    let itemsSold: [POSInventoryItem]
    let onDismiss: () -> Void
    
    @State private var pulse = false
    @State private var showResetButton = false
    @State private var itemBounces: [CGFloat] = []
    
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
                
                // Pulsing Green Success Checkmark (Rule 4.3: 200pt checkmark)
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .foregroundColor(.toddlerGreen)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear {
                        pulse = true
                    }
                
                // Horizontal list of purchased item images bouncing in (Phase 3 Step 3.9)
                HStack(spacing: ToddlerLayout.gridUnit * 3) {
                    ForEach(0..<min(itemsSold.count, 4), id: \.self) { index in
                        let item = itemsSold[index]
                        AsyncImage(url: item.imageUrl) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color.toddlerSurfaceRaised
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 4))
                        .shadow(radius: 6)
                        .offset(y: itemBounces.indices.contains(index) ? itemBounces[index] : 0)
                    }
                }
                .onAppear {
                    setupItemBounces()
                }
                
                Spacer()
                
                // Go Again! CTA button (Rule 2.4/Rule 1.2: green checkmark circle, 200pt min width)
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
            // Auto reveal reset action after 2 seconds (Rule 4.3 auto-dismiss/transition context)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring()) {
                    showResetButton = true
                }
            }
        }
    }
    
    private func setupItemBounces() {
        itemBounces = Array(repeating: 0, count: itemsSold.count)
        for i in 0..<itemsSold.count {
            // Trigger staggered springs for purchased item cards (Rule 4.2 style)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                withAnimation(
                    .interpolatingSpring(stiffness: 120, damping: 6)
                    .repeatForever(autoreverses: true)
                ) {
                    if itemBounces.indices.contains(i) {
                        itemBounces[i] = -24
                    }
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
