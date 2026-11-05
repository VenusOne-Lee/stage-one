import Foundation
import StageOneCore

/// SO-100: the app side of the `stage` CLI. A Unix domain socket at `IPC.socketPath`
/// (mode 0600, so only this user can talk to it). One request per connection: the CLI
/// writes a JSON `Command` and a newline, the app answers with a JSON `CommandReply`.
final class CommandServer: @unchecked Sendable {
    static let shared = CommandServer()

    private let lock = NSLock()
    private var listener: Int32 = -1

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard listener < 0 else { return }
        let path = IPC.socketPath
        try? FileManager.default.createDirectory(at: IPC.supportDirectory, withIntermediateDirectories: true)
        unlink(path)

        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(s); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, len) }
        }
        guard bound == 0, listen(s, 8) == 0 else { close(s); return }
        chmod(path, 0o600)
        listener = s
        Thread.detachNewThread { [self] in acceptLoop(s) }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard listener >= 0 else { return }
        close(listener)
        listener = -1
        unlink(IPC.socketPath)
    }

    private func acceptLoop(_ s: Int32) {
        while true {
            let client = accept(s, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // listener closed
            }
            serve(client)
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 1 << 20 {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if buf[..<n].contains(10) { break }
        }
        if let nl = data.firstIndex(of: 10) { data = data[..<nl] }

        let reply: CommandReply
        if let command = try? IPC.decode(Command.self, Data(data)) {
            reply = DispatchQueue.main.sync { MainActor.assumeIsolated { CommandRouter.run(command) } }
        } else {
            reply = .fail("Stage One couldn't read that request. Is the CLI the same version as the app?")
        }
        guard var out = try? IPC.encode(reply) else { return }
        out.append(10)
        out.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(client, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }
}
