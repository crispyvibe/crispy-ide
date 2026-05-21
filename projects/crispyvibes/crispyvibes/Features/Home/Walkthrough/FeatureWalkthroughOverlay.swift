import SwiftUI

struct FeatureWalkthroughOverlay: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @ObservedObject var controller: FeatureWalkthroughController

    var body: some View {
        if let step = controller.currentStep {
            ZStack {
                Color.black
                    .opacity(0.45)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(controller.progressText)
                            .font(AppTypographyTokens.captionSemibold)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(controller.progressText)
                            .accessibilityIdentifier("walkthrough.progress")

                        Spacer()

                        Button(AppStrings.Common.skip) {
                            controller.skip()
                        }
                        .buttonStyle(.crispyvibesText)
                        .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("walkthrough.skip")
                    }

                    Text(step.title)
                        .font(AppTypographyTokens.title2Semibold)
                        .foregroundStyle(appThemePalette.primaryTextColor)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(step.title)
                        .accessibilityIdentifier("walkthrough.title")

                    Text(step.message)
                        .font(AppTypographyTokens.body)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(step.message)
                        .accessibilityIdentifier("walkthrough.message")

                    FeatureWalkthroughSlideView(step: step)
                        .accessibilityIdentifier("walkthrough.slide")

                    if let shortcutHint = step.shortcutHint {
                        HStack(spacing: 8) {
                            Image(systemName: "keyboard")
                                .foregroundStyle(appThemePalette.accentColor)
                            Text(shortcutHint)
                                .font(AppTypographyTokens.calloutSemibold)
                                .foregroundStyle(appThemePalette.primaryTextColor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.82))
                        .overlay(
                            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                                .stroke(appThemePalette.borderColorValue.opacity(0.8), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous))
                        .accessibilityIdentifier("walkthrough.shortcut")
                    }

                    HStack(spacing: 10) {
                        Button(AppStrings.Common.back) {
                            controller.previous()
                        }
                        .buttonStyle(.crispyvibesText)
                        .disabled(controller.currentStepIndex == 0)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("walkthrough.previous")

                        Spacer()

                        Button(controller.isLastStep ? AppStrings.Common.done : AppStrings.Common.next) {
                            controller.next()
                        }
                        .buttonStyle(.crispyvibesPrimary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(controller.isLastStep ? "walkthrough.finish" : "walkthrough.next")
                    }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .background(appThemePalette.windowBackgroundColor.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(12), style: .continuous)
                        .stroke(appThemePalette.borderColorValue.opacity(0.85), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(12), style: .continuous))
                .shadow(color: Color.black.opacity(0.3), radius: 20, y: 8)
                .padding(24)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("walkthrough.container")
        }
    }
}

private struct FeatureWalkthroughSlideView: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var appThemePalette
    let step: FeatureWalkthroughStep

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(step.heroImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                ForEach(step.annotations) { annotation in
                    FeatureWalkthroughAnnotationView(annotation: annotation)
                        .position(
                            x: geometry.size.width * annotation.normalizedX,
                            y: geometry.size.height * annotation.normalizedY
                        )
                        .accessibilityIdentifier("walkthrough.annotation.\(annotation.id)")
                }
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(14), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(14), style: .continuous)
                .stroke(appThemePalette.borderColorValue.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 20, y: 8)
    }
}

private struct FeatureWalkthroughAnnotationView: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var appThemePalette
    let annotation: FeatureWalkthroughAnnotation

    var body: some View {
        ZStack {
            Circle()
                .fill(appThemePalette.accentColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.95), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(annotation.title)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(appThemePalette.primaryTextColor)
                Text(annotation.detail)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(3)
            }
            .frame(width: 220, alignment: .leading)
            .padding(10)
            .background(appThemePalette.canvasBackgroundColor.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                    .stroke(appThemePalette.borderColorValue.opacity(0.86), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous))
            .offset(annotation.placement.offset)
        }
    }
}
