import Foundation

enum DevicePlatform: Hashable {
    case ios
    case android
}

struct Simulator: Identifiable, Hashable {
    let id: String // udid or adb serial
    let name: String
    let runtime: String
    let platform: DevicePlatform

    var displayName: String {
        switch platform {
        case .ios:
            let cleaned = runtime
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            return "\(name) — \(cleaned)"
        case .android:
            return "\(name) — Android \(runtime)"
        }
    }
}
