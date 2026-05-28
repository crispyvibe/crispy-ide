import AppKit
import SwiftUI

struct HomeWelcomeActions {
    let onAcceptDisclaimer: () -> Void
    let onDismissHome: () -> Void
    let onOpenRecentVibeSpace: (VibeSpaceConfigFile) -> Void
    let onVibeSpaceCreationResult: (VibeSpaceCreationResult) -> Void
    let onContinueTerminalVibeSpace: () -> Void
    let onShowManageVibeSpaces: () -> Void
    let onShowSettings: () -> Void
}

struct HomeWelcomeSurfaceView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    let showsDisclaimer: Bool
    let showBackToVibeSpaceButton: Bool
    let recentVibeSpaceConfigs: [VibeSpaceConfigFile]
    let nextTemporaryVibeSpaceName: String
    let vibeSpaceCreationSheetBinding: Binding<Bool>
    let actions: HomeWelcomeActions

    private var disclaimerPoints: [String] {
        [
            AppStrings.Onboarding.telemetry,
            AppStrings.Onboarding.crashReporting,
            AppStrings.Onboarding.asIs,
            AppStrings.Onboarding.liability,
            AppStrings.Onboarding.justYouAndYourVibe
        ]
    }

    private var welcomeSurfaceCornerRadius: CGFloat {
        18
    }

    private var welcomeSurfaceBorderColor: Color {
        appThemePalette.borderColorValue.opacity(appThemePalette.prefersDarkWindowChrome ? 0.46 : 0.26)
    }

    private var welcomeSurfaceShadowColor: Color {
        appThemePalette.borderColorValue.opacity(appThemePalette.prefersDarkWindowChrome ? 0.13 : 0.05)
    }

    private var welcomeSurfaceGradient: LinearGradient {
        LinearGradient(
            colors: [
                appThemePalette.canvasSecondaryBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.86 : 0.97),
                appThemePalette.canvasBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.76 : 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            if showsDisclaimer {
                disclaimerGate
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                HomeWelcomeDashboardView(
                    recentVibeSpaceConfigs: recentVibeSpaceConfigs,
                    vibeSpaceCreationSheetBinding: vibeSpaceCreationSheetBinding,
                    actions: actions
                )
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: max(geometry.size.height - 84, 0), alignment: .center)
                .padding(.horizontal, 28)
                .padding(.vertical, 42)
            }
            .overlay(alignment: .topTrailing) {
                if showBackToVibeSpaceButton {
                    Button {
                        actions.onDismissHome()
                    } label: {
                        Label("Back to VibeSpace", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.crispyvibesText)
                    .padding(.top, 24)
                    .padding(.trailing, 28)
                    .accessibilityIdentifier("home.back-to-vibespace")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(welcomeCanvasBackground)
        .sheet(isPresented: vibeSpaceCreationSheetBinding) {
            VibeSpaceCreationSheet(
                defaultName: nextTemporaryVibeSpaceName
            ) { result in
                actions.onVibeSpaceCreationResult(result)
            }
        }
    }

    private var disclaimerGate: some View {
        ZStack {
            welcomeCanvasBackground

            VStack(spacing: 28) {
                disclaimerHeroLockup

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Onboarding.disclaimerTitle)
                        .font(AppTypographyTokens.welcomeSectionHeadline)
                        .foregroundStyle(appThemePalette.primaryTextColor.opacity(0.88))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .accessibilityIdentifier("onboarding.disclaimer.title")

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(disclaimerPoints, id: \.self) { point in
                            Label {
                                Text(point)
                                    .font(AppTypographyTokens.welcomeBody)
                                    .foregroundStyle(appThemePalette.primaryTextColor)
                            } icon: {
                                Circle()
                                    .fill(appThemePalette.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }

                    Text(AppStrings.Onboarding.keychainNote)
                        .font(AppTypographyTokens.welcomePath)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button(AppStrings.Onboarding.quit) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.crispyvibesText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AppStrings.Onboarding.quit)
                    .accessibilityIdentifier("onboarding.disclaimer.quit")

                    Spacer()

                    Button(AppStrings.Onboarding.acceptAndContinue) {
                        actions.onAcceptDisclaimer()
                    }
                    .buttonStyle(.crispyvibesPrimary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AppStrings.Onboarding.acceptAndContinue)
                    .accessibilityIdentifier("onboarding.disclaimer.accept")
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 34)
            .frame(maxWidth: 680, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: welcomeSurfaceCornerRadius, style: .continuous)
                    .fill(welcomeSurfaceGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: welcomeSurfaceCornerRadius, style: .continuous)
                    .stroke(welcomeSurfaceBorderColor, lineWidth: 1)
            )
            .shadow(color: welcomeSurfaceShadowColor, radius: 28, x: 0, y: 18)
            .padding(.horizontal, 28)
            .padding(.vertical, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.disclaimer.screen")
    }

    private var disclaimerHeroLockup: some View {
        HStack(alignment: .top, spacing: 18) {
            Image("CrispyVibesMonoMark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 92, height: 80)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.Brand.crispyvibes)
                    .font(AppTypographyTokens.welcomeBrandTitle)
                    .tracking(2.4)
                    .foregroundStyle(appThemePalette.primaryTextColor.opacity(0.95))

                Text(AppStrings.Home.welcomeHero)
                    .font(AppTypographyTokens.scaledChromeSystem(20, weight: .semibold, design: .rounded))
                    .foregroundStyle(appThemePalette.primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppStrings.Home.justYouAndYourVibe)
                    .font(AppTypographyTokens.welcomeBody)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcomeCanvasBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appThemePalette.windowBackgroundColor,
                    appThemePalette.canvasBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.98 : 1.0),
                    appThemePalette.windowBackgroundColor.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(appThemePalette.accentColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.24 : 0.12))
                .frame(width: 520, height: 520)
                .blur(radius: 138)
                .offset(x: -270, y: -310)

            Circle()
                .fill(appThemePalette.successColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.17 : 0.08))
                .frame(width: 460, height: 460)
                .blur(radius: 130)
                .offset(x: 350, y: -220)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            appThemePalette.accentColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.12 : 0.06),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 180)
                .blur(radius: 80)
                .offset(x: -180, y: -40)
        }
    }

}

struct HomeWelcomeDashboardView: View {
    let recentVibeSpaceConfigs: [VibeSpaceConfigFile]
    let vibeSpaceCreationSheetBinding: Binding<Bool>
    let actions: HomeWelcomeActions

    private var hasRecentVibeSpaces: Bool {
        !recentVibeSpaceConfigs.isEmpty
    }

    private var createCardWidth: CGFloat { 348 }
    private var recentsColumnWidth: CGFloat { 348 }
    private var centerAxisGap: CGFloat { 52 }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if hasRecentVibeSpaces {
                ZStack {
                    HomeWelcomeDashboardAxisSpineView()

                    VStack(alignment: .leading, spacing: 22) {
                        HomeWelcomeDashboardLogoView()
                        dashboardGrid
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    HomeWelcomeDashboardLogoView()
                    dashboardGrid
                }
            }
        }
    }

    @ViewBuilder
    private var dashboardGrid: some View {
        if hasRecentVibeSpaces {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                HomeWelcomeCreateVibeSpaceCardView(
                    hasRecentVibeSpaces: true,
                    vibeSpaceCreationSheetBinding: vibeSpaceCreationSheetBinding
                )
                .frame(width: createCardWidth, alignment: .trailing)

                Spacer()
                    .frame(width: centerAxisGap)

                HomeWelcomeRecentVibeSpacesListView(
                    recentVibeSpaceConfigs: recentVibeSpaceConfigs,
                    onOpenRecentVibeSpace: actions.onOpenRecentVibeSpace
                )
                .frame(width: recentsColumnWidth, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 216, alignment: .top)
        } else {
            HomeWelcomeCreateVibeSpaceCardView(
                hasRecentVibeSpaces: false,
                vibeSpaceCreationSheetBinding: vibeSpaceCreationSheetBinding
            )
            .frame(width: createCardWidth, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }

        HomeWelcomeUtilityDockView(
            onContinueTerminalVibeSpace: actions.onContinueTerminalVibeSpace,
            onShowManageVibeSpaces: actions.onShowManageVibeSpaces,
            onShowSettings: actions.onShowSettings
        )
    }
}

struct HomeWelcomeDashboardLogoView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    private var landingTitle: String {
        "\(AppStrings.Brand.crispyvibes) (BETA)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image("CrispyVibesMonoMark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 88, height: 76)

            Text(landingTitle)
                .font(AppTypographyTokens.welcomeBrandTitle)
                .tracking(2.4)
                .foregroundStyle(appThemePalette.primaryTextColor.opacity(0.95))
                .accessibilityIdentifier("welcome.title")

            Text(AppStrings.Home.welcomeHero)
                .font(AppTypographyTokens.welcomeBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(appThemePalette.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HomeWelcomeCreateVibeSpaceCardView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    let hasRecentVibeSpaces: Bool
    let vibeSpaceCreationSheetBinding: Binding<Bool>

    private var cornerRadius: CGFloat { 18 }

    private var cardHeight: CGFloat {
        hasRecentVibeSpaces ? 176 : 184
    }

    var body: some View {
        Button {
            vibeSpaceCreationSheetBinding.wrappedValue = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Home.createNewVibeSpace)
                        .font(AppTypographyTokens.scaledChromeSystem(22, weight: .semibold, design: .rounded))
                        .foregroundStyle(appThemePalette.primaryTextColor)

                    Text(AppStrings.Home.justYouAndYourVibe)
                        .font(AppTypographyTokens.scaledChromeSystem(14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(appThemePalette.accentColor)

                    Text(AppStrings.VibeSpaceCreation.nameYourVibeSpace)
                        .font(AppTypographyTokens.scaledChromeSystem(14, weight: .regular, design: .rounded))
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 278, alignment: .leading)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
            .background(welcomeHeroCardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                appThemePalette.borderColorValue.opacity(0.78),
                                appThemePalette.accentColor.opacity(0.22),
                                appThemePalette.successColor.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.95
                    )
            )
            .shadow(color: appThemePalette.accentColor.opacity(0.08), radius: 14, x: 0, y: 10)
            .shadow(color: appThemePalette.borderColorValue.opacity(appThemePalette.prefersDarkWindowChrome ? 0.13 : 0.05), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome.action.create-vibespace")
    }

    private var welcomeHeroCardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        appThemePalette.canvasSecondaryBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.84 : 0.97),
                        appThemePalette.canvasBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.74 : 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(appThemePalette.accentColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.14 : 0.06))
                    .frame(width: 164, height: 164)
                    .blur(radius: 44)
                    .offset(x: -42, y: -44)
            }
    }
}

struct HomeWelcomeRecentVibeSpacesListView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale

    let recentVibeSpaceConfigs: [VibeSpaceConfigFile]
    let onOpenRecentVibeSpace: (VibeSpaceConfigFile) -> Void

    private var borderColor: Color {
        appThemePalette.borderColorValue.opacity(0.48)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppStrings.Home.recentVibeSpaces)
                    .font(AppTypographyTokens.welcomeSectionHeadline)
                    .foregroundStyle(appThemePalette.primaryTextColor)
                Spacer()
            }
            .padding(.leading, 1)

            Rectangle()
                .fill(borderColor)
                .frame(height: 1)

            if recentVibeSpaceConfigs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Home.nothingRecentYet)
                        .font(AppTypographyTokens.calloutSemibold)
                        .foregroundStyle(appThemePalette.primaryTextColor)
                    Text(AppStrings.Home.createOnceShowHere)
                        .font(AppTypographyTokens.welcomeActionSummary)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                ForEach(Array(recentVibeSpaceConfigs.prefix(5)), id: \.id) { config in
                    Button {
                        onOpenRecentVibeSpace(config)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(7), style: .continuous)
                                    .fill(appThemePalette.canvasBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.16 : 0.44))
                                Image(systemName: "folder")
                                    .font(AppTypographyTokens.scaledIcon(13, weight: .semibold))
                                    .foregroundStyle(appThemePalette.accentColor)
                            }
                            .frame(width: uiScale.iconSize(26), height: uiScale.iconSize(26))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.name)
                                    .font(AppTypographyTokens.welcomeVibeSpaceName)
                                    .foregroundStyle(appThemePalette.primaryTextColor)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(vibespaceSummary(for: config))
                                    .font(AppTypographyTokens.welcomeActionSummary)
                                    .foregroundStyle(appThemePalette.secondaryTextColor)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Image(systemName: "chevron.right")
                                .font(AppTypographyTokens.welcomeStepBadge)
                                .foregroundStyle(appThemePalette.secondaryTextColor.opacity(0.88))
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(borderColor.opacity(0.34))
                                .frame(height: 1)
                                .padding(.top, 42)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("welcome.recent.\(config.id.uuidString)")
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 242, alignment: .topLeading)
    }

    private func vibespaceSummary(for config: VibeSpaceConfigFile) -> String {
        let availableCount = config.projectPaths.count
        let unresolvedCount = config.unresolvedProjectPaths.count
        let totalCount = availableCount + unresolvedCount
        let firstPath = config.projectPaths.first ?? config.unresolvedProjectPaths.first
        let countText = "\(totalCount) item\(totalCount == 1 ? "" : "s")"

        guard let firstPath else { return countText }
        let displayPath = URL(fileURLWithPath: firstPath).lastPathComponent
        return totalCount > 1 ? "\(countText) · \(displayPath)" : displayPath
    }
}

struct HomeWelcomeUtilityDockView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    let onContinueTerminalVibeSpace: () -> Void
    let onShowManageVibeSpaces: () -> Void
    let onShowSettings: () -> Void

    private var borderColor: Color {
        appThemePalette.borderColorValue.opacity(0.58)
    }

    var body: some View {
        HStack(spacing: 0) {
            utilityButton(
                title: "Terminal Mode",
                symbolName: "terminal",
                accessibilityIdentifier: "welcome.action.continue-terminals",
                action: onContinueTerminalVibeSpace
            )

            utilityDivider

            utilityButton(
                title: AppStrings.Home.manageVibeSpacesButton,
                symbolName: "square.stack.3d.up",
                accessibilityIdentifier: "welcome.action.manage-vibespaces",
                action: onShowManageVibeSpaces
            )

            utilityDivider

            utilityButton(
                title: "Settings",
                symbolName: "gearshape",
                accessibilityIdentifier: "welcome.action.settings",
                action: onShowSettings
            )
        }
        .padding(6)
        .frame(maxWidth: 620)
        .background(
            Capsule()
                .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(appThemePalette.prefersDarkWindowChrome ? 0.76 : 0.92))
        )
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: appThemePalette.borderColorValue.opacity(appThemePalette.prefersDarkWindowChrome ? 0.13 : 0.05), radius: 10, x: 0, y: 6)
        .frame(maxWidth: .infinity)
    }

    private var utilityDivider: some View {
        Rectangle()
            .fill(borderColor.opacity(0.52))
            .frame(width: 1, height: 18)
            .padding(.vertical, 8)
    }

    private func utilityButton(
        title: String,
        symbolName: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(AppTypographyTokens.scaledIcon(13, weight: .semibold))
                Text(title)
                    .font(AppTypographyTokens.calloutSemibold)
            }
            .foregroundStyle(appThemePalette.primaryTextColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct HomeWelcomeDashboardAxisSpineView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        appThemePalette.borderColorValue.opacity(0.0),
                        appThemePalette.borderColorValue.opacity(0.22),
                        appThemePalette.borderColorValue.opacity(0.42),
                        appThemePalette.borderColorValue.opacity(0.18),
                        appThemePalette.borderColorValue.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.top, 212)
            .padding(.bottom, 30)
            .allowsHitTesting(false)
    }
}

extension ContentView {
    private func makeHomeWelcomeSurface(showsDisclaimer: Bool) -> some View {
        HomeWelcomeSurfaceView(
            showsDisclaimer: showsDisclaimer,
            showBackToVibeSpaceButton: homeShell.canReturnToVibeSpace,
            recentVibeSpaceConfigs: recentVibeSpaceConfigsForDisplay,
            nextTemporaryVibeSpaceName: homeCatalogCoordinator.nextTemporaryVibeSpaceName(),
            vibeSpaceCreationSheetBinding: homeShell.vibeSpaceCreationSheetBinding,
            actions: HomeWelcomeActions(
                onAcceptDisclaimer: {
                    vibespaceManagement.setAcceptedDisclaimer(true)
                    hasAcceptedDisclaimer = true
                },
                onDismissHome: {
                    homeShell.dismissHome()
                },
                onOpenRecentVibeSpace: { config in
                    homeCatalogCoordinator.restoreVibeSpaceConfig(config)
                },
                onVibeSpaceCreationResult: { result in
                    homeCatalogCoordinator.applyVibeSpaceCreationResult(result)
                },
                onContinueTerminalVibeSpace: {
                    homeCatalogCoordinator.continueWithTerminalVibeSpaceFromWelcome()
                },
                onShowManageVibeSpaces: {
                    homeShell.presentAppSettings(.vibespaces)
                },
                onShowSettings: {
                    showAppSettingsFromAppMenu(category: .general)
                }
            )
        )
    }

    var disclaimerGate: some View {
        makeHomeWelcomeSurface(showsDisclaimer: true)
    }

    var emptyState: some View {
        makeHomeWelcomeSurface(showsDisclaimer: false)
    }
}
