import Foundation

@MainActor
protocol BrowserSessionOwnershipHost: AnyObject {
    var sessionOwnershipID: UUID { get }
    var canParticipateInOwnershipArbitration: Bool { get }
    var ownershipArbitrationPriority: Int { get }
    func retryOwnershipAcquisition()
}

@MainActor
final class BrowserHostOwnershipCoordinator {
    private final class WeakHostReference {
        weak var host: BrowserSessionOwnershipHost?

        init(host: BrowserSessionOwnershipHost) {
            self.host = host
        }
    }

    private var ownerID: UUID?
    private var hostByOwnershipID: [UUID: WeakHostReference] = [:]

    func registerHost(_ host: BrowserSessionOwnershipHost) {
        hostByOwnershipID[host.sessionOwnershipID] = WeakHostReference(host: host)
        pruneDeadHosts()
    }

    func unregisterHost(ownershipID: UUID) {
        hostByOwnershipID.removeValue(forKey: ownershipID)
        if ownerID == ownershipID {
            ownerID = nil
            notifyContendersAfterOwnershipRelease(excluding: ownershipID)
        }
        pruneDeadHosts()
    }

    func releaseOwnership(ownerID: UUID) {
        guard self.ownerID == ownerID else { return }
        self.ownerID = nil
        notifyContendersAfterOwnershipRelease(excluding: ownerID)
    }

    func ensureOwnership(ownerID: UUID, canParticipate: Bool) -> Bool {
        pruneDeadHosts()
        pruneStaleOwner()

        if let currentOwnerID = self.ownerID {
            if currentOwnerID == ownerID {
                return canParticipate
            }
            guard canParticipate else { return false }
            guard shouldPreemptOwner(currentOwnerID: currentOwnerID, contenderID: ownerID) else {
                return false
            }
            self.ownerID = ownerID
            notifyPreviousOwnerToYield(ownershipID: currentOwnerID)
            return true
        }

        guard canParticipate else { return false }
        self.ownerID = ownerID
        return true
    }

    private func pruneDeadHosts() {
        hostByOwnershipID = hostByOwnershipID.filter { _, reference in
            reference.host != nil
        }
    }

    private func pruneStaleOwner() {
        guard let ownerID else { return }
        guard let ownerHost = hostByOwnershipID[ownerID]?.host else {
            self.ownerID = nil
            return
        }
        if !ownerHost.canParticipateInOwnershipArbitration {
            self.ownerID = nil
        }
    }

    private func arbitrationPriority(for ownershipID: UUID) -> Int {
        hostByOwnershipID[ownershipID]?.host?.ownershipArbitrationPriority ?? .min
    }

    private func shouldPreemptOwner(currentOwnerID: UUID, contenderID: UUID) -> Bool {
        arbitrationPriority(for: contenderID) > arbitrationPriority(for: currentOwnerID)
    }

    private func notifyPreviousOwnerToYield(ownershipID: UUID) {
        guard let previousOwner = hostByOwnershipID[ownershipID]?.host else { return }
        DispatchQueue.main.async {
            previousOwner.retryOwnershipAcquisition()
        }
    }

    private func notifyContendersAfterOwnershipRelease(excluding ownerID: UUID) {
        pruneDeadHosts()
        let contenders = hostByOwnershipID.compactMap { candidate -> BrowserSessionOwnershipHost? in
            let (candidateOwnerID, reference) = candidate
            guard candidateOwnerID != ownerID else { return nil }
            return reference.host
        }

        DispatchQueue.main.async {
            for host in contenders {
                host.retryOwnershipAcquisition()
            }
        }
    }
}
