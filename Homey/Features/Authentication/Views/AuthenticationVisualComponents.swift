import SwiftUI

struct AuthenticationBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let bloomSize = max(width, height) * 0.68
            let sideGlowSize = max(width, height) * 0.58

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: AuthenticationTheme.leftWarmPeach, location: 0.0),
                        .init(color: AuthenticationTheme.leftSoftTan, location: 0.34),
                        .init(color: AuthenticationTheme.midWarmCream, location: 0.58),
                        .init(color: AuthenticationTheme.rightCoolIvory, location: 0.82),
                        .init(color: AuthenticationTheme.farRightCoolWhite, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(reduceTransparency ? 0.24 : 0.58),
                                AuthenticationTheme.sunlightGold.opacity(reduceTransparency ? 0.10 : 0.22),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloomSize * 0.50
                        )
                    )
                    .frame(width: bloomSize, height: bloomSize)
                    .blur(radius: reduceTransparency ? 24 : 54)
                    .position(x: width * 0.35, y: height * 0.24)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AuthenticationTheme.coolCardGlow.opacity(reduceTransparency ? 0.06 : 0.14),
                                Color.white.opacity(reduceTransparency ? 0.06 : 0.16),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: sideGlowSize * 0.52
                        )
                    )
                    .frame(width: sideGlowSize, height: sideGlowSize)
                    .blur(radius: reduceTransparency ? 22 : 48)
                    .position(x: width * 0.76, y: height * 0.42)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AuthenticationTheme.lowerLeftWarmth.opacity(reduceTransparency ? 0.06 : 0.18),
                                AuthenticationTheme.softBeige.opacity(reduceTransparency ? 0.04 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: sideGlowSize * 0.48
                        )
                    )
                    .frame(width: sideGlowSize, height: sideGlowSize)
                    .blur(radius: reduceTransparency ? 24 : 52)
                    .position(x: width * 0.18, y: height * 0.88)
            }
        }
        .ignoresSafeArea()
    }
}

struct AuthenticationHeroView: View {
    let isCompact: Bool

    private var headline: AttributedString {
        var text = AttributedString("Home is better together.")

        if let range = text.range(of: "better together.") {
            text[range].foregroundColor = AuthenticationTheme.primaryBlue
        }

        return text
    }

    var body: some View {
        VStack(alignment: isCompact ? .center : .leading, spacing: isCompact ? 12 : 22) {
            Image("homey_login_hero")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: isCompact ? 150 : 390)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .accessibilityHidden(true)

            if !isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(AuthenticationTheme.darkText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Homey helps your family stay organized,\nconnected, and at home.")
                        .font(.title3)
                        .foregroundStyle(AuthenticationTheme.secondaryText)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.leading, 18)
            }
        }
        .padding(.vertical, isCompact ? 4 : 0)
        .padding(.horizontal, isCompact ? 10 : 0)
    }
}

struct AuthenticationFormCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var isCompact = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(isCompact ? 24 : 36)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 26 : 30, style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 1 : 0.92))
            )
            .overlay {
                RoundedRectangle(cornerRadius: isCompact ? 26 : 30, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: AuthenticationTheme.warmShadow, radius: 30, x: 0, y: 16)
    }
}

struct AuthenticationFormHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "house.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AuthenticationTheme.primaryBlue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(AuthenticationTheme.darkText)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AuthenticationTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AuthenticationTextField<Field: Hashable>: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var focusedField: FocusState<Field?>.Binding
    let field: Field
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var submitLabel: SubmitLabel = .next

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AuthenticationTheme.secondaryText)
                .frame(width: 22)
                .accessibilityHidden(true)

            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .focused(focusedField, equals: field)
                .submitLabel(submitLabel)
        }
        .authenticationFieldBackground(isFocused: focusedField.wrappedValue == field)
    }
}

struct AuthenticationSecureField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    @Binding var isPasswordVisible: Bool
    var focusedField: FocusState<Field?>.Binding
    let field: Field
    var textContentType: UITextContentType = .password
    var submitLabel: SubmitLabel = .go

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .foregroundStyle(AuthenticationTheme.secondaryText)
                .frame(width: 22)
                .accessibilityHidden(true)

            Group {
                if isPasswordVisible {
                    TextField(title, text: $text)
                        .textContentType(textContentType)
                } else {
                    SecureField(title, text: $text)
                        .textContentType(textContentType)
                }
            }
            .focused(focusedField, equals: field)
            .submitLabel(submitLabel)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(AuthenticationTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPasswordVisible ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
        }
        .authenticationFieldBackground(isFocused: focusedField.wrappedValue == field)
    }
}

struct AuthenticationErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AuthenticationTheme.darkText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

struct AuthenticationDividerWithText: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AuthenticationTheme.border)
                .frame(height: 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(AuthenticationTheme.secondaryText)

            Rectangle()
                .fill(AuthenticationTheme.border)
                .frame(height: 1)
        }
    }
}

struct AuthenticationPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        AuthenticationTheme.primaryBlue,
                        AuthenticationTheme.primaryBlue.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: AuthenticationTheme.primaryBlue.opacity(configuration.isPressed ? 0.10 : 0.20), radius: 14, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.90 : 1)
    }
}

struct AuthenticationSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AuthenticationTheme.primaryBlue)
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

extension View {
    func authenticationFieldBackground(isFocused: Bool) -> some View {
        modifier(AuthenticationFieldBackground(isFocused: isFocused))
    }
}

private struct AuthenticationFieldBackground: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(AuthenticationTheme.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? AuthenticationTheme.primaryBlue : AuthenticationTheme.fieldBorder, lineWidth: isFocused ? 1.5 : 1)
            }
    }
}

enum AuthenticationTheme {
    static let background = Color(red: 0.98, green: 0.95, blue: 0.91)
    static let leftWarmPeach = Color(red: 0.88, green: 0.73, blue: 0.61)
    static let leftSoftTan = Color(red: 0.96, green: 0.87, blue: 0.76)
    static let midWarmCream = Color(red: 0.98, green: 0.94, blue: 0.87)
    static let rightCoolIvory = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let farRightCoolWhite = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let sunlightGold = Color(red: 1.00, green: 0.91, blue: 0.72)
    static let coolCardGlow = Color(red: 0.82, green: 0.89, blue: 0.98)
    static let lowerLeftWarmth = Color(red: 0.94, green: 0.72, blue: 0.58)
    static let softBeige = Color(red: 0.94, green: 0.86, blue: 0.77)
    static let primaryBlue = Color(red: 0.29, green: 0.53, blue: 0.91)
    static let darkText = Color(red: 0.10, green: 0.14, blue: 0.22)
    static let secondaryText = Color(red: 0.38, green: 0.42, blue: 0.50)
    static let border = Color(red: 0.86, green: 0.84, blue: 0.80)
    static let fieldBorder = Color(red: 0.82, green: 0.82, blue: 0.80)
    static let fieldBackground = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let warmShadow = Color(red: 0.35, green: 0.24, blue: 0.16).opacity(0.10)
}
