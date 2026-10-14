import Foundation

enum Format {
    static func wpm(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "–"
    }

    static func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "–"
    }

    /// "1h 12m", "18 min", "45 s".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 { return "\(total / 3600)h \(String(format: "%02d", total % 3600 / 60))m" }
        if total >= 60 { return "\(total / 60) min" }
        return "\(total) s"
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    static func signed(_ value: Double, decimals: Int = 0) -> String {
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        let body = abs(rounded).formatted(.number.precision(.fractionLength(decimals)))
        return rounded > 0 ? "+\(body)" : rounded < 0 ? "−\(body)" : body
    }
}
