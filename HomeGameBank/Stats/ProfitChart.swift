import SwiftUI
import Charts
import PokerCore

/// All-time chart: running profit after each session. One series, so no legend; the title names it.
/// Touch and drag to read any session.
struct ProfitChart: View {
    let points: [SessionStats.Point]
    @State private var selected: Int?

    private static let short: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d"); return f }()
    private func label(_ d: String) -> String { SessionStats.day(d).map { Self.short.string(from: $0) } ?? d }

    var body: some View {
        let last = points.last?.total ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All-time profit").font(.app(15, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(Money.format(last, signed: true)).font(.app(15, .bold)).monospacedDigit().foregroundStyle(Theme.result(last))
            }
            Chart {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong).lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(points) { p in
                    LineMark(x: .value("Session", p.index), y: .value("Total", p.total))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let i = selected, points.indices.contains(i) {
                    let p = points[i]
                    RuleMark(x: .value("Session", p.index))
                        .foregroundStyle(Theme.text2)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("\(label(p.date)) · \(Money.format(p.profit, signed: true)) · total \(Money.format(p.total, signed: true))")
                                .font(.app(12)).monospacedDigit().foregroundStyle(Theme.text)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.fill2, in: RoundedRectangle(cornerRadius: 8))
                        }
                    PointMark(x: .value("Session", p.index), y: .value("Total", p.total))
                        .foregroundStyle(Theme.accent).symbolSize(70)
                } else if let p = points.last {
                    PointMark(x: .value("Session", p.index), y: .value("Total", p.total))
                        .foregroundStyle(Theme.accent).symbolSize(50)
                }
            }
            .chartXSelection(value: $selected)
            .chartXScale(domain: 0...max(1, points.count - 1))
            .chartXAxis {
                AxisMarks(values: [0, max(0, points.count - 1)]) { v in
                    AxisValueLabel(anchor: v.index == 0 ? .topLeading : .topTrailing) {
                        if let i = v.as(Int.self), points.indices.contains(i) { Text(label(points[i].date)) }
                    }
                    .foregroundStyle(Theme.text2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(Money.short(d)) }
                    }
                    .foregroundStyle(Theme.text2)
                }
            }
            .frame(height: 200)
            .padding(.top, 18)
            .accessibilityLabel("Running profit over \(points.count) sessions, now \(Money.format(last, signed: true))")
        }
        .padding(.vertical, 8)
    }
}
