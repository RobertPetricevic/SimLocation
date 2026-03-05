import Foundation

struct Simulator: Identifiable, Hashable {
    let id: String // udid
    let name: String
    let runtime: String

    var displayName: String {
        let cleaned = runtime
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
        return "\(name) — \(cleaned)"
    }
}
