import SwiftUI

@MainActor
struct AutomationOverviewView: View {
    @Environment(\.appThemePalette) var palette
    @Environment(\.crispyvibesUIScale) var uiScale
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var isRevealed = false
    @State var selectedExample: AutomationOverviewExampleScenario = .executiveBriefing

    let isActive: Bool
    let onOpenSkills: () -> Void
    let onOpenVibes: () -> Void
    let onOpenLanes: () -> Void
    let onOpenLoops: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(30)) {
                introduction
                conceptFlow
                exampleFlow
            }
            .padding(.horizontal, uiScale.spacing(32))
            .padding(.vertical, uiScale.spacing(28))
            .frame(maxWidth: uiScale.chromeSize(1180), alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvasBackgroundColor)
        .task(id: [isActive, reduceMotion]) {
            guard isActive else {
                isRevealed = false
                return
            }
            if !reduceMotion {
                await _Concurrency.Task.yield()
            }
            isRevealed = true
        }
    }

    private var introduction: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: uiScale.spacing(20)) {
                introductionCopy
                Spacer(minLength: uiScale.spacing(24))
                startButton
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
                introductionCopy
                startButton
            }
        }
        .automationOverviewReveal(
            isRevealed: isRevealed,
            order: 0,
            reduceMotion: reduceMotion,
            offset: uiScale.spacing(10)
        )
    }

    private var introductionCopy: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(14)) {
            Image(systemName: "gearshape.2")
                .font(.system(size: uiScale.iconSize(20), weight: .semibold))
                .foregroundStyle(palette.accentColor)
                .frame(width: uiScale.chromeSize(44), height: uiScale.chromeSize(44))
                .background(
                    RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                        .fill(palette.accentColor.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                        .strokeBorder(palette.accentColor.opacity(0.28))
                )

            VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
                Text(AppStrings.Automation.introTitle)
                    .font(.system(size: uiScale.textSize(24), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppStrings.Automation.introSubtitle)
                    .font(.system(size: uiScale.textSize(13)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineSpacing(uiScale.spacing(2))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var startButton: some View {
        Button(action: onOpenVibes) {
            Label(AppStrings.Automation.startWithVibe, systemImage: "sparkles.rectangle.stack")
                .font(.system(size: uiScale.textSize(13), weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(uiScale.controlSize)
    }

    private var conceptFlow: some View {
        ViewThatFits(in: .horizontal) {
            horizontalConceptFlow(cardWidth: 260)
            horizontalConceptFlow(cardWidth: 230)

            VStack(spacing: uiScale.spacing(10)) {
                skillCard
                connector(direction: .down, revealOrder: 1.5)
                vibeCard
                connector(direction: .down, revealOrder: 2.5)
                laneCard
                connector(direction: .down, revealOrder: 3.5)
                loopCard
            }
        }
    }

    private func horizontalConceptFlow(cardWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)
            skillCard
                .frame(width: uiScale.chromeSize(cardWidth))
            connector(direction: .right, revealOrder: 1.5)
            vibeCard
                .frame(width: uiScale.chromeSize(cardWidth))
            connector(direction: .right, revealOrder: 2.5)
            laneCard
                .frame(width: uiScale.chromeSize(cardWidth))
            connector(direction: .right, revealOrder: 3.5)
            loopCard
                .frame(width: uiScale.chromeSize(cardWidth))
            Spacer(minLength: 0)
        }
    }

    private var skillCard: some View {
        conceptCard(
            number: "01",
            title: AppStrings.Automation.skillConcept,
            role: AppStrings.Automation.skillRole,
            description: AppStrings.Automation.skillDescription,
            artwork: .skill,
            color: palette.accentStrongColor,
            revealOrder: 1,
            details: [
                (AppStrings.Automation.skillInstructions, "text.book.closed"),
                (AppStrings.Automation.skillResources, "shippingbox"),
                (AppStrings.Automation.skillRoles, "person.2")
            ],
            actionTitle: AppStrings.Automation.openSkills,
            action: onOpenSkills
        )
    }

    private var vibeCard: some View {
        conceptCard(
            number: "02",
            title: AppStrings.Automation.vibeConcept,
            role: AppStrings.Automation.vibeRole,
            description: AppStrings.Automation.vibeDescription,
            artwork: .vibe,
            color: palette.accentColor,
            revealOrder: 2,
            details: [
                (AppStrings.Automation.vibeOutcome, "target"),
                (AppStrings.VibeLanes.editorDoneWhen, "checkmark.seal"),
                (AppStrings.Automation.vibeLimitsExecution, "timer")
            ],
            actionTitle: AppStrings.Automation.openVibes,
            action: onOpenVibes
        )
    }

    private var laneCard: some View {
        conceptCard(
            number: "03",
            title: AppStrings.Automation.laneConcept,
            role: AppStrings.Automation.laneRole,
            description: AppStrings.Automation.laneDescription,
            artwork: .lane,
            color: palette.warningColor,
            revealOrder: 3,
            details: [
                (AppStrings.Automation.laneOrderedVibes, "list.number"),
                (AppStrings.Automation.laneInputsOutputs, "arrow.left.arrow.right"),
                (AppStrings.Automation.laneHandoffs, "arrowshape.turn.up.right")
            ],
            actionTitle: AppStrings.Automation.openLanes,
            action: onOpenLanes
        )
    }

    private var loopCard: some View {
        conceptCard(
            number: "04",
            title: AppStrings.Automation.loopConcept,
            role: AppStrings.Automation.loopRole,
            description: AppStrings.Automation.loopDescription,
            artwork: .loop,
            color: palette.successColor,
            revealOrder: 4,
            details: [
                (AppStrings.Automation.loopProjectTask, "folder"),
                (AppStrings.Loops.schedule, "calendar"),
                (AppStrings.Loops.history, "clock")
            ],
            actionTitle: AppStrings.Automation.openLoops,
            action: onOpenLoops
        )
    }

    private func conceptCard(
        number: String,
        title: String,
        role: String,
        description: String,
        artwork: AutomationConceptArtwork.Kind,
        color: Color,
        revealOrder: Double,
        details: [(String, String)],
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                HStack(alignment: .top, spacing: uiScale.spacing(12)) {
                    VStack(alignment: .leading, spacing: uiScale.spacing(3)) {
                        Text(number)
                            .font(.system(size: uiScale.textSize(9), weight: .bold, design: .monospaced))
                            .foregroundStyle(color)
                        Text(title)
                            .font(.system(size: uiScale.textSize(19), weight: .bold))
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: uiScale.spacing(4))
                    AutomationConceptArtwork(kind: artwork, color: color, isActive: isActive)
                        .frame(width: uiScale.chromeSize(86), height: uiScale.chromeSize(58))
                }

                VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
                    Text(role)
                        .font(.system(size: uiScale.textSize(12), weight: .semibold))
                        .foregroundStyle(color)
                    Text(description)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle()
                    .fill(palette.borderColorValue.opacity(0.38))
                    .frame(maxWidth: .infinity)
                    .frame(height: uiScale.chromeSize(1))

                VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        Label(detail.0, systemImage: detail.1)
                            .font(.system(size: uiScale.textSize(10), weight: .medium))
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: uiScale.spacing(2))

                HStack(spacing: uiScale.spacing(6)) {
                    Text(actionTitle)
                        .font(.system(size: uiScale.textSize(11), weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: uiScale.iconSize(9), weight: .bold))
                }
                .foregroundStyle(color)
            }
            .padding(uiScale.spacing(18))
            .frame(maxWidth: .infinity, minHeight: uiScale.chromeSize(260), alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                    .fill(palette.canvasSecondaryBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                    .strokeBorder(palette.borderColorValue.opacity(0.48))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vibeLaneHoverable(cornerRadius: uiScale.chromeSize(8))
        .automationOverviewReveal(
            isRevealed: isRevealed,
            order: revealOrder,
            reduceMotion: reduceMotion,
            offset: uiScale.spacing(16)
        )
        .accessibilityLabel("\(title). \(role). \(description). \(actionTitle)")
    }

    private func connector(
        direction: AutomationFlowDirection,
        revealOrder: Double
    ) -> some View {
        AutomationFlowConnector(direction: direction, isActive: isActive, iconSize: 13)
            .foregroundStyle(palette.tertiaryTextColor)
            .frame(width: uiScale.chromeSize(46), height: uiScale.chromeSize(38))
            .automationOverviewReveal(
                isRevealed: isRevealed,
                order: revealOrder,
                reduceMotion: reduceMotion,
                offset: 0
            )
            .accessibilityHidden(true)
    }

}
