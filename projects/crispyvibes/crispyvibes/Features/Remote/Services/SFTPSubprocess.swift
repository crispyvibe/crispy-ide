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
    private var nextRequestId: UInt32 = 1
    private(set) var isRunning = false

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
        isRunning = true
        process.terminationHandler = { [weak self] _ in self?.isRunning = false }

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
        sendRequest(type: 16) { $0.appendSSHString(path) } // SSH_FXP_REALPATH
        let resp = try readPacket()
        if resp.type == 104 { // SSH_FXP_NAME
            var d = resp.payload; _ = d.readUInt32() // requestId
            let count = d.readUInt32() ?? 0
            if count > 0, let name = d.readSSHString() { return name }
        }
        try throwIfStatus(resp, context: "realpath(\(path))")
        throw SFTPError.operationFailed("realpath failed")
    }

    func listDirectory(_ path: String) throws -> [SFTPEntry] {
        try locked {
        // OPENDIR
        sendRequest(type: 11) { $0.appendSSHString(path) }
        let openResp = try readPacket()
        guard openResp.type == 102 else { try throwIfStatus(openResp, context: "opendir"); throw SFTPError.operationFailed("opendir failed") }
        var od = openResp.payload; _ = od.readUInt32()
        guard let handle = od.readSSHData() else { throw SFTPError.operationFailed("opendir: no handle") }

        // READDIR loop
        var entries = [SFTPEntry]()
        while true {
            _ = sendRequest(type: 12) { $0.appendSSHData(handle) } // SSH_FXP_READDIR
            let resp = try readPacket()
            if resp.type == 101 { // SSH_FXP_STATUS (EOF)
                var sd = resp.payload; _ = sd.readUInt32()
                let code = sd.readUInt32() ?? 4
                if code == 1 { break } // SSH_FX_EOF
                let msg = sd.readSSHString() ?? "unknown"
                throw SFTPError.operationFailed("readdir: \(msg)")
            }
            guard resp.type == 104 else { throw SFTPError.operationFailed("readdir: unexpected type \(resp.type)") }
            var nd = resp.payload; _ = nd.readUInt32()
            let count = nd.readUInt32() ?? 0
            for _ in 0..<count {
                guard let filename = nd.readSSHString(),
                      let _ = nd.readSSHString(), // longname
                      let attrs = nd.readSFTPAttrs() else { break }
                guard filename != "." && filename != ".." else { continue }
                let fullPath = (path as NSString).appendingPathComponent(filename)
                let isDir = attrs.permissions.map { ($0 & 0o170000) == 0o040000 } ?? false
                entries.append(SFTPEntry(
                    name: filename, path: fullPath, isDirectory: isDir,
                    size: attrs.size ?? 0,
                    modificationDate: attrs.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ))
            }
        }

        // CLOSE
        _ = sendRequest(type: 4) { $0.appendSSHData(handle) }
        _ = try? readPacket()
        return entries
        }
    }

    func stat(_ path: String) throws -> SFTPAttrs {
        try locked {
            _ = sendRequest(type: 17) { $0.appendSSHString(path) }
            let resp = try readPacket()
            if resp.type == 105 {
                var d = resp.payload; _ = d.readUInt32()
                if let attrs = d.readSFTPAttrs() { return attrs }
            }
            try throwIfStatus(resp, context: "stat(\(path))")
            throw SFTPError.operationFailed("stat failed")
        }
    }

    func readFile(_ path: String) throws -> Data {
        try locked {
            sendRequest(type: 3) { buf in
                buf.appendSSHString(path)
                buf.appendUInt32(0x00000001)
                buf.appendUInt32(0)
            }
            let openResp = try readPacket()
            guard openResp.type == 102 else { try throwIfStatus(openResp, context: "open(\(path))"); throw SFTPError.fileNotFound(path) }
            var od = openResp.payload; _ = od.readUInt32()
            guard let handle = od.readSSHData() else { throw SFTPError.operationFailed("open: no handle") }

            var result = Data()
            var offset: UInt64 = 0
            let chunkSize: UInt32 = 32768
            while true {
                _ = sendRequest(type: 5) { buf in
                    buf.appendSSHData(handle)
                    buf.appendUInt64(offset)
                    buf.appendUInt32(chunkSize)
                }
                let resp = try readPacket()
                if resp.type == 101 { break }
                guard resp.type == 103 else { throw SFTPError.operationFailed("read: unexpected type \(resp.type)") }
                var dd = resp.payload; _ = dd.readUInt32()
                guard let chunk = dd.readSSHData() else { break }
                result.append(chunk)
                offset += UInt64(chunk.count)
                if chunk.count < chunkSize { break }
            }

            _ = sendRequest(type: 4) { $0.appendSSHData(handle) }
            _ = try? readPacket()
            return result
        }
    }

    func writeFile(_ path: String, contents: Data) throws {
        try locked {
            sendRequest(type: 3) { buf in
                buf.appendSSHString(path)
                buf.appendUInt32(0x0000001A)
                buf.appendUInt32(0)
            }
            let openResp = try readPacket()
            guard openResp.type == 102 else { try throwIfStatus(openResp, context: "open-write(\(path))"); throw SFTPError.writeFailed(path, "open failed") }
            var od = openResp.payload; _ = od.readUInt32()
            guard let handle = od.readSSHData() else { throw SFTPError.operationFailed("open: no handle") }

            var offset: UInt64 = 0
            let chunkSize = 32768
            while Int(offset) < contents.count {
                let end = min(Int(offset) + chunkSize, contents.count)
                let chunk = contents[Int(offset)..<end]
                _ = sendRequest(type: 6) { buf in
                    buf.appendSSHData(handle)
                    buf.appendUInt64(offset)
                    buf.appendSSHData(Data(chunk))
                }
                let resp = try readPacket()
                if resp.type == 101 {
                    var sd = resp.payload; _ = sd.readUInt32()
                    let code = sd.readUInt32() ?? 4
                    if code != 0 {
                        let msg = sd.readSSHString() ?? "write failed"
                        throw SFTPError.writeFailed(path, msg)
                    }
                }
                offset = UInt64(end)
            }

            _ = sendRequest(type: 4) { $0.appendSSHData(handle) }
            _ = try? readPacket()
        }
    }

    func fileSize(_ path: String) throws -> UInt64? {
        try stat(path).size
    }

    func mkdir(_ path: String) throws {
        try locked {
            _ = sendRequest(type: 14) { buf in
                buf.appendSSHString(path)
                buf.appendUInt32(0)
            }
            let resp = try readPacket()
            try throwIfStatus(resp, context: "mkdir(\(path))", allowOK: true)
        }
    }

    func remove(_ path: String) throws {
        try locked {
            _ = sendRequest(type: 13) { $0.appendSSHString(path) }
            let resp = try readPacket()
            try throwIfStatus(resp, context: "remove(\(path))", allowOK: true)
        }
    }

    func rename(from oldPath: String, to newPath: String) throws {
        try locked {
            _ = sendRequest(type: 18) { buf in
                buf.appendSSHString(oldPath)
                buf.appendSSHString(newPath)
            }
            let resp = try readPacket()
            try throwIfStatus(resp, context: "rename", allowOK: true)
        }
    }

    func terminate() {
        isRunning = false
        process.terminationHandler = nil
        signal(SIGPIPE, SIG_IGN)
        try? stdinHandle.close()
        if process.isRunning { process.terminate() }
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

    private func throwIfStatus(_ packet: Packet, context: String, allowOK: Bool = false) throws {
        guard packet.type == 101 else { return } // SSH_FXP_STATUS
        var d = packet.payload; _ = d.readUInt32()
        let code = d.readUInt32() ?? 4
        if allowOK && code == 0 { return }
        let msg = d.readSSHString() ?? "unknown error"
        switch code {
        case 2: throw SFTPError.fileNotFound(context)
        case 3: throw SFTPError.operationFailed("Permission denied: \(context)")
        default: throw SFTPError.operationFailed("\(context): \(msg)")
        }
    }
}

// MARK: - Binary Helpers

struct SFTPAttrs {
    var size: UInt64?
    var uid: UInt32?
    var gid: UInt32?
    var permissions: UInt32?
    var atime: UInt32?
    var mtime: UInt32?
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
        let bytes = self[startIndex..<startIndex+Int(len)]
        // Use lossy UTF-8 decoding so a single filename with non-UTF-8 bytes
        // (legal on POSIX) cannot abort an SFTP READDIR loop and silently drop
        // the rest of the directory entries. Invalid sequences become U+FFFD;
        // the byte stream is still consumed correctly so subsequent fields
        // remain in sync.
        let s = String(decoding: bytes, as: UTF8.self)
        self = self.dropFirst(Int(len)).asData
        return s
    }
    mutating func readSSHData() -> Data? {
        guard let len = readUInt32() else { return nil }
        guard count >= Int(len) else { return nil }
        let d = Data(self[startIndex..<startIndex+Int(len)])
        self = self.dropFirst(Int(len)).asData
        return d
    }
    mutating func readSFTPAttrs() -> SFTPAttrs? {
        guard let flags = readUInt32() else { return nil }
        var a = SFTPAttrs()
        if flags & 0x01 != 0 { a.size = readUInt64() }
        if flags & 0x02 != 0 { a.uid = readUInt32(); a.gid = readUInt32() }
        if flags & 0x04 != 0 { a.permissions = readUInt32() }
        if flags & 0x08 != 0 { a.atime = readUInt32(); a.mtime = readUInt32() }
        if flags & 0x80000000 != 0 {
            if let extCount = readUInt32() {
                for _ in 0..<extCount { _ = readSSHString(); _ = readSSHString() }
            }
        }
        return a
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
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "SFTP session is not connected."
        case .timeout(let cmd): return "SFTP command timed out: \(cmd)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .writeFailed(let path, let detail): return "Failed to write \(path): \(detail)"
        case .operationFailed(let detail): return "SFTP operation failed: \(detail)"
        }
    }
}

struct SFTPEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modificationDate: Date?
}
