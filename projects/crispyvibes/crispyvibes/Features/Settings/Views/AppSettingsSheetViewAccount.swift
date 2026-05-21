import SwiftUI

extension AppSettingsSheetView {
    var accountCategoryContent: some View {
        Group {
            SettingsCard(
                title: "Sign In",
                description: "Uses Sign in with Apple for cloud-backed features."
            ) {
                accountSignInControls
            }
        }
        .background(
            SettingsWindowAccessor { window in
                authService.updatePresentationAnchor(window)
            }
        )
    }

    var accountSignInControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if authService.isSignedIn {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(appThemePalette.successColor)
                    Text("Signed in" + (authService.userEmail.map { " as \($0)" } ?? ""))
                        .font(AppTypographyTokens.calloutSemibold)
                }

                Button(AppStrings.Settings.Account.signOut) {
                    authService.signOut()
                }
                .buttonStyle(.crispyvibesText)
                .accessibilityIdentifier("app.settings.auth.signout")
            } else {
                Button {
                    authService.signInWithApple(
                        domain: resolvedAuthDomain,
                        clientId: resolvedAuthClientID
                    )
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.crispyvibesPrimary)
                .accessibilityIdentifier("app.settings.auth.apple")
            }

            if let error = authService.lastErrorMessage, !error.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(appThemePalette.warningColor)
                    Text(error)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                }
            }
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> SettingsWindowAccessorView {
        let view = SettingsWindowAccessorView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: SettingsWindowAccessorView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.reportCurrentWindow()
    }
}

private final class SettingsWindowAccessorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportCurrentWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        reportCurrentWindow()
    }

    func reportCurrentWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.onWindowChange?(self?.window)
        }
    }
}
