// SSHPickerOverlayController.swift — SSH Remote Development

import SwiftUI

/// State driver for the in-window SSH connection picker overlay.
///
/// Mirrors the `BoardInlinePickerOverlayController` pattern: a single
/// `ObservableObject` that the canvas observes to know when to render the
/// picker, and that imperative call sites (e.g. toolbar buttons, vibespace
/// settings actions) write to in order to present the picker.
///
/// Rendered as an in-window overlay rather than a macOS sheet so the
/// Liquid Glass background can sample the canvas content behind it.
@MainActor
final class SSHPickerOverlayController: ObservableObject {
    @Published var presentation: SSHPickerPresentation?

    func present(_ presentation: SSHPickerPresentation) {
        self.presentation = presentation
    }

    func dismiss() {
        presentation = nil
    }
}

/// Captures everything required to render an SSH connection picker overlay.
@MainActor
struct SSHPickerPresentation: Identifiable {
    let id = UUID()
    let viewModel: SSHConnectionPickerViewModel
    let profileStore: SSHProfileStore
    let onFolderSelected: (SSHConnection, String) -> Void
    let onCancel: () -> Void
}
