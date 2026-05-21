import SwiftUI

private struct BrowserHostOwnershipParticipationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct BrowserHostOwnershipPriorityBoostKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var browserHostOwnershipParticipationEnabled: Bool {
        get { self[BrowserHostOwnershipParticipationEnabledKey.self] }
        set { self[BrowserHostOwnershipParticipationEnabledKey.self] = newValue }
    }

    var browserHostOwnershipPriorityBoost: Int {
        get { self[BrowserHostOwnershipPriorityBoostKey.self] }
        set { self[BrowserHostOwnershipPriorityBoostKey.self] = newValue }
    }
}

enum BrowserHostPresentation {
    case board(isActive: Bool)
    case detailed
    case spotlight

    private enum Constants {
        static let inactiveBoardPriority = 180
        static let activeBoardPriority = 200
        static let detailedPriority = 220
        static let spotlightPriority = 300
        static let boardAccessibilityIdentifier = "vibespace.browser-board.host"
        static let detailedAccessibilityIdentifier = "vibespace.browser-detailed.host"
        static let spotlightAccessibilityIdentifier = "vibespace.browser-spotlight.host"
    }

    var ownershipPriority: Int {
        switch self {
        case let .board(isActive):
            return isActive ? Constants.activeBoardPriority : Constants.inactiveBoardPriority
        case .detailed:
            return Constants.detailedPriority
        case .spotlight:
            return Constants.spotlightPriority
        }
    }

    var accessibilityIdentifier: String? {
        switch self {
        case .board:
            return Constants.boardAccessibilityIdentifier
        case .detailed:
            return Constants.detailedAccessibilityIdentifier
        case .spotlight:
            return Constants.spotlightAccessibilityIdentifier
        }
    }
}

struct BrowserSessionHostView: NSViewRepresentable {
    @Environment(\.browserHostOwnershipParticipationEnabled) private var ownershipParticipationEnabled
    @Environment(\.browserHostOwnershipPriorityBoost) private var ownershipPriorityBoost

    let viewModel: BrowserPanelViewModel
    var presentation: BrowserHostPresentation = .detailed

    func makeNSView(context: Context) -> BrowserContainerView {
        let container = BrowserContainerView(frame: .zero)
        container.configureAccessibility(identifier: presentation.accessibilityIdentifier)
        container.attach(
            viewModel,
            allowsOwnershipParticipation: ownershipParticipationEnabled,
            ownershipPriority: presentation.ownershipPriority + ownershipPriorityBoost
        )
        return container
    }

    func updateNSView(_ nsView: BrowserContainerView, context: Context) {
        nsView.configureAccessibility(identifier: presentation.accessibilityIdentifier)
        nsView.attach(
            viewModel,
            allowsOwnershipParticipation: ownershipParticipationEnabled,
            ownershipPriority: presentation.ownershipPriority + ownershipPriorityBoost
        )
    }
}

@MainActor
final class BrowserContainerView: NSView, BrowserSessionOwnershipHost {
    private let hostOwnershipID = UUID()
    private weak var desiredViewModel: BrowserPanelViewModel?
    private weak var attachedWebView: CrispyVibesBrowserWebView?
    private var desiredAllowsOwnershipParticipation = true
    private var desiredOwnershipPriority = 0
    private var configuredAccessibilityIdentifier: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            unregisterFromCurrentViewModel()
        }
    }

    func attach(
        _ viewModel: BrowserPanelViewModel,
        allowsOwnershipParticipation: Bool,
        ownershipPriority: Int
    ) {
        if desiredViewModel !== viewModel {
            resetAttachedState()
            unregisterFromCurrentViewModel()
            desiredViewModel = viewModel
            viewModel.hostOwnershipCoordinator.registerHost(self)
        }

        desiredAllowsOwnershipParticipation = allowsOwnershipParticipation
        desiredOwnershipPriority = ownershipPriority
        attemptAttachIfNeeded()
    }

    override func layout() {
        super.layout()
        layoutAttachedWebViewFrame()
        attemptAttachIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            resetAttachedState()
            releaseOwnership()
            return
        }
        attemptAttachIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            resetAttachedState()
            releaseOwnership()
            return
        }
        attemptAttachIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            resetAttachedState()
            releaseOwnership()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func attemptAttachIfNeeded() {
        guard ensureDesiredOwnership() else {
            detachAttachedWebViewIfNeeded()
            return
        }
        guard let webView = desiredViewModel?.webView else { return }
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
        attachedWebView = webView
        layoutAttachedWebViewFrame()
    }

    private func detachAttachedWebViewIfNeeded() {
        guard let attachedWebView else { return }
        if attachedWebView.superview === self {
            attachedWebView.removeFromSuperview()
        }
        self.attachedWebView = nil
    }

    private func releaseOwnership() {
        desiredViewModel?.hostOwnershipCoordinator.releaseOwnership(ownerID: hostOwnershipID)
    }

    private func unregisterFromCurrentViewModel() {
        releaseOwnership()
        desiredViewModel?.hostOwnershipCoordinator.unregisterHost(ownershipID: hostOwnershipID)
    }

    private func resetAttachedState() {
        detachAttachedWebViewIfNeeded()
    }

    private func layoutAttachedWebViewFrame() {
        attachedWebView?.frame = bounds
    }

    private var canParticipateInOwnership: Bool {
        desiredAllowsOwnershipParticipation &&
            desiredViewModel != nil &&
            superview != nil &&
            window != nil
    }

    private func ensureDesiredOwnership() -> Bool {
        guard let desiredViewModel else { return false }
        return desiredViewModel.hostOwnershipCoordinator.ensureOwnership(
            ownerID: hostOwnershipID,
            canParticipate: canParticipateInOwnership
        )
    }

    func configureAccessibility(identifier: String?) {
        guard configuredAccessibilityIdentifier != identifier else { return }
        configuredAccessibilityIdentifier = identifier
        setAccessibilityIdentifier(identifier)
    }

    var sessionOwnershipID: UUID { hostOwnershipID }
    var canParticipateInOwnershipArbitration: Bool { canParticipateInOwnership }
    var ownershipArbitrationPriority: Int { desiredOwnershipPriority }

    func retryOwnershipAcquisition() {
        attemptAttachIfNeeded()
    }
}
