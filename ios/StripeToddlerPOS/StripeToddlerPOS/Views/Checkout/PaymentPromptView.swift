import SwiftUI

struct PaymentPromptView: View {
    let state: POSFlowState
    let onCancel: () -> Void
    @State private var bounce = false
    
    var body: some View {
        ZStack {
            // Semi-opaque background overlay
            Color.black.opacity(0.40)
                .ignoresSafeArea()
            
            VStack(spacing: ToddlerLayout.gridUnit * 4) {
                switch state {
                case .readerSyncing:
                    VStack(spacing: ToddlerLayout.gridUnit * 3) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.toddlerBlue)
                            .opacity(bounce ? 0.5 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bounce)
                        
                        Text("Syncing Reader...")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.toddlerText)
                    }
                    .onAppear { bounce = true }
                    
                case .awaitingCardTap:
                    VStack(spacing: ToddlerLayout.gridUnit * 3) {
                        StripeReaderTapAnimationView()
                        
                        Text("Tap Card on Reader")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.toddlerText)
                    }
                    
                case .processingPayment:
                    VStack(spacing: ToddlerLayout.gridUnit * 3) {
                        ProgressView()
                            .controlSize(.large)
                            .scaleEffect(1.5)
                            .frame(width: 60, height: 60) // Rule 4.5
                            .padding()
                        
                        Text("Paying...")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.toddlerText)
                    }
                    
                default:
                    EmptyView()
                }
                
                // Cancel Button (Rule 1.2: CTA, Rule 2.2: xmark.circle.fill red)
                if state != .processingPayment {
                    Button(action: onDismissOrCancel) {
                        HStack(spacing: ToddlerLayout.gridUnit * 2) {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                            Text("Cancel")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                        .frame(height: 80)
                        .background(Color.toddlerRed)
                        .cornerRadius(ToddlerLayout.cornerRadiusButton)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                }
            }
            .padding(ToddlerLayout.gridUnit * 5)
            .background(Color.toddlerSurface)
            .cornerRadius(ToddlerLayout.cornerRadiusModal) // Rule 7: Modal sheets / popup cornerRadius: 32
            .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
            .frame(width: 480)
        }
    }

    private var onDismissOrCancel: () -> Void {
        onCancel
    }
}

// MARK: - Animated Stripe M2 Reader & Card Tap (Toddler Visual Guidance)
struct StripeReaderTapAnimationView: View {
    @State private var isTapping = false
    @State private var wavePulse = false
    
    var body: some View {
        ZStack {
            // Background Contactless Glow Ripples
            Circle()
                .stroke(Color.toddlerGreen.opacity(wavePulse ? 0.0 : 0.6), lineWidth: 6)
                .frame(width: wavePulse ? 240 : 140, height: wavePulse ? 240 : 140)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: wavePulse
                )
            
            // 1. White Stripe Reader M2 Representation
            VStack(spacing: 12) {
                // 4 Contactless LEDs
                HStack(spacing: 8) {
                    ForEach(0..<4) { _ in
                        Circle()
                            .fill(isTapping ? Color.toddlerGreen : Color(white: 0.82))
                            .frame(width: 10, height: 10)
                            .shadow(color: isTapping ? .toddlerGreen : .clear, radius: 4)
                    }
                }
                
                Spacer()
                
                // Contactless Wave Icon on White Reader
                Image(systemName: "wave.3.right")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color.toddlerBlue)
                    .rotationEffect(.degrees(-90))
                
                Spacer()
                
                // Reader Logo / Brand Line
                Text("STRIPE M2")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(Color(white: 0.55))
                    .tracking(2)
            }
            .padding(16)
            .frame(width: 160, height: 160)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(white: 0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(28)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color(white: 0.85), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
            
            // 2. Animated Stripe Test Card Tapping Down onto Reader M2
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Card Chip
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.toddlerYellow)
                        .frame(width: 24, height: 18)
                    
                    Spacer()
                    
                    // Contactless Icon
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Text("•••• 4242")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(12)
            .frame(width: 140, height: 90)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.38, green: 0.35, blue: 0.95), Color(red: 0.25, green: 0.20, blue: 0.75)], // Stripe Indigo
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            .rotationEffect(.degrees(isTapping ? -5 : -25))
            .offset(x: isTapping ? 10 : -45, y: isTapping ? -15 : -95)
            .animation(
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isTapping
            )
        }
        .frame(width: 260, height: 260)
        .onAppear {
            isTapping = true
            wavePulse = true
        }
    }
}

struct PaymentPromptView_Previews: PreviewProvider {
    static var previews: some View {
        PaymentPromptView(state: .awaitingCardTap, onCancel: {})
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
