import SwiftUI

enum HomeyColors {
    static let background = Color(red: 0.98, green: 0.95, blue: 0.91)
    static let warmPeach = Color(red: 0.88, green: 0.73, blue: 0.61)
    static let warmCream = Color(red: 0.98, green: 0.94, blue: 0.87)
    static let coolIvory = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let primary = Color(red: 0.29, green: 0.53, blue: 0.91)
    static let text = Color(red: 0.10, green: 0.14, blue: 0.22)
    static let secondaryText = Color(red: 0.38, green: 0.42, blue: 0.50)
    static let field = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let border = Color(red: 0.82, green: 0.82, blue: 0.80)
    static let success = Color(red: 0.30, green: 0.58, blue: 0.36)
    static let recipeBackground = Color(red: 0.985, green: 0.977, blue: 0.961)
    static let recipeGreenAccent = success
    static let recipeOrangeAccent = Color(red: 0.91, green: 0.36, blue: 0.10)
    static let recipeCardBackground = Color.white
    static let danger = Color(red: 0.76, green: 0.20, blue: 0.18)
}

enum HomeyTypography {
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.body
    static let caption = Font.subheadline
}

enum HomeySpacing { static let small: CGFloat = 8; static let medium: CGFloat = 16; static let large: CGFloat = 24; static let extraLarge: CGFloat = 32 }
enum HomeyCornerRadius { static let field: CGFloat = 14; static let card: CGFloat = 24 }

struct HomeyBackground: View {
    var body: some View {
        LinearGradient(colors: [HomeyColors.warmPeach, HomeyColors.warmCream, HomeyColors.coolIvory], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct HomeyCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(HomeySpacing.large).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: HomeyCornerRadius.card, style: .continuous))
            .shadow(color: .brown.opacity(0.10), radius: 24, y: 12)
    }
}

extension View { func homeyCard() -> some View { modifier(HomeyCardModifier()) } }

struct HomeyButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
            .foregroundStyle(secondary ? HomeyColors.primary : .white)
            .background(secondary ? Color.white : HomeyColors.primary, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
            .overlay { RoundedRectangle(cornerRadius: HomeyCornerRadius.field).stroke(HomeyColors.primary, lineWidth: secondary ? 1 : 0) }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct HomeyTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 15).frame(minHeight: 52).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
            .overlay { RoundedRectangle(cornerRadius: HomeyCornerRadius.field).stroke(HomeyColors.border) }
    }
}

extension View { func homeyTextField() -> some View { modifier(HomeyTextFieldModifier()) } }

struct HomeyErrorView: View {
    let message: String
    var body: some View { Label(message, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(HomeyColors.danger).frame(maxWidth: .infinity, alignment: .leading) }
}

struct HomeyBrandHeader: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "house.fill").font(.title2).foregroundStyle(.white).frame(width: 54, height: 54).background(HomeyColors.primary, in: RoundedRectangle(cornerRadius: 17))
            Text(title).font(HomeyTypography.hero).foregroundStyle(HomeyColors.text).multilineTextAlignment(.center)
            Text(subtitle).font(HomeyTypography.caption).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
}
