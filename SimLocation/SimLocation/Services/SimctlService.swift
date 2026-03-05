import Foundation

enum SimctlError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        }
    }
}

actor SimctlService {

    private func run(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { _ in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errStr = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    let msg = errStr.isEmpty ? "Exit code \(process.terminationStatus)" : errStr
                    continuation.resume(throwing: SimctlError.commandFailed(msg))
                } else {
                    continuation.resume(returning: outStr)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Commands

    func listBootedDevices() async throws -> [Simulator] {
        let output = try await run(["list", "devices", "booted", "-j"])
        guard let data = output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesDict = json["devices"] as? [String: [[String: Any]]]
        else {
            return []
        }

        var simulators: [Simulator] = []
        for (runtime, devices) in devicesDict {
            for device in devices {
                if let state = device["state"] as? String, state == "Booted",
                   let udid = device["udid"] as? String,
                   let name = device["name"] as? String {
                    simulators.append(Simulator(id: udid, name: name, runtime: runtime))
                }
            }
        }
        return simulators.sorted { $0.name < $1.name }
    }

    func setLocation(udid: String, latitude: Double, longitude: Double) async throws {
        _ = try await run(["location", udid, "set", "\(latitude),\(longitude)"])
    }

    func startRoute(udid: String, waypoints: [Waypoint], speed: Double, interval: Double?) async throws {
        var args = ["location", udid, "start", "--speed=\(speed)"]
        if let interval {
            args.append("--interval=\(interval)")
        }
        for wp in waypoints {
            args.append("\(wp.latitude),\(wp.longitude)")
        }
        _ = try await run(args)
    }

    func clearLocation(udid: String) async throws {
        _ = try await run(["location", udid, "clear"])
    }

    func runScenario(udid: String, scenario: String) async throws {
        _ = try await run(["location", udid, "run", scenario])
    }

    func listScenarios(udid: String) async throws -> String {
        try await run(["location", udid, "list"])
    }
}
