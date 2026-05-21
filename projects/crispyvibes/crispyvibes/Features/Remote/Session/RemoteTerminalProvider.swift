// RemoteTerminalProvider.swift — SSH Remote Development
//
// Remote terminal provider. Uses the same TerminalViewModel but
// configured with a processLaunchOverride that opens an SSH session
// to the remote host instead of a local shell.

import Foundation

typealias RemoteTerminalProvider = TerminalViewModel
