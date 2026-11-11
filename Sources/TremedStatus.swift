import Foundation

/// Items of the Central de Operações that need attention.
struct CentralHealth {
    let failing: [String]
    let warning: [String]

    var isHealthy: Bool { failing.isEmpty && warning.isEmpty }
}

/// TREMED's own health signals: the Central de Operações (items in `falha` or
/// `atencao`, read-only over `ssh tremed`) and whether João's notebook, where
/// the tremed-postgres and bling MCPs run, answers on the local network.
enum TremedStatus {
    static let centralURL = URL(string: "https://app.tremed.com.br/central")!
    /// How often each check runs.
    static let centralInterval: TimeInterval = 5 * 60
    static let notebookInterval: TimeInterval = 60

    private static let sshHost = "tremed"
    private static let notebookHost = "notebook"
    private static let notebookPort = "22"
    private static let centralQuery =
        "select saude, slug from operacoes.v_itens where saude in ('falha','atencao') order by 1, 2;"
    /// Runs psql inside the Postgres container; the SQL arrives on stdin.
    private static let remotePsql = "docker exec -i $(docker ps -qf name=pgvector_pgvector | head -1) "
        + "sh -c 'psql -U \"$POSTGRES_USER\" -d base-claude -At -v ON_ERROR_STOP=1'"

    /// nil when the server can't be reached or the query fails.
    static func central() -> CentralHealth? {
        let args = ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", sshHost, remotePsql]
        guard let output = run("/usr/bin/ssh", args, stdin: centralQuery, timeout: 25) else { return nil }
        var failing: [String] = []
        var warning: [String] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { continue }
            if fields[0] == "falha" { failing.append(fields[1]) }
            if fields[0] == "atencao" { warning.append(fields[1]) }
        }
        return CentralHealth(failing: failing, warning: warning)
    }

    /// Whether the notebook's SSH port answers within a few seconds.
    static func notebookOnline() -> Bool {
        guard let host = notebookAddress() else { return false }
        return run("/usr/bin/nc", ["-z", "-G", "3", host, notebookPort], timeout: 6) != nil
    }

    /// The notebook's address from ~/.ssh/config (its IP comes from DHCP, so
    /// it isn't hard-coded here).
    private static func notebookAddress() -> String? {
        guard let config = run("/usr/bin/ssh", ["-G", notebookHost], timeout: 5) else { return nil }
        return config.split(separator: "\n")
            .first { $0.hasPrefix("hostname ") }
            .map { String($0.dropFirst("hostname ".count)) }
    }

    /// Runs a command and returns its stdout, or nil on a non-zero exit,
    /// a launch failure or a timeout.
    private static func run(_ executable: String, _ arguments: [String], stdin: String? = nil,
                            timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        do {
            try process.run()
        } catch {
            NSLog("ClaudeTouchBar: can't run \(executable): \(error)")
            return nil
        }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        // Read while it runs, so a full pipe can't stall the process.
        var data = Data()
        let reader = DispatchQueue(label: "TremedStatus.read")
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning {
            process.terminate()
            NSLog("ClaudeTouchBar: \(executable) timed out")
            return nil
        }
        readDone.wait()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
