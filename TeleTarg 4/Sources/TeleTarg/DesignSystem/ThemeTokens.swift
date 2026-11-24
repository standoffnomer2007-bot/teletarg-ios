import SwiftUI
import UIKit

public extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

public extension UIColor {
    convenience init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

public struct DiscordColors: Sendable {
    public let railBackground: Color
    public let sidebarBackground: Color
    public let chatBackground: Color
    public let surfaceElevated: Color
    public let accent: Color
    public let primaryText: Color
    public let secondaryText: Color

    public static func palette(for mode: DiscordThemePalette, customAccentHex: String) -> DiscordColors {
        let customAccent = Color(hex: customAccentHex) ?? Color(red: 0.345, green: 0.396, blue: 0.949)
        switch mode {
        case .onyx:
            return DiscordColors(
                railBackground: Color(red: 0.047, green: 0.051, blue: 0.059),
                sidebarBackground: Color(red: 0.075, green: 0.082, blue: 0.094),
                chatBackground: Color(red: 0.098, green: 0.106, blue: 0.122),
                surfaceElevated: Color(red: 0.145, green: 0.157, blue: 0.180),
                accent: customAccent,
                primaryText: Color(white: 0.95),
                secondaryText: Color(white: 0.62)
            )
        case .ash:
            return DiscordColors(
                railBackground: Color(red: 0.118, green: 0.122, blue: 0.133),
                sidebarBackground: Color(red: 0.169, green: 0.176, blue: 0.192),
                chatBackground: Color(red: 0.192, green: 0.200, blue: 0.220),
                surfaceElevated: Color(red: 0.235, green: 0.243, blue: 0.267),
                accent: customAccent,
                primaryText: Color(white: 0.95),
                secondaryText: Color(white: 0.68)
            )
        case .blurple:
            return DiscordColors(
                railBackground: Color(red: 0.094, green: 0.106, blue: 0.212),
                sidebarBackground: Color(red: 0.125, green: 0.141, blue: 0.278),
                chatBackground: Color(red: 0.149, green: 0.169, blue: 0.325),
                surfaceElevated: Color(red: 0.196, green: 0.220, blue: 0.412),
                accent: Color(red: 0.345, green: 0.396, blue: 0.949),
                primaryText: .white,
                secondaryText: Color(white: 0.76)
            )
        case .custom:
            return DiscordColors(
                railBackground: Color(red: 0.071, green: 0.075, blue: 0.086),
                sidebarBackground: Color(red: 0.110, green: 0.118, blue: 0.133),
                chatBackground: Color(red: 0.133, green: 0.141, blue: 0.161),
                surfaceElevated: Color(red: 0.180, green: 0.192, blue: 0.216),
                accent: customAccent,
                primaryText: .white,
                secondaryText: Color(white: 0.66)
            )
        }
    }
}

public extension AppFontFamily {
    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .systemSF: design = .default
        case .roundedSF: design = .rounded
        case .monoSF: design = .monospaced
        case .serifNewYork: design = .serif
        }
        if let descriptor = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    var swiftUIDesign: Font.Design {
        switch self {
        case .systemSF: return .default
        case .roundedSF: return .rounded
        case .monoSF: return .monospaced
        case .serifNewYork: return .serif
        }
    }
}

public struct AvatarCircleView: View {
    let localPath: String?
    let initials: String
    let accentHex: String?
    let size: CGFloat
    let isOnline: Bool

    public init(
        localPath: String?,
        initials: String,
        accentHex: String?,
        size: CGFloat,
        isOnline: Bool = false
    ) {
        self.localPath = localPath
        self.initials = initials
        self.accentHex = accentHex
        self.size = size
        self.isOnline = isOnline
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let localPath, let uiImage = UIImage(contentsOfFile: localPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill((Color(hex: accentHex) ?? Color.blue).opacity(0.24))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(Color(hex: accentHex) ?? .blue)
                    }
            }

            if isOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
            }
        }
    }
}
