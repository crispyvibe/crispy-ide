// SSHRemoteError.swift — SSH Remote Development

import Foundation

enum SSHRemoteError: LocalizedError {
    case timeout(String)
    case portForwardAlreadyExists(UInt16)
    case portForwardLocalPortInUse(UInt16)
    case portForwardSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let op): return "Operation timed out: \(op)"
        case .portForwardAlreadyExists(let port):
            return "A port forward for localhost:\(port) already exists on this SSH connection."
        case .portForwardLocalPortInUse(let port):
            return "localhost:\(port) is already in use on this Mac. Choose a different local port."
        case .portForwardSetupFailed(let message):
            return "Could not start the port forward: \(message)"
        }
    }
}
