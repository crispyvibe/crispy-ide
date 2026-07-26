import SwiftUI

extension AutomationOverviewView {
    var exampleFlow: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
            Rectangle()
                .fill(palette.borderColorValue.opacity(0.42))
                .frame(maxWidth: .infinity)
                .frame(height: uiScale.chromeSize(1))

            VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
                Text(AppStrings.Automation.exampleTitle)
                    .font(.system(size: uiScale.textSize(15), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                Text(AppStrings.Automation.exampleSubtitle)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                exampleSelector
                    .padding(.top, uiScale.spacing(6))

                Text(selectedExample.summary)
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.18),
                        value: selectedExample
                    )
            }
            .automationOverviewReveal(
                isRevealed: isRevealed,
                order: 5,
                reduceMotion: reduceMotion,
                offset: uiScale.spacing(8)
            )

            ViewThatFits(in: .horizontal) {
                horizontalBlueprint
                verticalBlueprint
            }
            .id(selectedExample)
            .padding(.horizontal, uiScale.spacing(20))
            .padding(.vertical, uiScale.spacing(18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.canvasSecondaryBackgroundColor.opacity(0.46))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.borderColorValue.opacity(0.38))
                    .frame(height: uiScale.chromeSize(1))
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.borderColorValue.opacity(0.38))
                    .frame(height: uiScale.chromeSize(1))
            }
            .automationOverviewReveal(
                isRevealed: isRevealed,
                order: 5.4,
                reduceMotion: reduceMotion,
                offset: uiScale.spacing(10)
            )
        }
    }

    private var exampleSelector: some View {
        Picker(AppStrings.Automation.exampleSelectorLabel, selection: $selectedExample) {
            ForEach(AutomationOverviewExampleScenario.allCases) { scenario in
                Text(scenario.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .tag(scenario)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(uiScale.controlSize)
        .frame(maxWidth: uiScale.chromeSize(620))
        .accessibilityIdentifier("automation.example.selector")
    }

    private var horizontalBlueprint: some View {
        HStack(alignment: .center, spacing: 0) {
            skillSource
                .frame(width: uiScale.chromeSize(172))

            blueprintLink(.right)

            laneBlueprint
                .frame(width: uiScale.chromeSize(470))

            blueprintLink(.right)

            loopDestination
                .frame(width: uiScale.chromeSize(190))
        }
        .frame(minWidth: uiScale.chromeSize(936), maxWidth: .infinity, alignment: .center)
    }

    private var verticalBlueprint: some View {
        VStack(alignment: .leading, spacing: 0) {
            skillSource
            blueprintLink(.down)
            laneBlueprint
            blueprintLink(.down)
            loopDestination
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skillSource: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            endpointHeader(
                number: "01",
                concept: AppStrings.Automation.skillConcept,
                role: AppStrings.Automation.skillRole,
                systemImage: "books.vertical.fill",
                color: palette.accentStrongColor
            )

            HStack(spacing: uiScale.spacing(6)) {
                skillBadge(
                    selectedExample.workSkill,
                    systemImage: selectedExample.workSkillImage
                )
                skillBadge(
                    selectedExample.reviewSkill,
                    systemImage: selectedExample.reviewSkillImage
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var laneBlueprint: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
            HStack(alignment: .firstTextBaseline, spacing: uiScale.spacing(10)) {
                VStack(alignment: .leading, spacing: uiScale.spacing(3)) {
                    HStack(spacing: uiScale.spacing(6)) {
                        Text("03")
                            .font(.system(size: uiScale.textSize(8), weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.tertiaryTextColor)
                        Text(AppStrings.Automation.laneConcept.uppercased())
                            .font(.system(size: uiScale.textSize(9), weight: .bold))
                            .foregroundStyle(palette.warningColor)
                    }
                    Text(selectedExample.laneName)
                        .font(.system(size: uiScale.textSize(13), weight: .bold))
                        .foregroundStyle(palette.primaryTextColor)
                }

                Spacer(minLength: uiScale.spacing(8))

                Label(AppStrings.Automation.exampleVibeCount, systemImage: "scope")
                    .font(.system(size: uiScale.textSize(9), weight: .semibold))
                    .foregroundStyle(palette.accentColor)
                    .lineLimit(1)
            }

            ViewThatFits(in: .horizontal) {
                horizontalCheckpointRail
                verticalCheckpointRail
            }
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(13))
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(7), style: .continuous)
                .fill(palette.warningColor.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(7), style: .continuous)
                .strokeBorder(palette.warningColor.opacity(0.24))
        )
        .accessibilityElement(children: .contain)
    }

    private var horizontalCheckpointRail: some View {
        HStack(alignment: .center, spacing: 0) {
            vibeCheckpoint(
                title: selectedExample.firstVibe,
                skill: selectedExample.workSkill,
                skillImage: selectedExample.workSkillImage
            )
            checkpointLink(.right)
            vibeCheckpoint(
                title: selectedExample.secondVibe,
                skill: selectedExample.workSkill,
                skillImage: selectedExample.workSkillImage
            )
            checkpointLink(.right)
            vibeCheckpoint(
                title: selectedExample.thirdVibe,
                skill: selectedExample.reviewSkill,
                skillImage: selectedExample.reviewSkillImage
            )
        }
        .frame(minWidth: uiScale.chromeSize(390), maxWidth: .infinity)
    }

    private var verticalCheckpointRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            vibeCheckpoint(
                title: selectedExample.firstVibe,
                skill: selectedExample.workSkill,
                skillImage: selectedExample.workSkillImage
            )
            checkpointLink(.down)
            vibeCheckpoint(
                title: selectedExample.secondVibe,
                skill: selectedExample.workSkill,
                skillImage: selectedExample.workSkillImage
            )
            checkpointLink(.down)
            vibeCheckpoint(
                title: selectedExample.thirdVibe,
                skill: selectedExample.reviewSkill,
                skillImage: selectedExample.reviewSkillImage
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loopDestination: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            endpointHeader(
                number: "04",
                concept: AppStrings.Automation.loopConcept,
                role: AppStrings.Automation.loopRole,
                systemImage: "clock.arrow.circlepath",
                color: palette.successColor
            )

            Text(selectedExample.schedule)
                .font(.system(size: uiScale.textSize(13), weight: .bold))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func endpointHeader(
        number: String,
        concept: String,
        role: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(alignment: .center, spacing: uiScale.spacing(10)) {
            Image(systemName: systemImage)
                .font(.system(size: uiScale.iconSize(16), weight: .semibold))
                .foregroundStyle(color)
                .frame(width: uiScale.chromeSize(38), height: uiScale.chromeSize(38))
                .background(
                    RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                        .fill(color.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                        .strokeBorder(color.opacity(0.3))
                )

            VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                HStack(spacing: uiScale.spacing(5)) {
                    Text(number)
                        .font(.system(size: uiScale.textSize(8), weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.tertiaryTextColor)
                    Text(concept.uppercased())
                        .font(.system(size: uiScale.textSize(9), weight: .bold))
                        .foregroundStyle(color)
                }
                Text(role)
                    .font(.system(size: uiScale.textSize(9)))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    private func vibeCheckpoint(
        title: String,
        skill: String,
        skillImage: String
    ) -> some View {
        VStack(spacing: uiScale.spacing(6)) {
            Image(systemName: "scope")
                .font(.system(size: uiScale.iconSize(13), weight: .semibold))
                .foregroundStyle(palette.accentColor)
                .frame(width: uiScale.chromeSize(28), height: uiScale.chromeSize(28))
                .background(Circle().fill(palette.accentColor.opacity(0.12)))
                .overlay(Circle().strokeBorder(palette.accentColor.opacity(0.32)))

            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Label(skill, systemImage: skillImage)
                .font(.system(size: uiScale.textSize(8), weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
        }
        .frame(width: uiScale.chromeSize(100))
        .accessibilityElement(children: .combine)
    }

    private func skillBadge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: uiScale.textSize(9), weight: .semibold))
            .foregroundStyle(palette.primaryTextColor)
            .padding(.horizontal, uiScale.spacing(7))
            .frame(height: uiScale.chromeSize(25))
            .background(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(5), style: .continuous)
                    .fill(palette.accentStrongColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(5), style: .continuous)
                    .strokeBorder(palette.accentStrongColor.opacity(0.22))
            )
    }

    private func blueprintLink(_ direction: AutomationFlowDirection) -> some View {
        flowLink(direction, length: 52, thickness: 1, iconSize: 9)
    }

    private func checkpointLink(_ direction: AutomationFlowDirection) -> some View {
        flowLink(direction, length: 32, thickness: 1, iconSize: 7)
    }

    private func flowLink(
        _ direction: AutomationFlowDirection,
        length: CGFloat,
        thickness: CGFloat,
        iconSize: CGFloat
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(palette.borderColorValue.opacity(0.6))
                .frame(
                    width: direction == .right
                        ? uiScale.chromeSize(length)
                        : uiScale.chromeSize(thickness),
                    height: direction == .down
                        ? uiScale.chromeSize(length)
                        : uiScale.chromeSize(thickness)
                )

            AutomationFlowConnector(
                direction: direction,
                isActive: isActive,
                iconSize: iconSize
            )
            .foregroundStyle(palette.secondaryTextColor)
        }
        .frame(
            width: direction == .right
                ? uiScale.chromeSize(length)
                : uiScale.chromeSize(38),
            height: direction == .down
                ? uiScale.chromeSize(length)
                : uiScale.chromeSize(38)
        )
        .accessibilityHidden(true)
    }
}
