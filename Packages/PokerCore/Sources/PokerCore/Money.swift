import Foundation

/// Dollar formatting that matches the web app: "$1,234", "$12.50", "+$40", "−$27".
public enum Money {
    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()
    private static let cents: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    public static func format(_ value: Double, signed: Bool = false) -> String {
        let rounded = (value * 100).rounded() / 100
        let a = abs(rounded)
        let isWhole = a == a.rounded()
        let body = (isWhole ? whole : cents).string(from: NSNumber(value: a)) ?? "\(a)"
        let sign = rounded < 0 ? "−" : (signed && rounded > 0 ? "+" : "")
        return "\(sign)$\(body)"
    }

    /// Axis labels: "$500", "−$1.5k".
    public static func short(_ value: Double) -> String {
        let a = abs(value), s = value < 0 ? "−" : ""
        if a >= 1000 {
            let k = a / 1000
            return "\(s)$\(k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k))k"
        }
        return "\(s)$\(Int(a.rounded()))"
    }
}
