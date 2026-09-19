import SwiftUI
import Charts
import MeterCore

enum Palette {
    static let green = Color(red: 0.12, green: 0.57, blue: 0.43)
    static let amber = Color(red: 0.77, green: 0.48, blue: 0.13)
    static let red = Color(red: 0.80, green: 0.30, blue: 0.28)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.07)
    static func tier(_ tier: Int) -> Color { tier == 1 ? green : (tier == 2 ? amber : red) }
}

extension Double {
    func meter(_ digits: Int = 1) -> String { formatted(.number.precision(.fractionLength(digits)).grouping(.never)) }
    var yuan: String { "¥" + meter(2) }
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Palette.green, Color(red: 0.08, green: 0.37, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.3))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Palette.green
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
    }
}

struct QuotaRing: View {
    let analysis: UsageAnalysis
    var size: CGFloat = 126
    var body: some View {
        let color = analysis.tariff.mode == .combined ? Palette.green : Palette.tier(analysis.tier)
        let highestTier = analysis.tariff.mode != .combined && analysis.tier == 3
        ZStack {
            Circle().stroke(color.opacity(highestTier ? 0.65 : 0.10), lineWidth: 9)
            Circle().trim(from: 0, to: analysis.remainingFraction)
                .stroke(Palette.tier(analysis.tier), style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
            Circle().inset(by: 13).stroke(Color.secondary.opacity(0.10), lineWidth: 4)
            Circle().inset(by: 13).trim(from: 0, to: analysis.timeRemainingFraction)
                .stroke(Color.secondary.opacity(0.40), style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                if analysis.tariff.mode == .combined {
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.24)).foregroundStyle(Palette.green)
                    Text("合表计费").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if analysis.tier == 3 {
                    Text("第三档").font(.system(size: size * 0.18, weight: .semibold))
                    Text("无下一档").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text((analysis.remainingFraction * 100).meter(0) + "%").font(.system(size: size * 0.23, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("档位额度剩余").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }.frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(highestTier ? "已进入第三档，无下一档" : "阶梯剩余额度 \((analysis.remainingFraction * 100).meter(0))%，日历剩余 \((analysis.timeRemainingFraction * 100).meter(0))%")
    }
}

struct TierProgress: View {
    let snapshot: UsageSnapshot
    let tariff: Tariff
    var compact = false
    var body: some View {
        let limits = tariff.limits(for: snapshot.month)
        let buckets = tariff.buckets(total: snapshot.total, month: snapshot.month)
        HStack(spacing: 8) {
            segment(fill: buckets[0] / limits.0, color: Palette.green, label: "一档 ≤ \(limits.0.meter(0))")
            segment(fill: buckets[1] / (limits.1 - limits.0), color: Palette.amber, label: "二档 ≤ \(limits.1.meter(0))")
            segment(fill: buckets[2] > 0 ? 1 : 0, color: Palette.red, label: "三档 > \(limits.1.meter(0))")
        }
    }
    func segment(fill: Double, color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.12))
                    .overlay(alignment: .leading) { Capsule().fill(color).frame(width: geometry.size.width * max(0, min(1, fill))) }
            }.frame(height: compact ? 7 : 9)
            Text(label).font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct UsageChart: View {
    let snapshot: UsageSnapshot
    var compact = false
    @State private var hoverDay: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(compact ? "每日用电" : "用电的每一天").font(.system(size: compact ? 12 : 16, weight: .semibold))
                Spacer()
                if let day = hoverDay, let value = snapshot.daily.first(where: { $0.day == day }) {
                    Text("\(snapshot.month.month)/\(day)  ·  \(value.kWh.meter(2)) 度\(value.estimated ? "（估抄）" : "")").font(.system(size: 11)).foregroundStyle(Palette.green)
                } else {
                    Text(compact ? "度 / 日" : "悬停查看每日用电").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(snapshot.daily) { day in
                    BarMark(x: .value("日期", snapshot.month.date(day: day.day), unit: .day), y: .value("用电量", day.kWh))
                        .foregroundStyle(day.day == hoverDay ? Palette.green : Palette.green.opacity(compact ? 0.65 : 0.8))
                        .cornerRadius(compact ? 2 : 3)
                        .opacity(hoverDay == nil || hoverDay == day.day ? 1 : 0.40)
                        .accessibilityLabel("\(snapshot.month.month) 月 \(day.day) 日")
                        .accessibilityValue("\(day.kWh.meter(2)) 度")
                }
            }
            .chartXScale(domain: snapshot.month.start...snapshot.month.offset(1).start)
            .chartXAxis {
                AxisMarks(values: [1, 5, 10, 15, 20, 25, 30].filter { $0 <= snapshot.month.days }.map { snapshot.month.date(day: $0) }) { value in
                    AxisValueLabel(format: .dateTime.day(), centered: false).font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 2 : 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { return }
                                let x = location.x - geometry[frame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    let day = ShenzhenTime.calendar.component(.day, from: date)
                                    hoverDay = snapshot.daily.contains(where: { $0.day == day }) ? day : nil
                                }
                            case .ended: hoverDay = nil
                            }
                        }
                }
            }
            .frame(height: compact ? 80 : 176)
            if !compact {
                HStack(spacing: 6) {
                    Circle().fill(Palette.green).frame(width: 5, height: 5)
                    Text("已发布 \(snapshot.daily.count) 天数据；空白日期表示暂无数据")
                    Spacer()
                    if snapshot.daily.contains(where: \.estimated) { Text("包含估抄数据") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyMeterView: View {
    @ObservedObject var store: MeterStore
    let showSettings: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 60)
            Text(store.isConfigured ? "等待这一月的电量" : "让每一度电，心中有数")
                .font(.system(size: 22, weight: .semibold))
            Text(store.selectedError ?? (store.isConfigured ? "正在向南网查询每日用电数据。" : "填入南网 Token 和电表信息，即可查看阶梯额度与用电趋势。"))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 350)
            if store.loading.contains(store.selectedMonth.key) { ProgressView().controlSize(.small) }
            Button(store.isConfigured && !store.needsToken ? "重新查询" : "配置我的电表") {
                if store.isConfigured && !store.needsToken { store.refreshSelected() } else { showSettings() }
            }.buttonStyle(.borderedProminent).tint(Palette.green)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
}

struct StatusBanner: View {
    let message: String
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.amber)
            Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action { Button("设置", action: action).buttonStyle(.link).font(.system(size: 11)) }
        }.padding(12).background(Palette.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}
