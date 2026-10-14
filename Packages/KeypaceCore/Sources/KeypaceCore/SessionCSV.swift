import Foundation

/// CSV export of stored sessions, one row per session.
public enum SessionCSV {
    public static let header = "start,end,app,keyboard,input_source,characters,backspaces,keystrokes,duration_seconds,wpm,correction_rate"

    public static func make(_ sessions: [SessionRecord]) -> String {
        let iso = ISO8601DateFormatter()
        let rows = sessions.map { s in
            let totals = s.totals
            return [
                iso.string(from: s.start),
                iso.string(from: s.end),
                escape(s.appID),
                escape(s.keyboardID ?? ""),
                escape(s.inputSourceID ?? ""),
                String(s.characters),
                String(s.backspaces),
                String(s.keystrokes),
                String(format: "%.1f", totals.duration),
                totals.wpm.map { String(format: "%.1f", $0) } ?? "",
                totals.correctionRate.map { String(format: "%.4f", $0) } ?? "",
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
