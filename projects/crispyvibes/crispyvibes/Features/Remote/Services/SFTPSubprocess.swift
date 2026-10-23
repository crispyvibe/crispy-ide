// SFTPSubprocess.swift — SSH Remote Development
// Binary SFTP protocol client over `ssh -s sftp` subprocess.
// Speaks SFTPv3 wire protocol directly — no text parsing, binary-safe.
// Based on draft-ietf-secsh-filexfer-02 (SFTP version 3).

import Foundation

final class SFTPSubprocess: @unchecked Sendable {
    private let process: Process
    private let stdinHandle: FileHandle
    private let fd: Int32
    private let lock = NSLock()
    private let lifecycleLock = NSLock()
    private var nextRequestId: UInt32 = 1
    private var running = false
    private var resourcesClosed = false

    var isRunning: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return running
    }

    init(controlPath: String, user: String, host: String, port: UInt16) throws {
        let process = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()

        var args = ["-o", "ControlPath=\(controlPath)"]
        if port != 22 { args += ["-p", String(port)] }
        args += ["\(user)@\(host)", "-s", "sftp"]

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        self.fd = outPipe.fileHandleForReading.fileDescriptor

        try process.run()
        inPipe.fileHandleForReading.closeFile()
        outPipe.fileHandleForWriting.closeFile()
        setRunning(true)
        process.terminationHandler = { [weak self] _ in self?.setRunning(false) }

        // SFTP init handshake with timeout — if ssh can't connect, read blocks forever
        send(type: 1) { $0.appendUInt32(3) }
        let box = UnsafeMutableTransferBox<Result<Packet, Error>>(.failure(SFTPError.timeout("init")))
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do { box.value = .success(try self.readPacket()) }
            catch { box.value = .failure(error) }
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 10) == .success else {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            terminate()
            throw SFTPError.operationFailed("SFTP timed out: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let resp = try box.value.get()
        guard resp.type == 2 else {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            terminate()
            throw SFTPError.operationFailed("SFTP init failed (type=\(resp.type)): \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: - Public API (all serialized via lock)

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard isRunning else { throw SFTPError.notConnected }
        return try body()
    }

    func homeDirectory() throws -> String {
        let result = try locked { try _realpath(".") }
        AppDiagnostics.record(category: .remote, level: .info, event: "sftp_home", metadata: ["path": result])
        return result
    }

    func realpath(_ path: String) throws -> String {
        try locked { try _realpath(path) }
    }

    private func _realpath(_ path: String) throws -> String {
        let requestID = sendRequest(type: 16) { $0.appendSSHString(path) } // SSH_FXP_REALPATH
        let resp = try readPacket()
        try validateResponseID(resp, expected: requestID, context: "realpath")
        if resp.type == 104 { // SSH_FXP_NAME
            var payload = resp.payload
            _ = payload.readUInt32()
            guard payload.readUInt32() == 1,
                  let name = payload.readSSHString(),
                  payload.readSSHString() != nil,
                  payload.readSFTPAttrs() != nil,
                  payload.isEmpty else {
                throw SFTPError.operationFailed("realpath: malformed name response")
            }
            return name
        }
        try throwIfStatus(resp, context: "realpath(\(path))")
        throw SFTPError.operationFailed("realpath failed")
    }

    func listDirectory(_ path: String, maximumEntries: Int? = nil) throws -> [SFTPEntry] {
        try locked {
            let openID = sendRequest(type: 11) { $0.appendSSHString(path) }
            let openResp = try readPacket()
            try validateResponseID(openResp, expected: openID, context: "opendir")
            guard openResp.type == 102 else {
                try throwIfStatus(openResp, context: "opendir")
                throw SFTPError.operationFailed("opendir failed")
            }
            var openPayload = openResp.payload
            _ = openPayload.readUInt32()
            guard let handle = openPayload.readSSHData(), openPayload.isEmpty else {
                throw SFTPError.operationFailed("opendir: malformed handle")
            }
            var closeNeeded = true
            defer {
                if closeNeeded, isRunning { try? closeHandle(handle, context: "closedir") }
            }

            var entries = [SFTPEntry]()
            while true {
                try Task.checkCancellation()
                let readID = sendRequest(type: 12) { $0.appendSSHData(handle) }
                let resp = try readPacket()
                try validateResponseID(resp, expected: readID, context: "readdir")
                if resp.type == 101 {
                    let status = try statusDetails(resp, context: "readdir")
                    if status.code == 1 { break }
                    throw SFTPError.operationFailed("readdir: \(status.message)")
                }
                guard resp.type == 104 else {
                    throw SFTPError.operationFailed("readdir: unexpected type \(resp.type)")
                }
                var names = resp.payload
                _ = names.readUInt32()
                guard let count = names.readUInt32(), count > 0 else {
                    throw SFTPError.operationFailed("readdir: malformed name count")
                }
                for _ in 0..<count {
                    try Task.checkCancellation()
                    guard let filename = names.readSSHString(),
                          names.readSSHString() != nil,
                          let attrs = names.readSFTPAttrs() else {
                        throw SFTPError.operationFailed("readdir: malformed name entry")
                    }
                    guard filename != "." && filename != ".." else { continue }
                    if let maximumEntries, entries.count >= maximumEntries {
                        throw SFTPError.entryLimitExceeded(maximumEntries)
                    }
                    let fullPath = (path as NSString).appendingPathComponent(filename)
                    entries.append(SFTPEntry(
                        name: filename,
                        path: fullPath,
                        kind: SFTPFileKind(permissions: attrs.permissions),
                        size: attrs.size ?? 0,
                        modificationDate: attrs.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                        modificationTime: attrs.mtime
                    ))
                }
                guard names.isEmpty else {
                    throw SFTPError.operationFailed("readdir: trailing bytes in name response")
                }
            }

            closeNeeded = false
            try closeHandle(handle, context: "closedir")
            return entries
        }
    }

    func stat(_ path: String) throws -> SFTPAttrs {
        try attributes(path, requestType: 17, context: "stat")
    }

    func lstat(_ path: String) throws -> SFTPAttrs {
        try attributes(path, requestType: 7, context: "lstat")
    }

    private func attributes(_ path: String, requestType: UInt8, context: String) throws -> SFTPAttrs {
        try locked {
            let requestID = sendRequest(type: requestType) { $0.appendSSHString(path) }
            let resp = try readPacket()
            try validateResponseID(resp, expected: requestID, context: context)
            if resp.type == 105 {
                var d = resp.payload; _ = d.readUInt32()
                guard let attrs = d.readSFTPAttrs(), d.isEmpty else {
                    throw SFTPError.operationFailed("\(context): malformed attributes")
                }
                return attrs
            }
            try throwIfStatus(resp, context: "\(context)(\(path))")
            throw SFTPError.operationFailed("\(context) failed")
        }
    }

    func readFile(_ path: String) throws -> Data {
        try locked {
            let openID = sendRequest(type: 3) { buf in
                buf.appendSSHString(path)
                buf.appendUInt32(0x00000001)
                buf.appendUInt32(0)
            }
            let openResp = try readPacket()
            try validateResponseID(openResp, expected: openID, context: "open")
            guard openResp.type == 102 else { try throwIfStatus(openResp, context: "open(\(path))"); throw SFTPError.fileNotFound(path) }
            var od = openResp.payload; _ = od.readUInt32()
            guard let handle = od.readSSHData(), od.isEmpty else { throw SFTPError.operationFailed("open: malformed handle") }
            var closeNeeded = true
            defer {
                if closeNeeded, isRunning { try? closeHandle(handle, context: "close-read") }
            }

            var result = Data()
            var offset: UInt64 = 0
            let chunkSize: UInt32 = 32768
            while true {
                let readID = sendRequest(type: 5) { buf in
                    buf.appendSSHData(handle)
                    buf.appendUInt64(offset)
                    buf.appendUInt32(chunkSize)
                }
                let resp = try readPacket()
                try validateResponseID(resp, expected: readID, context: "read")
                if resp.type == 101 {
                    let status = try statusDetails(resp, context: "read(\(path))")
                    if status.code == 1 { break }
                    throw SFTPError.operationFailed("read(\(path)): \(status.message)")
                }
                guard resp.type == 103 else { throw SFTPError.operationFailed("read: unexpected type \(resp.type)") }
                var dd = resp.payload; _ = dd.readUInt32()
                guard let chunk = dd.readSSHData(), !chunk.isEmpty, dd.isEmpty else {
                    throw SFTPError.operationFailed("read(\(path)): server returned no data before EOF")
                }
                result.append(chunk)
                offset += UInt64(chunk.count)
            }
            closeNeeded = false
            try closeHandle(handle, context: "close-read")
            return result
        }
    }

    @discardableResult
    func downloadFile(
        _ remotePath: String,
        to localURL: URL,
        progress: @escaping @Sendable (UInt64) -> Void
    ) throws -> UInt64 {
        try locked {
            try Task.checkCancellation()
            let openID = sendRequest(type: 3) { buffer in
                buffer.appendSSHString(remotePath)
                buffer.appendUInt32(0x00000001)
                buffer.appendUInt32(0)
            }
            let openResponse = try readPacket()
            try validateResponseID(openResponse, expected: openID, context: "open")
            guard openResponse.type == 102 else {
                try throwIfStatus(openResponse, context: "open(\(remotePath))")
                throw SFTPError.fileNotFound(remotePath)
            }
            var openPayload = openResponse.payload
            _ = openPayload.readUInt32()
            guard let handle = openPayload.readSSHData(), openPayload.isEmpty else {
                throw SFTPError.operationFailed("open: malformed handle")
            }
            var closeNeeded = true
            defer {
                if closeNeeded, isRunning { try? closeHandle(handle, context: "close-read") }
            }

            guard FileManager.default.createFile(
                atPath: localURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: localURL)
            defer { try? output.close() }

            var offset: UInt64 = 0
            let chunkSize: UInt32 = 128 * 1024
            while true {
                try Task.checkCancellation()
                let readID = sendRequest(type: 5) { buffer in
                    buffer.appendSSHData(handle)
                    buffer.appendUInt64(offset)
                    buffer.appendUInt32(chunkSize)
                }
                let response = try readPacket()
                try validateResponseID(response, expected: readID, context: "read")
                if response.type == 101 {
                    let status = try statusDetails(response, context: "read(\(remotePath))")
                    if status.code == 1 { break }
                    throw SFTPError.operationFailed("read(\(remotePath)): \(status.message)")
                }
                guard response.type == 103 else {
                    throw SFTPError.operationFailed("read: unexpected type \(response.type)")
                }
                var dataPayload = response.payload
                _ = dataPayload.readUInt32()
                guard let chunk = dataPayload.readSSHData(), !chunk.isEmpty, dataPayload.isEmpty else {
                    throw SFTPError.operationFailed("read(\(remotePath)): server returned no data before EOF")
                }
                try output.write(contentsOf: chunk)
                offset += UInt64(chunk.count)
                progress(offset)
            }
            closeNeeded = false
            try closeHandle(handle, context: "close-read")
            return offset
        }
    }

    func writeFile(_ path: String, contents: Data) throws {
        try locked {
            let openID = sendRequest(type: 3) { buf in
                buf.appendSSHString(path)
                buf.appendUInt32(0x0000001A)
                buf.appendUInt32(0)
            }
            let openResp = try readPacket()
            try validateResponseID(openResp, expected: openID, context: "open-write")
            guard openResp.type == 102 else { try throwIfStatus(openResp, context: "open-write(\(path))"); throw SFTPError.writeFailed(path, "open failed") }
            var od = openResp.payload; _ = od.readUInt32()
            guard let handle = od.readSSHData(), od.isEmpty else { throw SFTPError.operationFailed("open: malformed handle") }
            var closeNeeded = true
            defer {
                if closeNeeded, isRunning { try? closeHandle(handle, context: "close-write") }
            }

            var offset: UInt64 = 0
            let chunkSize = 32768
            while Int(offset) < contents.count {
                let end = min(Int(offset) + chunkSize, contents.count)
                let chunk = contents[Int(offset)..<end]
                let writeID = sendRequest(type: 6) { buf in
                    buf.appendSSHData(handle)
                    buf.appendUInt64(offset)
                    buf.appendSSHData(Data(chunk))
                }
                let resp = try readPacket()
                try validateResponseID(resp, expected: writeID, context: "write")
                guard resp.type == 101 else {
                    throw SFTPError.writeFailed(path, "unexpected response type \(resp.type)")
                }
                let status = try statusDetails(resp, context: "write(\(path))")
                guard status.code == 0 else {
                    throw SFTPError.writeFailed(path, status.message)
                }
                offset = UInt64(end)
            }

            closeNeeded = false
            try closeHandle(handle, context: "close-write")
        }
    }

    func fileSize(_ path: String) throws -> UInt64? {
        try stat(path).size
    }

    func mkdir(_ path: String) throws {
        try locked {
            let requestID = sendRequest(type: 14) { buf in
                buf.appendSSHString(path)
                buf.appendUInt32(0)
            }
            let resp = try readPacket()
            try validateResponseID(resp, expected: requestID, context: "mkdir")
            try throwIfStatus(resp, context: "mkdir(\(path))", allowOK: true)
        }
    }

    func remove(_ path: String) throws {
        try locked {
            let requestID = sendRequest(type: 13) { $0.appendSSHString(path) }
            let resp = try readPacket()
            try validateResponseID(resp, expected: requestID, context: "remove")
            try throwIfStatus(resp, context: "remove(\(path))", allowOK: true)
        }
    }

    func rename(from oldPath: String, to newPath: String) throws {
        try locked {
            let requestID = sendRequest(type: 18) { buf in
                buf.appendSSHString(oldPath)
                buf.appendSSHString(newPath)
            }
            let resp = try readPacket()
            try validateResponseID(resp, expected: requestID, context: "rename")
            try throwIfStatus(resp, context: "rename", allowOK: true)
        }
    }

    func terminate() {
        lifecycleLock.lock()
        running = false
        let shouldCloseResources = !resourcesClosed
        resourcesClosed = true
        lifecycleLock.unlock()
        guard shouldCloseResources else { return }

        process.terminationHandler = nil
        signal(SIGPIPE, SIG_IGN)
        try? stdinHandle.close()
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < deadline {
                usleep(10_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
    }

    private func setRunning(_ value: Bool) {
        lifecycleLock.lock()
        running = value
        lifecycleLock.unlock()
    }

    deinit { terminate() }

    // MARK: - Wire Protocol

    private struct Packet {
        let type: UInt8
        let payload: Data
    }

    @discardableResult
    private func sendRequest(type: UInt8, _ build: (inout Data) -> Void) -> UInt32 {
        let id = nextRequestId; nextRequestId &+= 1
        send(type: type) { buf in
            buf.appendUInt32(id)
            build(&buf)
        }
        return id
    }

    private func send(type: UInt8, _ build: (inout Data) -> Void) {
        var payload = Data()
        payload.append(type)
        build(&payload)
        var packet = Data()
        packet.appendUInt32(UInt32(payload.count))
        packet.append(payload)
        stdinHandle.write(packet)
    }

    private func readPacket() throws -> Packet {
        let header = try readExact(5) // 4 bytes length + 1 byte type
        let length = header.readUInt32At(0)
        guard length >= 1, length <= 64 * 1024 * 1024 else {
            throw SFTPError.operationFailed("SFTP packet length is invalid: \(length)")
        }
        let type = header[4]
        let payload = length > 1 ? try readExact(Int(length) - 1) : Data()
        return Packet(type: type, payload: payload)
    }

    private func readExact(_ count: Int) throws -> Data {
        var buf = Data(count: count)
        var offset = 0
        while offset < count {
            let n = buf.withUnsafeMutableBytes { ptr in
                read(fd, ptr.baseAddress! + offset, count - offset)
            }
            if n < 0 {
                let err = String(cString: strerror(errno))
                throw SFTPError.operationFailed("SFTP read error: \(err)")
            }
            if n == 0 { throw SFTPError.operationFailed("SFTP connection closed (EOF reading \(count) bytes at offset \(offset))") }
            offset += n
        }
        return buf
    }

    private func closeHandle(_ handle: Data, context: String) throws {
        let closeID = sendRequest(type: 4) { $0.appendSSHData(handle) }
        let response = try readPacket()
        try validateResponseID(response, expected: closeID, context: context)
        let status = try statusDetails(response, context: context)
        guard status.code == 0 else {
            throw SFTPError.operationFailed("\(context): \(status.message)")
        }
    }

    private func validateResponseID(
        _ packet: Packet,
        expected: UInt32,
        context: String
    ) throws {
        var payload = packet.payload
        guard payload.readUInt32() == expected else {
            throw SFTPError.operationFailed("\(context): mismatched SFTP response")
        }
    }

    private func statusDetails(
        _ packet: Packet,
        context: String
    ) throws -> (code: UInt32, message: String) {
        guard packet.type == 101 else {
            throw SFTPError.operationFailed("\(context): expected status response")
        }
        var payload = packet.payload
        _ = payload.readUInt32()
        guard let code = payload.readUInt32(),
              let message = payload.readSSHString(),
              payload.readSSHString() != nil,
              payload.isEmpty else {
            throw SFTPError.operationFailed("\(context): malformed status response")
        }
        return (code, message.isEmpty ? "SFTP status \(code)" : message)
    }

    private func throwIfStatus(_ packet: Packet, context: String, allowOK: Bool = false) throws {
        guard packet.type == 101 else {
            throw SFTPError.operationFailed("\(context): unexpected response type \(packet.type)")
        }
        let status = try statusDetails(packet, context: context)
        if allowOK && status.code == 0 { return }
        switch status.code {
        case 2: throw SFTPError.fileNotFound(context)
        case 3: throw SFTPError.operationFailed("Permission denied: \(context)")
        default: throw SFTPError.operationFailed("\(context): \(status.message)")
        }
    }
}

// MARK: - Binary Helpers

enum SFTPFileKind: Equatable, Sendable {
    case regular
    case directory
    case symbolicLink
    case other

    init(permissions: UInt32?) {
        guard let permissions else {
            self = .other
            return
        }
        switch permissions & 0o170000 {
        case 0o100000: self = .regular
        case 0o040000: self = .directory
        case 0o120000: self = .symbolicLink
        default: self = .other
        }
    }
}

struct SFTPAttrs {
    var size: UInt64?
    var uid: UInt32?
    var gid: UInt32?
    var permissions: UInt32?
    var atime: UInt32?
    var mtime: UInt32?

    var fileKind: SFTPFileKind { SFTPFileKind(permissions: permissions) }
}

private extension Data {
    mutating func appendUInt32(_ v: UInt32) { var v = v.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    mutating func appendUInt64(_ v: UInt64) { var v = v.bigEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    mutating func appendSSHString(_ s: String) {
        let d = Data(s.utf8)
        appendUInt32(UInt32(d.count))
        append(d)
    }
    mutating func appendSSHData(_ d: Data) {
        appendUInt32(UInt32(d.count))
        append(d)
    }

    func readUInt32At(_ offset: Int) -> UInt32 {
        self[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    mutating func readUInt32() -> UInt32? {
        guard count >= 4 else { return nil }
        let v = readUInt32At(0)
        self = self.dropFirst(4).asData
        return v
    }
    mutating func readUInt64() -> UInt64? {
        guard count >= 8 else { return nil }
        let v = self[startIndex..<startIndex+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        self = self.dropFirst(8).asData
        return v
    }
    mutating func readSSHString() -> String? {
        guard let len = readUInt32() else { return nil }
        guard count >= Int(len) else { return nil }
        let bytes = Data(self[startIndex..<startIndex+Int(len)])
        guard let string = String(data: bytes, encoding: .utf8) else { return nil }
        self = self.dropFirst(Int(len)).asData
        return string
    }
    mutating func readSSHData() -> Data? {
        guard let len = readUInt32() else { return nil }
        guard count >= Int(len) else { return nil }
        let d = Data(self[startIndex..<startIndex+Int(len)])
        self = self.dropFirst(Int(len)).asData
        return d
    }
    mutating func readSFTPAttrs() -> SFTPAttrs? {
        guard let flags = readUInt32(), flags & ~UInt32(0x8000000F) == 0 else { return nil }
        var attributes = SFTPAttrs()
        if flags & 0x01 != 0 {
            guard let size = readUInt64() else { return nil }
            attributes.size = size
        }
        if flags & 0x02 != 0 {
            guard let uid = readUInt32(), let gid = readUInt32() else { return nil }
            attributes.uid = uid
            attributes.gid = gid
        }
        if flags & 0x04 != 0 {
            guard let permissions = readUInt32() else { return nil }
            attributes.permissions = permissions
        }
        if flags & 0x08 != 0 {
            guard let atime = readUInt32(), let mtime = readUInt32() else { return nil }
            attributes.atime = atime
            attributes.mtime = mtime
        }
        if flags & 0x80000000 != 0 {
            guard let extensionCount = readUInt32() else { return nil }
            for _ in 0..<extensionCount {
                guard readSSHString() != nil, readSSHData() != nil else { return nil }
            }
        }
        return attributes
    }
}

private extension Data.SubSequence {
    var asData: Data { Data(self) }
}

// MARK: - Types

enum SFTPError: LocalizedError {
    case notConnected
    case timeout(String)
    case fileNotFound(String)
    case writeFailed(String, String)
    case entryLimitExceeded(Int)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "SFTP session is not connected."
        case .timeout(let cmd): return "SFTP command timed out: \(cmd)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .writeFailed(let path, let detail): return "Failed to write \(path): \(detail)"
        case .entryLimitExceeded(let limit): return "SFTP directory entry limit exceeded (\(limit))."
        case .operationFailed(let detail): return "SFTP operation failed: \(detail)"
        }
    }
}

struct SFTPEntry {
    let name: String
    let path: String
    let kind: SFTPFileKind
    let size: UInt64
    let modificationDate: Date?
    let modificationTime: UInt32?

    var isDirectory: Bool { kind == .directory }
}
