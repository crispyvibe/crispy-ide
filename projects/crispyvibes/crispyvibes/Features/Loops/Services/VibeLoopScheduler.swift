import AppKit
import Foundation

@MainActor
final class VibeLoopScheduler {
    private let manager: VibeLoopManager
    private let clock: VibeLoopClock
    private var sleepTask: _Concurrency.Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var started = false

    init(manager: VibeLoopManager, clock: VibeLoopClock = VibeLoopSystemClock()) {
        self.manager = manager
        self.clock = clock
    }

    func start() {
        guard !started else { return }
        started = true
        manager.onScheduleChanged = { [weak self] in
            Task { await self?.reconcileAfterConfigurationChange() }
        }
        observe(
            NSWorkspace.didWakeNotification,
            center: NSWorkspace.shared.notificationCenter
        )
        observe(.NSSystemTimeZoneDidChange, center: .default)
        observe(.NSSystemClockDidChange, center: .default)
        Task { await reconcile(reason: .catchUp) }
    }

    func reconcileNow() {
        Task { await reconcile(reason: .catchUp) }
    }

    private func reconcileAfterConfigurationChange() async {
        await reconcile(reason: .configurationChange)
    }

    private func reconcile(reason: VibeLoopReconciliationReason) async {
        guard started else { return }
        sleepTask?.cancel()
        await manager.reconcileDueLoops(at: clock.now, reason: reason)
        scheduleNextWake()
    }

    func shutdown() {
        started = false
        sleepTask?.cancel()
        sleepTask = nil
        manager.onScheduleChanged = nil
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func scheduleNextWake() {
        guard started, let next = manager.earliestNextRunDate() else { return }
        let delay = max(0.05, next.timeIntervalSince(clock.now))
        let nanoseconds = UInt64(min(delay, 7 * 24 * 60 * 60) * 1_000_000_000)
        sleepTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: nanoseconds)
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.reconcileScheduledWake(expectedAt: next)
        }
    }

    private func reconcileScheduledWake(expectedAt: Date) async {
        guard started else { return }
        sleepTask = nil
        await manager.reconcileDueLoops(
            at: clock.now,
            reason: .scheduledWake(expectedAt: expectedAt)
        )
        scheduleNextWake()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let observer = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.reconcileNow()
            }
        }
        observers.append((center, observer))
    }
}
