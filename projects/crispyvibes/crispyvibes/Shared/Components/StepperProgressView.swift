import SwiftUI

struct StepperProgressView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let stepTitles: [String]
    let currentStep: Int
    let accentColor: Color
    let completedColor: Color
    let inactiveColor: Color
    let textColor: Color
    let secondaryTextColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stepTitles.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Rectangle()
                        .fill(index <= currentStep ? completedColor : inactiveColor)
                        .frame(height: 1.5)
                        .frame(maxWidth: uiScale.chromeSize(40))
                        .frame(height: uiScale.iconSize(22))
                }

                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(
                                index < currentStep
                                    ? completedColor
                                    : index == currentStep
                                        ? accentColor
                                        : Color.clear
                            )
                            .overlay(
                                Circle().stroke(
                                    index <= currentStep ? accentColor : inactiveColor,
                                    lineWidth: 1.5
                                )
                            )
                            .frame(width: uiScale.iconSize(22), height: uiScale.iconSize(22))

                        if index < currentStep {
                            Image(systemName: "checkmark")
                                .font(AppTypographyTokens.scaledIcon(10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(AppTypographyTokens.scaledSystem(10, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    index == currentStep ? .white : secondaryTextColor
                                )
                        }
                    }

                    Text(title)
                        .font(AppTypographyTokens.scaledSystem(10, weight: index == currentStep ? .semibold : .regular))
                        .foregroundStyle(index == currentStep ? textColor : secondaryTextColor)
                        .lineLimit(1)
                }
            }
        }
    }
}
