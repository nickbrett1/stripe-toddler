import SwiftUI

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Design System Color Tokens (Rule 3)
extension Color {
    static let toddlerBackground     = Color(red: 0.97, green: 0.97, blue: 1.00) // Near-white
    static let toddlerSurface        = Color.white
    static let toddlerSurfaceRaised  = Color(red: 0.94, green: 0.95, blue: 0.99) // Light card

    static let toddlerBlue           = Color(hex: "#1752E8")
    static let toddlerBlueDark       = Color(hex: "#0D33A6")

    static let toddlerGreen          = Color(hex: "#0DB84A")
    static let toddlerGreenDark      = Color(hex: "#058534")

    static let toddlerRed            = Color(hex: "#EB1919")
    static let toddlerRedDark        = Color(hex: "#A60A0A")

    static let toddlerYellow         = Color(hex: "#FFC200")
    static let toddlerYellowDark     = Color(hex: "#CC8F00")

    static let toddlerText           = Color(hex: "#14141A")
    static let toddlerTextSecondary  = Color(hex: "#666B7A")
    static let toddlerDivider        = Color(hex: "#D9DCE6")
    static let toddlerDisabled       = Color(hex: "#CCCFD9")
    static let toddlerDisabledText   = Color(hex: "#999EA8")
}

// MARK: - Design System Layout Constants (Rule 1 & Rule 5)
enum ToddlerLayout {
    static let minTouchTarget: CGFloat = 120
    static let primaryCTAHeight: CGFloat = 120
    static let primaryCTAMinWidth: CGFloat = 200
    static let gridUnit: CGFloat = 8
    static let targetSpacing: CGFloat = 24
    static let cornerRadiusCard: CGFloat = 24
    static let cornerRadiusButton: CGFloat = 20
    static let cornerRadiusModal: CGFloat = 32
    
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
    static let shadowOpacity: Double = 0.10
}

// MARK: - Button Style (Rule 4)
struct ToddlerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.55, blendDuration: 0),
                value: configuration.isPressed
            )
    }
}

#if os(iOS)
import UIKit
#endif

public enum ToddlerHapticStyle {
    case rigid
    case soft
    case heavy
    case medium
    case light
}

public enum ToddlerHapticType {
    case success
    case warning
    case error
}

// MARK: - Haptic Feedback Helper (Rule 8)
public enum ToddlerHaptic {
    public static func play(_ style: ToddlerHapticStyle) {
        #if os(iOS)
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .rigid: uiStyle = .rigid
        case .soft: uiStyle = .soft
        case .heavy: uiStyle = .heavy
        case .medium: uiStyle = .medium
        case .light: uiStyle = .light
        }
        let generator = UIImpactFeedbackGenerator(style: uiStyle)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    
    public static func playNotification(_ type: ToddlerHapticType) {
        #if os(iOS)
        let uiType: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: uiType = .success
        case .warning: uiType = .warning
        case .error: uiType = .error
        }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(uiType)
        #endif
    }
}
