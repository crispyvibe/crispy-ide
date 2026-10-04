import SwiftUI

/// Permission and structured recovery actions for F062 failures.
@MainActor
struct ScreenCaptureRecoveryView: View {
    @ObservedObject var viewModel: ScreenCaptureRecoveryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(viewModel.title, systemImage: "rectangle.on.rectangle.slash")
                .font(.headline)
            Text(viewModel.message)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(viewModel.commands) { command in
                    Button(viewModel.title(for: command.action)) { viewModel.perform(command) }
                        .accessibilityIdentifier("screenCapture.recovery.\(command.action.rawValue)")
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screenCapture.recovery.panel")
    }
}
