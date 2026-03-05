import Foundation
import CoreLocation

enum AdbError: LocalizedError {
    case commandFailed(String)
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .notAvailable: return "adb is not installed"
        }
    }
}

actor AdbService {

    private var adbPath: String?

    // MARK: - Path Resolution

    private func resolveAdbPath() async -> String? {
        if let cached = adbPath { return cached }

        // Try `which adb` first
        if let path = try? await runRaw(executableURL: "/usr/bin/env", arguments: ["which", "adb"]),
           !path.isEmpty {
            adbPath = path
            return path
        }

        // Common install locations
        let candidates = [
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/usr/local/bin/adb",
            "/opt/homebrew/bin/adb",
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                adbPath = candidate
                return candidate
            }
        }

        return nil
    }

    func isAvailable() async -> Bool {
        await resolveAdbPath() != nil
    }

    // MARK: - Process Execution

    private func runRaw(executableURL: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executableURL)
            process.arguments = arguments

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
                    continuation.resume(throwing: AdbError.commandFailed(msg))
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

    private func run(_ arguments: [String]) async throws -> String {
        guard let path = await resolveAdbPath() else {
            throw AdbError.notAvailable
        }
        return try await runRaw(executableURL: path, arguments: arguments)
    }

    // MARK: - Device Discovery

    func listRunningEmulators() async throws -> [Simulator] {
        let output = try await run(["devices"])

        // Parse lines like "emulator-5554	device"
        var emulators: [Simulator] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("\tdevice"),
                  trimmed.hasPrefix("emulator-") else { continue }
            let serial = String(trimmed.split(separator: "\t").first ?? "")
            guard !serial.isEmpty else { continue }

            let name = (try? await getEmulatorName(serial: serial)) ?? serial
            let version = (try? await getAndroidVersion(serial: serial)) ?? "?"

            emulators.append(Simulator(id: serial, name: name, runtime: version, platform: .android))
        }
        return emulators.sorted { $0.name < $1.name }
    }

    private func getEmulatorName(serial: String) async throws -> String {
        let output = try await run(["-s", serial, "emu", "avd", "name"])
        // First line is the AVD name, second line is "OK"
        let name = output.components(separatedBy: "\n").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? serial
        return name.isEmpty ? serial : name
    }

    private func getAndroidVersion(serial: String) async throws -> String {
        try await run(["-s", serial, "shell", "getprop", "ro.build.version.release"])
    }

    // MARK: - Location Commands

    /// Note: adb geo fix takes longitude first, then latitude
    func setLocation(serial: String, latitude: Double, longitude: Double) async throws {
        _ = try await run(["-s", serial, "emu", "geo", "fix", "\(longitude)", "\(latitude)"])
    }

    func clearLocation(serial: String) async throws {
        _ = try await run(["-s", serial, "emu", "geo", "fix", "0", "0"])
    }

    // MARK: - Route Simulation

    /// Simulates a route by sending sequential geo fix commands.
    /// Interpolates between waypoints for smooth movement.
    /// This is a long-running method that should be called from a Task and supports cancellation.
    func simulateRoute(serial: String, waypoints: [Waypoint], speed: Double) async throws {
        guard waypoints.count >= 2 else { return }

        let interpolated = interpolateWaypoints(waypoints, intervalMeters: 10.0)

        for i in 0..<interpolated.count {
            try Task.checkCancellation()

            let point = interpolated[i]
            try await setLocation(serial: serial, latitude: point.latitude, longitude: point.longitude)

            // Calculate delay to next point based on distance and speed
            if i < interpolated.count - 1 {
                let next = interpolated[i + 1]
                let from = CLLocation(latitude: point.latitude, longitude: point.longitude)
                let to = CLLocation(latitude: next.latitude, longitude: next.longitude)
                let distance = from.distance(from: to)
                let delay = distance / max(speed, 0.1)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Interpolates waypoints to produce points approximately every `intervalMeters` meters.
    private func interpolateWaypoints(_ waypoints: [Waypoint], intervalMeters: Double) -> [(latitude: Double, longitude: Double)] {
        var result: [(latitude: Double, longitude: Double)] = []

        for i in 0..<(waypoints.count - 1) {
            let start = CLLocation(latitude: waypoints[i].latitude, longitude: waypoints[i].longitude)
            let end = CLLocation(latitude: waypoints[i + 1].latitude, longitude: waypoints[i + 1].longitude)
            let distance = start.distance(from: end)

            let steps = max(Int(distance / intervalMeters), 1)
            for step in 0..<steps {
                let fraction = Double(step) / Double(steps)
                let lat = waypoints[i].latitude + fraction * (waypoints[i + 1].latitude - waypoints[i].latitude)
                let lng = waypoints[i].longitude + fraction * (waypoints[i + 1].longitude - waypoints[i].longitude)
                result.append((latitude: lat, longitude: lng))
            }
        }

        // Add the final point
        if let last = waypoints.last {
            result.append((latitude: last.latitude, longitude: last.longitude))
        }

        return result
    }
}
