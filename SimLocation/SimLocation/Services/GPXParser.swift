import Foundation

struct GPXParser {

    struct GPXResult {
        var name: String?
        var waypoints: [Waypoint]
    }

    static func parse(data: Data) throws -> GPXResult {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw GPXError.invalidFormat
        }
        guard !delegate.points.isEmpty else {
            throw GPXError.noPoints
        }
        return GPXResult(name: delegate.trackName, waypoints: delegate.points)
    }

    enum GPXError: LocalizedError {
        case invalidFormat
        case noPoints

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Invalid GPX file"
            case .noPoints: return "GPX file contains no track points or waypoints"
            }
        }
    }
}

private class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [Waypoint] = []
    var trackName: String?

    private var currentElement = ""
    private var currentText = ""
    // Track whether we're inside a <name> that belongs to the track/route (not a waypoint name)
    private var insideTrack = false
    private var insideRoute = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "trk":
            insideTrack = true
        case "rte":
            insideRoute = true
        case "trkpt", "rtept", "wpt":
            if let latStr = attributeDict["lat"], let lonStr = attributeDict["lon"],
               let lat = Double(latStr), let lon = Double(lonStr) {
                points.append(Waypoint(latitude: lat, longitude: lon))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "name" && trackName == nil && (insideTrack || insideRoute) {
            let name = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                trackName = name
            }
        }
        if elementName == "trk" { insideTrack = false }
        if elementName == "rte" { insideRoute = false }
        currentElement = ""
    }
}
