import SwiftUI
import MeterCore

struct PopoverView: View {
    @ObservedObject var store: MeterStore
    let showDashboard: () -> Void
    let showSettings: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("szElectricityMeter").font(.system(size: 13, weight: .semibold))
                    Text(store.currentMonth.title + (store.isDemo ? " · 演示数据" : "")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: store.refreshCurrent) { Image(systemName: "arrow.clockwise") }
                    .disabled(store.loading.contains(store.currentMonth.key)).help("刷新本月数据")
                Button(action: showSettings) { Image(systemName: "gearshape") }.help("设置")
            }.buttonStyle(.borderless).padding(18)
            Divider()
            ScrollView {
                if let snapshot = store.current, let analysis = store.currentAnalysis {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = store.errors[store.currentMonth.key] { StatusBanner(message: "\(error) 显示上次成功数据。", action: showSettings) }
                        if snapshot.isDelayed() { StatusBanner(message: "南网数据延迟，预测已暂停。") }
                        HStack(spacing: 20) {
                            QuotaRing(analysis: analysis, size: 100)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("本月已用").font(.system(size: 11)).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(snapshot.total.meter(2)).font(.system(size: 31, weight: .semibold, design: .rounded)).monospacedDigit()
                                    Text("度").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Pill(text: store.configuration.tariff.mode == .combined ? "合表电价" : "第 \(analysis.tier) 档 · \(snapshot.month.isSummer ? "夏季" : "非夏季")", color: Palette.tier(analysis.tier))
                            }
                        }.padding(.vertical, 6)
                        if let remaining = analysis.remaining {
                            HStack {
                                Text("距第 \(analysis.tier + 1) 档").foregroundStyle(.secondary)
                                Spacer()
                                Text("还剩 \(remaining.meter(2)) 度").fontWeight(.semibold).foregroundStyle(Palette.tier(analysis.tier))
                            }.font(.system(size: 12))
                            TierProgress(snapshot: snapshot, tariff: store.configuration.tariff, compact: true)
                        }
                        Divider()
                        VStack(spacing: 11) {
                            row("电费估算", store.configuration.tariff.cost(snapshot: snapshot)?.yuan ?? "缺少分时数据")
                            row("月底预计", analysis.projected.map { $0.meter(1) + " 度" } ?? "—")
                            row("不跨档日均预算", analysis.dailyBudget.map { $0.meter(2) + " 度 / 天" } ?? "—")
                        }
                        if let day = analysis.expectedCrossingDay {
                            Label("按当前日均，预计 \(snapshot.month.month) 月 \(day) 日跨档", systemImage: "arrow.up.right")
                                .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        }
                        Divider()
                        UsageChart(snapshot: snapshot, compact: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("数据截至 \(snapshot.month.month) 月 \(snapshot.lastDay ?? 1) 日 · 每 \(store.configuration.refreshMinutes) 分钟查询")
                            Text("电费为估算；日预算包含尚未出数据的日期。")
                        }.font(.system(size: 9)).foregroundStyle(.secondary)
                    }.padding(20)
                } else {
                    EmptyMeterView(store: store, showSettings: showSettings).frame(height: 300)
                }
            }
            Divider()
            HStack {
                Button(action: showDashboard) { Label("查看用电详情", systemImage: "chart.bar.xaxis") }.buttonStyle(.plain)
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain).help("退出szElectricityMeter")
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
        }.frame(width: 396).frame(maxHeight: 700).background(Palette.background).tint(Palette.green)
            .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
    }
    func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium).monospacedDigit() }.font(.system(size: 12))
    }
}
