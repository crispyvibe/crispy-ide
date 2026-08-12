import Combine
import Foundation

@MainActor
protocol ExperimentalFeaturesProviding: ObservableObject {
    var isTmuxIntegrationEnabled: Bool { get }
    var tmuxSessionBehavior: TmuxSessionBehavior { get }
    var tmuxTabCloseBehavior: TmuxSessionBehavior { get }
    var isACPObservabilityEnabled: Bool { get }
    var isACPObservabilityVerboseEnabled: Bool { get }
    var acpObservabilityMode: ACPObservabilityMode { get }
    var isTerminalInsightEnabled: Bool { get }
    var isEnhancedRemoteExplorerEnabled: Bool { get }
}

@MainActor
final class ExperimentalFeaturesService: ExperimentalFeaturesProviding {
    @Published private(set) var isTmuxIntegrationEnabled: Bool
    @Published private(set) var tmuxSessionBehavior: TmuxSessionBehavior
    @Published private(set) var tmuxTabCloseBehavior: TmuxSessionBehavior
    @Published private(set) var isACPObservabilityEnabled: Bool
    @Published private(set) var isACPObservabilityVerboseEnabled: Bool
    @Published private(set) var isTerminalInsightEnabled: Bool
    @Published private(set) var isEnhancedRemoteExplorerEnabled: Bool

    private var cancellables: Set<AnyCancellable> = []

    var acpObservabilityMode: ACPObservabilityMode {
        if isACPObservabilityVerboseEnabled {
            return .verbose
        }
        if isACPObservabilityEnabled {
            return .baseline
        }
        return .disabled
    }

    init(defaults: UserDefaults = .standard) {
        self.isTmuxIntegrationEnabled = defaults.bool(forKey: AppPreferences.experimentalTmuxIntegrationKey)
        self.tmuxSessionBehavior = TmuxSessionBehavior(
            rawValue: defaults.string(forKey: AppPreferences.experimentalTmuxSessionBehaviorKey)
                ?? AppPreferences.experimentalTmuxSessionBehaviorDefault
        ) ?? .detach
        self.tmuxTabCloseBehavior = TmuxSessionBehavior(
            rawValue: defaults.string(forKey: AppPreferences.experimentalTmuxTabCloseBehaviorKey)
                ?? AppPreferences.experimentalTmuxTabCloseBehaviorDefault
        ) ?? .terminate
        self.isACPObservabilityEnabled = defaults.bool(forKey: AppPreferences.experimentalACPObservabilityKey)
        self.isACPObservabilityVerboseEnabled = defaults.bool(
            forKey: AppPreferences.experimentalACPObservabilityVerboseKey
        )
        self.isTerminalInsightEnabled = defaults.bool(forKey: AppPreferences.experimentalTerminalInsightKey)
        self.isEnhancedRemoteExplorerEnabled = defaults.bool(forKey: AppPreferences.enhancedRemoteExplorerKey)

        defaults.publisher(for: \.experimentalTmuxIntegration)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isTmuxIntegrationEnabled = value }
            .store(in: &cancellables)

        defaults.publisher(for: \.experimentalTmuxSessionBehavior)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.tmuxSessionBehavior = TmuxSessionBehavior(rawValue: value ?? "") ?? .detach
            }
            .store(in: &cancellables)

        defaults.publisher(for: \.experimentalTmuxTabCloseBehavior)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.tmuxTabCloseBehavior = TmuxSessionBehavior(rawValue: value ?? "") ?? .terminate
            }
            .store(in: &cancellables)

        defaults.publisher(for: \.experimentalACPObservability)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isACPObservabilityEnabled = value }
            .store(in: &cancellables)

        defaults.publisher(for: \.experimentalACPObservabilityVerbose)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isACPObservabilityVerboseEnabled = value }
            .store(in: &cancellables)

        defaults.publisher(for: \.experimentalTerminalInsight)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isTerminalInsightEnabled = value }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: defaults
        )
        .receive(on: RunLoop.main)
        .sink { [weak self, weak defaults] _ in
            guard let defaults else { return }
            self?.isEnhancedRemoteExplorerEnabled = defaults.bool(
                forKey: AppPreferences.enhancedRemoteExplorerKey
            )
        }
        .store(in: &cancellables)
    }
}

private extension UserDefaults {
    @objc dynamic var experimentalTmuxIntegration: Bool {
        bool(forKey: AppPreferences.experimentalTmuxIntegrationKey)
    }

    @objc dynamic var experimentalTmuxSessionBehavior: String? {
        string(forKey: AppPreferences.experimentalTmuxSessionBehaviorKey)
    }

    @objc dynamic var experimentalTmuxTabCloseBehavior: String? {
        string(forKey: AppPreferences.experimentalTmuxTabCloseBehaviorKey)
    }

    @objc dynamic var experimentalACPObservability: Bool {
        bool(forKey: AppPreferences.experimentalACPObservabilityKey)
    }

    @objc dynamic var experimentalACPObservabilityVerbose: Bool {
        bool(forKey: AppPreferences.experimentalACPObservabilityVerboseKey)
    }

    @objc dynamic var experimentalTerminalInsight: Bool {
        bool(forKey: AppPreferences.experimentalTerminalInsightKey)
    }
}
