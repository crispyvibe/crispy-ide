import Foundation

@MainActor
final class FeatureWalkthroughController: ObservableObject {
    private static let isWalkthroughEnabled = false
    @Published private(set) var steps: [FeatureWalkthroughStep]
    @Published private(set) var currentStepIndex: Int = 0
    @Published var isPresented = false

    private let defaults: UserDefaults
    private let completedKey: String
    private let forcePresentation: Bool
    private let disableAutoPresentation: Bool
    private var didEvaluateAutoPresentation = false

    init(
        provider: FeatureWalkthroughStepProviding = DefaultFeatureWalkthroughStepProvider(),
        defaults: UserDefaults = .standard,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        completedKey: String = AppPreferences.featureWalkthroughCompletedKey
    ) {
        let isUITestMode = Self.truthy(launchEnvironment["CRISPYVIBES_UI_TEST_MODE"])
        let resolvedCompletedKey = isUITestMode ? "\(completedKey).ui-test" : completedKey
        self.steps = provider.steps
        self.defaults = defaults
        self.completedKey = resolvedCompletedKey
        self.forcePresentation = Self.truthy(launchEnvironment["CRISPYVIBES_UI_TEST_FORCE_WALKTHROUGH"])
        self.disableAutoPresentation = Self.truthy(launchEnvironment["CRISPYVIBES_UI_TEST_DISABLE_AUTO_WALKTHROUGH"])

        if Self.truthy(launchEnvironment["CRISPYVIBES_UI_TEST_RESET_WALKTHROUGH"]) {
            defaults.removeObject(forKey: resolvedCompletedKey)
        }
    }

    var currentStep: FeatureWalkthroughStep? {
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var isLastStep: Bool {
        currentStepIndex >= steps.count - 1
    }

    var progressText: String {
        guard !steps.isEmpty else { return "Step 0 of 0" }
        return "Step \(currentStepIndex + 1) of \(steps.count)"
    }

    func evaluateAutoPresentation(hasVibeSpace: Bool) {
        guard Self.isWalkthroughEnabled else { return }
        guard hasVibeSpace else { return }

        if forcePresentation {
            present(resetToFirstStep: true)
            didEvaluateAutoPresentation = true
            return
        }

        guard !didEvaluateAutoPresentation else { return }
        didEvaluateAutoPresentation = true

        guard !disableAutoPresentation else { return }
        guard !hasCompletedWalkthrough else { return }
        present(resetToFirstStep: true)
    }

    func presentFromToolbar() {
        guard Self.isWalkthroughEnabled else { return }
        present(resetToFirstStep: true)
    }

    func next() {
        guard !steps.isEmpty else {
            completeWalkthrough()
            return
        }

        if isLastStep {
            completeWalkthrough()
            return
        }

        currentStepIndex += 1
    }

    func previous() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }

    func skip() {
        completeWalkthrough()
    }

    func resetForFreshStart() {
        defaults.removeObject(forKey: completedKey)
        currentStepIndex = 0
        isPresented = false
        didEvaluateAutoPresentation = false
    }

    private func present(resetToFirstStep: Bool) {
        guard Self.isWalkthroughEnabled else { return }
        guard !steps.isEmpty else { return }
        if resetToFirstStep {
            currentStepIndex = 0
        }
        isPresented = true
    }

    private func completeWalkthrough() {
        defaults.set(true, forKey: completedKey)
        isPresented = false
    }

    private var hasCompletedWalkthrough: Bool {
        defaults.bool(forKey: completedKey)
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
    }
}
