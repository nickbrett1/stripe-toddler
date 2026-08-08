import SwiftUI

struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-opaque dark overlay background
            Color.black.opacity(0.90)
                .ignoresSafeArea()
            
            VStack(spacing: ToddlerLayout.gridUnit * 4) {
                Spacer()
                
                // Giant error icon (red thumbs down)
                Image(systemName: "hand.thumbsdown.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .foregroundColor(.toddlerRed)
                
                // Full error title and detail text
                VStack(spacing: ToddlerLayout.gridUnit * 2) {
                    Text(formattedTitle)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    if !formattedDetail.isEmpty {
                        Text(formattedDetail)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                
                Spacer()
                
                // Dismiss button
                Button(action: onDismiss) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                        Text("Okay")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, ToddlerLayout.gridUnit * 8)
                    .frame(height: 90)
                    .background(Color.toddlerGreen)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
            }
            .padding(.bottom, ToddlerLayout.gridUnit * 6)
        }
    }
    
    private var formattedTitle: String {
        if message.localizedCaseInsensitiveContains("terminal error") ||
            message.localizedCaseInsensitiveContains("connecting") ||
            message.localizedCaseInsensitiveContains("reader") {
            return "Card Reader Not Found!"
        }
        let lines = message.components(separatedBy: "\n")
        return lines.first ?? message
    }

    private var formattedDetail: String {
        if message.localizedCaseInsensitiveContains("terminal error") ||
            message.localizedCaseInsensitiveContains("connecting") ||
            message.localizedCaseInsensitiveContains("reader") {
            return "Turn on your Stripe Reader M2, or enable Test Mode in Admin Settings (⚙️)"
        }
        let lines = message.components(separatedBy: "\n")
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ")
        }
        return ""
    }
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorView(message: "Payment reader connection lost!") {}
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
