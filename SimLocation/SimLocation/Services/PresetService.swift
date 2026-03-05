import Foundation

struct PresetService {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SimLocation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    static func load() -> [Preset] {
        guard let data = try? Data(contentsOf: fileURL),
              let presets = try? JSONDecoder().decode([Preset].self, from: data)
        else { return [] }
        return presets
    }

    static func save(_ presets: [Preset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
