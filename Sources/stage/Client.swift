import ArgumentParser
import Foundation
import StageOneCore

/// Sends one `Command` to the running app over its Unix socket and returns the reply.
enum Client {
    struct NotRunning: Error, CustomStringConvertible {
        var description: String { "Stage One isn't running. Open it with: open -a \"Stage One\"" }
    }

    static func send(_ command: Command) throws -> CommandReply {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { throw NotRunning() }
        defer { close(s) }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(IPC.socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw NotRunning() }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, len) }
        }
        guard ok == 0 else { throw NotRunning() }

        var out = try IPC.encode(command)
        out.append(10)
        try out.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(s, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { throw NotRunning() }
                off += n
            }
        }
        shutdown(s, SHUT_WR)

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(s, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        guard !data.isEmpty else { throw ValidationError("Stage One didn't answer. Try again in a moment.") }
        return try IPC.decode(CommandReply.self, data)
    }
}

/// Flags every command shares.
struct Output: ParsableArguments {
    @Flag(name: .long, help: "Print the raw JSON reply.")
    var json = false
}

/// Sends a command and prints the reply; exits 1 when the app reports a failure.
func runCommand(_ command: Command, _ output: Output, show: (CommandReply) -> Void = { print($0.message) }) throws {
    let reply = try Client.send(command)
    if output.json {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try e.encode(reply), as: UTF8.self))
    } else if reply.ok {
        show(reply)
    } else {
        FileHandle.standardError.write(Data((reply.message + "\n").utf8))
    }
    if !reply.ok { throw ExitCode.failure }
}
