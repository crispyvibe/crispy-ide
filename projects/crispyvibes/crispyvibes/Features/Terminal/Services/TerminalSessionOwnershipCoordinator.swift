import Foundation

protocol TerminalSessionOwnershipHost: AnyObject {
    var sessionOwnershipID: UUID { get }
    var desiredSessionIDForOwnership: UUID? { get }
    var canParticipateInOwnershipArbitration: Bool { get }
    var ownershipArbitrationPriority: Int { get }
    func retryOwnershipAcquisition()
}

final class TerminalHostOwnershipCoordinator {
    private final class WeakHostReference {
        weak var host: TerminalSessionOwnershipHost?

        init(host: TerminalSessionOwnershipHost) {
            self.host = host
        }
    }

    private var sessionOwnerByID: [UUID: UUID] = [:]
    private var hostByOwnershipID: [UUID: WeakHostReference] = [:]

    func registerHost(_ host: TerminalSessionOwnershipHost) {
        hostByOwnershipID[host.sessionOwnershipID] = WeakHostReference(host: host)
        pruneDeadHosts()
    }

    func unregisterHost(ownershipID: UUID) {
        hostByOwnershipID.removeValue(forKey: ownershipID)
        sessionOwnerByID = sessionOwnerByID.filter { _, ownerID in
            ownerID != ownershipID
        }
        pruneDeadHosts()
    }

    func releaseOwnership(for sessionID: UUID?, ownerID: UUID) {
        guard let sessionID else { return }
        guard sessionOwnerByID[sessionID] == ownerID else { return }
        sessionOwnerByID.removeValue(forKey: sessionID)
        notifyContendersAfterOwnershipRelease(for: sessionID, excluding: ownerID)
    }

    func ensureOwnership(for sessionID: UUID?, ownerID: UUID, canParticipate: Bool) -> Bool {
        guard let sessionID else { return true }
        pruneDeadHosts()
        pruneStaleSessionOwner(for: sessionID)

        if let currentOwnerID = sessionOwnerByID[sessionID] {
            if currentOwnerID == ownerID {
                return true
            }
            guard canParticipate else { return false }
            guard shouldPreemptOwner(currentOwnerID: currentOwnerID, contenderID: ownerID) else {
                return false
            }
            sessionOwnerByID[sessionID] = ownerID
            notifyPreviousOwnerToYield(ownershipID: currentOwnerID)
            return true
        }

        guard canParticipate else { return false }
        sessionOwnerByID[sessionID] = ownerID
        return true
    }

    private func pruneDeadHosts() {
        hostByOwnershipID = hostByOwnershipID.filter { _, reference in
            reference.host != nil
        }
    }

    private func ownerHost(for sessionID: UUID) -> TerminalSessionOwnershipHost? {
        guard let ownerID = sessionOwnerByID[sessionID] else { return nil }
        guard let ownerHost = hostByOwnershipID[ownerID]?.host else {
            sessionOwnerByID.removeValue(forKey: sessionID)
            return nil
        }
        return ownerHost
    }

    private func arbitrationPriority(for ownershipID: UUID) -> Int {
        guard let host = hostByOwnershipID[ownershipID]?.host else {
            return .min
        }
        return host.ownershipArbitrationPriority
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

    private func pruneStaleSessionOwner(for sessionID: UUID) {
        guard let ownerHost = ownerHost(for: sessionID) else { return }
        if ownerHost.desiredSessionIDForOwnership != sessionID
            || !ownerHost.canParticipateInOwnershipArbitration {
            sessionOwnerByID.removeValue(forKey: sessionID)
        }
    }

    private func notifyContendersAfterOwnershipRelease(
        for sessionID: UUID,
        excluding ownerID: UUID
    ) {
        pruneDeadHosts()
        let contenders = hostByOwnershipID.compactMap { candidate -> TerminalSessionOwnershipHost? in
            let (candidateOwnerID, reference) = candidate
            guard candidateOwnerID != ownerID else { return nil }
            guard let host = reference.host else { return nil }
            guard host.desiredSessionIDForOwnership == sessionID else { return nil }
            return host
        }

        DispatchQueue.main.async {
            for host in contenders {
                host.retryOwnershipAcquisition()
            }
        }
    }
}
