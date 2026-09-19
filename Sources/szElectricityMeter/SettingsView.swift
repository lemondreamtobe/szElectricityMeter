import SwiftUI
import ServiceManagement
import MeterCore

struct SettingsView: View {
    @ObservedObject var store: MeterStore
    @State private var draft: MeterConfiguration
    @State private var token = ""
    @State private var tab = 0
    @State private var fields: [String: String]
    @State private var message: String?
    @State private var isError = false
    @State private var launchAtLogin: Bool
    @State private var saving = false

    init(store: MeterStore) {
        self.store = store
        _launchAtLogin = State(initialValue: store.isDemo ? false : SMAppService.mainApp.status == .enabled)
        _draft = State(initialValue: store.configuration)
        let t = store.configuration.tariff
        _fields = State(initialValue: ["first": String(t.firstRate), "second": String(t.secondRate), "third": String(t.thirdRate), "peak": String(t.peakRate), "valley": String(t.valleyRate), "combined": String(t.combinedRate), "surcharge": String(t.surcharge), "summerFirst": String(t.summerFirst), "summerSecond": String(t.summerSecond), "winterFirst": String(t.winterFirst), "winterSecond": String(t.winterSecond)])
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("把电表放进菜单栏").font(.system(size: 19, weight: .semibold))
                    Text(store.isDemo ? "szElectricityMeter · 演示模式 · 不联网、不保存" : "szElectricityMeter · 设置").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Picker("设置类别", selection: $tab) {
                Text("连接电表").tag(0); Text("电价与阶梯").tag(1); Text("偏好设置").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 16)
            Form {
                if tab == 0 { connection }
                else if tab == 1 { tariff }
                else { preferences }
            }.formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(isError ? Palette.red : Palette.green).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.isDemo ? "演示设置仅在本次运行有效。" : "Token 仅保存在此 Mac 的系统钥匙串。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(saving ? "保存中…" : "保存并刷新") { Task { await save() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving)
            }.padding(20)
        }.frame(width: 600, height: 690).background(Palette.background).tint(Palette.green)
    }
    private var connection: some View {
        Group {
            Section {
                TextField("电表名称", text: $draft.accountName, prompt: Text("深圳 · 我的家"))
                TextField("区域代码", text: $draft.areaCode, prompt: Text("090000"))
                TextField("用电客户 ID · eleCustId", text: $draft.customerID, prompt: Text("从最新请求体复制"))
                TextField("计量点 ID · meteringPointId", text: $draft.meteringPointID, prompt: Text("从最新请求体复制"))
            } header: { Text("我的电表") } footer: { Text("以上 ID 对应抓包请求体里的 areaCode、eleCustId 和 meteringPointId。") }
            Section {
                SecureField("x-auth-token", text: $token, prompt: Text(store.isDemo ? "演示模式无需 Token" : (store.tokenAvailable ? "已保存 · 留空保留现有 Token" : "粘贴 Token 的值")))
                    .textContentType(.password)
                    .disabled(store.isDemo)
                HStack {
                    Label(store.needsToken ? "等待更新 Token" : (store.tokenAvailable ? "钥匙串已保存凭证" : "尚未配置"), systemImage: store.needsToken ? "key.slash" : "lock.shield")
                    Spacer()
                    if store.tokenAvailable { Text("现有值不回显").foregroundStyle(.secondary) }
                }.font(.system(size: 11))
            } header: { Text("登录凭证") } footer: {
                Text("在南网微信小程序查询电费时，从 queryElectricityCalendar 请求头复制 x-auth-token 的值。重新登录后 eleCustId 也可能变化，请使用同一次成功请求中的凭证与电表参数；App 会用 Token 设置 CAMSID Cookie。")
            }
            Section {
                if store.loading.contains(store.currentMonth.key) {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("正在验证连接并查询本月用电…") }.font(.system(size: 12))
                } else if let error = store.errors[store.currentMonth.key] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
                    Button("重新验证连接") { store.refreshCurrent() }
                } else if let snapshot = store.current {
                    Label("\(store.isDemo ? "本地生成的示例" : "最近查询成功") · \(snapshot.total.meter(2)) 度", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green)
                    Text("查询时间：\(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("重新验证连接") { store.refreshCurrent() }
                } else {
                    Text("保存后会验证连接；保存凭证本身不代表查询成功。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } header: { Text(store.isDemo ? "演示数据 · 未连接真实电表" : "连接验证") }
            Section {
                Text("只向 weixin.csg.cn 发起用电查询；不包含统计分析或第三方服务。用电缓存保存在本机，不保存原始响应中的表号和设备编号。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private var tariff: some View {
        Group {
            Section {
                Picker("计费方式", selection: $draft.tariff.mode) { ForEach(BillingMode.allCases) { Text($0.title).tag($0) } }
                rate("第一档 / 平时基价", "first")
                rate("第二档", "second")
                rate("第三档", "third")
                if draft.tariff.mode == .timeOfUse {
                    rate("峰时第一档", "peak")
                    rate("谷时第一档", "valley")
                }
                if draft.tariff.mode == .combined { rate("合表单价", "combined") }
                rate("政府性基金及附加", "surcharge")
            } header: { Text("电价 · 元 / 千瓦时（1 度电）") } footer: {
                Text("默认参考深圳居民生活电价表：0.6542 / 0.7042 / 0.9542 元。所列单价未含政府性基金及附加，默认附加值为 0，请按自家账单填写。选择峰谷模式应与南网已开通的计费方式一致。")
            }
            Section {
                rate("夏季第一档上限", "summerFirst")
                rate("夏季第二档上限", "summerSecond")
                rate("非夏季第一档上限", "winterFirst")
                rate("非夏季第二档上限", "winterSecond")
            } header: { Text("每月阶梯上限 · 度") } footer: {
                Text("5–10 月为夏季，默认 260 / 600 度；其他月份 200 / 400 度。若已获批多人口额度或有特殊计量周期，请按供电方核定值调整。当前按自然月计算。")
            }
            Section {
                Link("深圳市居民生活电价价目表 ↗", destination: URL(string: "https://fgw.sz.gov.cn/attachment/1/1460/1460239/11394935.pdf")!)
            }
        }
    }
    private var preferences: some View {
        Group {
            Section {
                Picker("自动查询", selection: $draft.refreshMinutes) {
                    Text("每 15 分钟").tag(15); Text("每 30 分钟").tag(30); Text("每小时（推荐）").tag(60)
                    Text("每 3 小时").tag(180); Text("每 6 小时").tag(360)
                }
                Picker("菜单栏显示", selection: $draft.menuStyle) {
                    Text("距离下一档的剩余额度").tag("remaining")
                    Text("本月累计用电").tag("used")
                    Text("仅进度环").tag("ring")
                }
                Picker("外观", selection: $draft.appearance) {
                    Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                }
                Toggle("登录时启动", isOn: $launchAtLogin).disabled(store.isDemo)
            } header: { Text("日常使用") } footer: { Text("用电数据按日发布，频繁查询不会获得实时功率。外环代表距下一档的额度比例，内环代表本月日历剩余比例。") }
            Section {
                Toggle("接近下一阶梯时通知我", isOn: $draft.notifyNearLimit).disabled(store.isDemo)
                if draft.notifyNearLimit {
                    HStack { Text("剩余额度"); Spacer(); Text("\(draft.alertThreshold.meter(0)) 度以下") }
                    Slider(value: $draft.alertThreshold, in: 5...100, step: 5)
                }
            } header: { Text("阶梯提醒") } footer: { Text("每个电表、每月、每个档位最多提醒一次。首次开启时会请求 macOS 通知权限。") }
        }
    }
    private func rate(_ title: String, _ key: String) -> some View {
        TextField(title, text: Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 }))
            .multilineTextAlignment(.trailing)
    }
    private func number(_ key: String) throws -> Double {
        guard let text = fields[key], let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, value >= 0 else { throw FormError.invalidPrice }
        return value
    }
    @MainActor private func save() async {
        saving = true; defer { saving = false }
        do {
            draft.areaCode = draft.areaCode.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.customerID = draft.customerID.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.meteringPointID = draft.meteringPointID.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.tariff.firstRate = try number("first"); draft.tariff.secondRate = try number("second"); draft.tariff.thirdRate = try number("third")
            draft.tariff.peakRate = try number("peak"); draft.tariff.valleyRate = try number("valley"); draft.tariff.combinedRate = try number("combined")
            draft.tariff.surcharge = try number("surcharge")
            draft.tariff.summerFirst = try number("summerFirst"); draft.tariff.summerSecond = try number("summerSecond")
            draft.tariff.winterFirst = try number("winterFirst"); draft.tariff.winterSecond = try number("winterSecond")
            guard draft.tariff.isValid else { throw FormError.invalidLimits }
            try store.save(draft, replacementToken: token)
            if store.isDemo {
                token = ""; message = "演示设置已应用；未写入本机、未发起请求。"; isError = false
                return
            }
            token = ""; message = "已保存，正在查询最新电量。"; isError = false
            if launchAtLogin != (SMAppService.mainApp.status == .enabled) {
                do {
                    if launchAtLogin { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() }
                    if SMAppService.mainApp.status == .requiresApproval { message = "配置已保存；请在系统设置中允许登录项。" }
                } catch { message = "配置已保存；登录项设置失败，可在系统设置中检查。"; isError = true }
            }
            if draft.notifyNearLimit {
                let granted = await store.requestNotifications()
                if !granted { message = "配置已保存；通知未获授权，可在系统设置中开启。" }
            }
        } catch { message = error.localizedDescription; isError = true }
    }
    enum FormError: LocalizedError {
        case invalidPrice, invalidLimits
        var errorDescription: String? {
            switch self {
            case .invalidPrice: return "电价与额度必须是有效的非负数字。"
            case .invalidLimits: return "请检查电价与阶梯：第二档上限须大于第一档，电价须逐档不降低。"
            }
        }
    }
}
