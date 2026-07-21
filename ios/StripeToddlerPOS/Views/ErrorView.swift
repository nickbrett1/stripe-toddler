import SwiftUI

struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-opaque dark overlay background
            Color.black.opacity(0.90)
                .ignoresSafeArea()
            
            VStack(spacing: ToddlerLayout.gridUnit * 5) {
                Spacer()
                
                // Giant error icon (Rule 9.1: 160x160pt xmark.octagon.fill in toddlerRed)
                Image(systemName: "xmark.octagon.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .foregroundColor(.toddlerRed)
                
                // Simple bold error title (Rule 9.1: title2 bold, max 6 words)
                Text(truncateMessage(message))
                    .font(.system(size: 28, weight: .bold)) // Truncated bold feedback
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                
                Spacer()
                
                // Single 120pt CTA Dismiss button (Rule 9.1 / Rule 1.2: green confirm button)
                Button(action: onDismiss) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                        Text("Okay")
                            .font(.system(size: 24, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                    .frame(height: 120)
                    .background(Color.toddlerGreen)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
            }
            .padding(.bottom, ToddlerLayout.gridUnit * 6)
        }
    }
    
    // Force message constraints so toddler/parent doesn't get overwhelmed (Rule 9.1 max 6 words)
    private func truncateMessage(_ rawMessage: String) -> String {
        let words = rawMessage.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count > 6 {
            return words.prefix(5).joined(separator: " ") + "..."
        }
        return rawMessage
    }
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorView(message: "Payment reader connection lost!") {}
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
