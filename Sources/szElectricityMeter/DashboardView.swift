import SwiftUI
import MeterCore

struct DashboardView: View {
    @ObservedObject var store: MeterStore
    let showSettings: () -> Void
    @State private var reduction = 2.0
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                if let snapshot = store.selected, let analysis = store.analysis {
                    VStack(spacing: 18) {
                        if let error = store.selectedError { StatusBanner(message: "\(error) 当前显示上次成功的数据。", action: showSettings) }
                        if let error = store.storageError { StatusBanner(message: error, action: showSettings) }
                        if snapshot.isDelayed() { StatusBanner(message: "南网数据已超过两天未更新，暂不显示月底预测。阶梯额度截至最近公布日期。") }
                        hero(snapshot, analysis)
                        HStack(spacing: 16) {
                            metric("本月电费估算", value: store.configuration.tariff.cost(snapshot: snapshot)?.yuan ?? "暂无分时数据", note: "按设置电价计算 · 非实际账单", icon: "yensign.circle")
                            metric("月底预计用电", value: analysis.projected.map { $0.meter(1) + " 度" } ?? "—", note: analysis.projectedCost.map { "预计电费 " + $0.yuan } ?? (snapshot.month < YearMonth() ? "历史月份不做预测" : "需完整且近期的日用电数据"), icon: "chart.line.uptrend.xyaxis")
                            metric("最近一日", value: snapshot.daily.last.map { $0.kWh.meter(2) + " 度" } ?? "—", note: snapshot.lastDay.map { "\(snapshot.month.month) 月 \($0) 日 · 非实时读数" } ?? "暂无每日明细", icon: "sun.max")
                        }
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 18) {
                                Card { UsageChart(snapshot: snapshot) }
                                tariffs(snapshot)
                            }.frame(maxWidth: .infinity)
                            VStack(spacing: 18) {
                                budget(analysis)
                                savings(analysis)
                            }.frame(width: 284)
                        }
                        HStack {
                            Text("南网每日用电数据  ·  最近查询 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            Text("数据与阶梯均按深圳时间计算")
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(24)
                } else {
                    EmptyMeterView(store: store, showSettings: showSettings).frame(minHeight: 560)
                }
            }
        }
        .background(Palette.background)
        .tint(Palette.green)
        .frame(minWidth: 940, minHeight: 700)
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
    }
    private var header: some View {
        HStack(spacing: 12) {
            BrandMark()
            VStack(alignment: .leading, spacing: 3) {
                Text("szElectricityMeter").font(.system(size: 16, weight: .semibold))
                Text(store.configuration.accountName).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if store.isDemo { Pill(text: "演示数据 · 未联网") }
            Spacer()
            if store.isDemo {
                Picker("演示档位", selection: Binding(get: { store.demoTier }, set: { store.selectDemoTier($0) })) {
                    Text("第一档").tag(1); Text("第二档").tag(2); Text("第三档").tag(3)
                }.labelsHidden().frame(width: 84)
            }
            HStack(spacing: 14) {
                Button { store.select(store.selectedMonth.offset(-1)) } label: { Image(systemName: "chevron.left") }.help("上个月")
                Button(store.selectedMonth.title) { store.select(YearMonth()) }.font(.system(size: 13, weight: .medium)).help("返回本月")
                Button { store.select(store.selectedMonth.offset(1)) } label: { Image(systemName: "chevron.right") }
                    .disabled(store.selectedMonth >= YearMonth()).help("下个月")
            }.buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.card, in: Capsule()).overlay(Capsule().stroke(Palette.border))
            Button { store.refreshSelected() } label: {
                if store.loading.contains(store.selectedMonth.key) { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                else { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
            }.disabled(store.loading.contains(store.selectedMonth.key)).help("刷新用电数据")
            Button(action: showSettings) { Image(systemName: "slider.horizontal.3") }.help("设置")
        }.buttonStyle(.borderless).padding(.horizontal, 26).padding(.vertical, 18)
    }
    private func hero(_ snapshot: UsageSnapshot, _ analysis: UsageAnalysis) -> some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("本月已用").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Pill(text: snapshot.month.isSummer ? "夏季标准" : "非夏季标准")
                    Pill(text: store.configuration.tariff.mode == .combined ? "合表" : "第 \(analysis.tier) 档", color: Palette.tier(analysis.tier))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.total.meter(2)).font(.system(size: 49, weight: .semibold, design: .rounded)).tracking(-1.5).monospacedDigit()
                    Text("度").font(.system(size: 17)).foregroundStyle(.secondary)
                }
                Text(snapshot.lastDay.map { "截至 \(snapshot.month.month) 月 \($0) 日 · 每日数据由南网陆续发布" } ?? "暂无数据日期，用电总量来自南网")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if store.configuration.tariff.mode != .combined { TierProgress(snapshot: snapshot, tariff: store.configuration.tariff).frame(maxWidth: 420) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 146).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 10) {
                Text(analysis.remaining != nil ? "距离第 \(analysis.tier + 1) 档，还可以用" : (store.configuration.tariff.mode == .combined ? "每一度电，统一价格" : "已进入最高阶梯"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(analysis.remaining.map { $0.meter(2) } ?? (store.configuration.tariff.mode == .combined ? (store.configuration.tariff.combinedRate + store.configuration.tariff.surcharge).meter(4) : "第三档"))
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(Palette.tier(analysis.tier)).monospacedDigit()
                    Text(analysis.remaining != nil ? "度" : (store.configuration.tariff.mode == .combined ? "元 / 度" : "")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let day = analysis.expectedCrossingDay {
                    Label("按当前日均，预计 \(snapshot.month.month)/\(day) 跨档", systemImage: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Palette.amber)
                } else {
                    Text(analysis.projected != nil && analysis.remaining != nil ? "按当前日均，预计本月不会跨档" : "阶梯仅对超出部分加价").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(width: 230, alignment: .leading)
            QuotaRing(analysis: analysis).padding(.trailing, 8)
        }.padding(26)
            .background(LinearGradient(colors: [Palette.green.opacity(0.07), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.green.opacity(0.12)))
    }
    private func metric(_ label: String, value: String, note: String, icon: String) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label(label, systemImage: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
    private func budget(_ analysis: UsageAnalysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                Label("给接下来的用电留点余地", systemImage: "leaf").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green)
                if let daily = analysis.dailyBudget {
                    Text("若希望本月留在第 \(analysis.tier) 档").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(daily.meter(2)).font(.system(size: 33, weight: .semibold, design: .rounded))
                        Text("度 / 天").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Text("从数据截止日之后起，剩余 \(analysis.unreportedDays) 天的平均额度，包含尚未出数据的日期。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    Divider()
                    if let average = analysis.average, let reduction = analysis.requiredDailyReduction {
                        Text("目前日均 \(average.meter(2)) 度\n\(reduction > 0 ? "每天需少用约 " + reduction.meter(2) + " 度" : "目前用电节奏在额度内")")
                            .font(.system(size: 11)).lineSpacing(5)
                    }
                } else {
                    Text(analysis.tariff.mode == .combined ? "合表电价没有阶梯分界，节电仍可直接降低电费。" : (analysis.tier == 3 ? "已到第三档，继续节电可减少最高档的用电支出。" : "数据不足或月份已结束，暂不计算剩余每日预算。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                }
            }
        }
    }
    private func savings(_ analysis: UsageAnalysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("少用一点，会省多少？").font(.system(size: 13, weight: .semibold))
                HStack {
                    Text("每天少用").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(reduction.meter(1)) 度").fontWeight(.medium)
                }.font(.system(size: 12))
                Slider(value: $reduction, in: 0...10, step: 0.5)
                if let saved = analysis.savings(reducingDaily: reduction) {
                    Text("月底预计节省  \(saved.yuan)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.green)
                } else {
                    Text(analysis.tariff.mode == .timeOfUse ? "峰谷模式缺少未来分时用量，不估算节省金额。" : "取得完整近期数据后，计算本月节省金额。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("例如 1 kW 电器少运行 1 小时≈1 度电。优先减少空调空转与不必要的热水保温；变频设备实际功率会变化。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
    private func tariffs(_ snapshot: UsageSnapshot) -> some View {
        let tariff = store.configuration.tariff
        let buckets = tariff.buckets(total: snapshot.total, month: snapshot.month)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("电价怎么计算").font(.system(size: 14, weight: .semibold)); Spacer(); Text(tariff.mode.title).font(.system(size: 11)).foregroundStyle(.secondary) }
                if tariff.mode == .tiered {
                    ForEach(0..<3) { index in
                        HStack {
                            Circle().fill(Palette.tier(index + 1)).frame(width: 6, height: 6)
                            Text("第 \(index + 1) 档").frame(width: 50, alignment: .leading)
                            Text("\(buckets[index].meter(2)) 度 × \(tariff.rate(tier: index + 1).meter(4)) 元").foregroundStyle(.secondary)
                            Spacer()
                            Text((buckets[index] * tariff.rate(tier: index + 1)).yuan).monospacedDigit()
                        }.font(.system(size: 11))
                    }
                    Text("跨档只对超出的电量加价，不会把整月电量按新档重算。").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if tariff.mode == .timeOfUse {
                    Text("谷时 00–08 · 峰时 10–12、14–19 · 其余为平时").font(.system(size: 11))
                    Text(snapshot.hasTOU ? "按峰平谷电量计算基础电费，再加上阶梯加价。" : "接口未提供完整峰平谷电量，暂不估算电费。可将可定时的用电移至谷时；普通阶梯用户错峰不改变单价。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                } else {
                    Text("\(snapshot.total.meter(2)) 度 × \((tariff.combinedRate + tariff.surcharge).meter(4)) 元 / 度").font(.system(size: 12))
                }
                Text(tariff.surcharge == 0 ? "默认采用参考电价，未计政府性基金及附加；可在设置中调整。" : "已包含设置的附加单价 \(tariff.surcharge.meter(8)) 元 / 度。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
