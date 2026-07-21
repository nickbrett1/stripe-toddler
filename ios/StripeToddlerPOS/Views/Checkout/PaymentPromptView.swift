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
                        Image(systemName: "creditcard.and.123")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.toddlerGreen)
                            .offset(y: bounce ? -12 : 0)
                            .animation(.interpolatingSpring(stiffness: 150, damping: 8).repeatForever(autoreverses: true), value: bounce)
                        
                        Text("Tap Card on Reader!")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(.toddlerText)
                    }
                    .onAppear { bounce = true }
                    
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
                    Button(action: onCancel) {
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
            .frame(width: 420)
        }
    }
}

struct PaymentPromptView_Previews: PreviewProvider {
    static var previews: some View {
        PaymentPromptView(state: .awaitingCardTap, onCancel: {})
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
