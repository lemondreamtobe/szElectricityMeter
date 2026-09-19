import AppKit
import Combine
import UserNotifications
import MeterCore

@MainActor final class MeterStore: ObservableObject {
    let isDemo: Bool
    @Published private(set) var demoTier = 1
    @Published private(set) var configuration: MeterConfiguration
    @Published private(set) var snapshots: [String: UsageSnapshot] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var tokenAvailable = false
    @Published private(set) var needsToken = false
    @Published private(set) var storageError: String?
    @Published var selectedMonth = YearMonth()
    @Published private(set) var currentMonth = YearMonth()
    private var generation = UUID()
    private var timer: Timer?
    private var token: String?
    private var pausedForAuth = false
    private var failures = 0
    private var nextRefresh = Date.distantPast
    private let disk = LocalStore()
    private var wakeObserver: NSObjectProtocol?
    var onStatusChange: (() -> Void)?

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            configuration = MeterConfiguration()
            configuration.accountName = "深圳 · 演示家庭"
            configuration.customerID = "DEMO-CUSTOMER"
            configuration.meteringPointID = "DEMO-METER"
            configuration.appearance = "light"
            for offset in -2...0 {
                let month = currentMonth.offset(offset)
                snapshots[month.key] = Self.demoSnapshot(month, tier: demoTier)
            }
            return
        }
        var initialError: String?
        do { configuration = try disk.loadConfiguration() }
        catch { configuration = MeterConfiguration(); initialError = "本地配置无法读取，请在设置中重新保存。" }
        snapshots = disk.snapshots(account: configuration.accountKey)
        do { token = try TokenVault.read(); tokenAvailable = !(token ?? "").isEmpty }
        catch { initialError = error.localizedDescription }
        storageError = initialError
    }
    var current: UsageSnapshot? { snapshots[currentMonth.key] }
    var selected: UsageSnapshot? { snapshots[selectedMonth.key] }
    var analysis: UsageAnalysis? { selected.map { UsageAnalysis(snapshot: $0, tariff: configuration.tariff) } }
    var currentAnalysis: UsageAnalysis? { current.map { UsageAnalysis(snapshot: $0, tariff: configuration.tariff) } }
    var isConfigured: Bool { isDemo || (configuration.isComplete && tokenAvailable) }
    var selectedError: String? { errors[selectedMonth.key] }

    func start() {
        guard !isDemo else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduledRefresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduledRefresh() }
        }
        scheduledRefresh()
    }
    func scheduledRefresh() {
        guard !isDemo else { return }
        rollMonth()
        if Date() >= nextRefresh && !pausedForAuth { Task { await refresh(currentMonth) } }
    }
    func rollMonth() {
        guard !isDemo else { return }
        let newMonth = YearMonth()
        if currentMonth != newMonth {
            if selectedMonth == currentMonth { selectedMonth = newMonth }
            currentMonth = newMonth
            nextRefresh = .distantPast
            onStatusChange?()
        }
    }
    func select(_ month: YearMonth) {
        guard month <= YearMonth() else { return }
        selectedMonth = month
        if snapshots[month.key] == nil { Task { await refresh(month) } }
    }
    func refreshSelected() { Task { await refresh(selectedMonth, manual: true) } }
    func refreshCurrent() { rollMonth(); Task { await refresh(currentMonth, manual: true) } }

    func refresh(_ month: YearMonth, manual: Bool = false) async {
        if isDemo {
            snapshots[month.key] = Self.demoSnapshot(month, tier: demoTier)
            onStatusChange?()
            return
        }
        guard !loading.contains(month.key), month <= YearMonth(), manual || !pausedForAuth else { return }
        guard isConfigured, let token else { needsToken = true; onStatusChange?(); return }
        let requestGeneration = generation, account = configuration.accountKey, config = configuration
        loading.insert(month.key); onStatusChange?()
        defer {
            if generation == requestGeneration { loading.remove(month.key); onStatusChange?() }
        }
        do {
            let result = try await CSGClient().fetch(month: month, configuration: config, token: token)
            guard generation == requestGeneration else { return }
            snapshots[month.key] = result
            errors.removeValue(forKey: month.key)
            pausedForAuth = false; needsToken = false; failures = 0
            if month == currentMonth { nextRefresh = Date().addingTimeInterval(Double(config.refreshMinutes) * 60) }
            do { try disk.saveSnapshots(snapshots, account: account); storageError = nil }
            catch { storageError = "数据已更新，但无法保存到本机缓存。" }
            await notifyIfNeeded(result)
        } catch {
            guard generation == requestGeneration else { return }
            errors[month.key] = error.localizedDescription
            failures = min(failures + 1, 6)
            if month == currentMonth { nextRefresh = Date().addingTimeInterval(min(21600, Double(config.refreshMinutes) * 60 * pow(2, Double(failures)))) }
            if (error as? MeterError) == .authentication { pausedForAuth = true; needsToken = true }
        }
    }

    func save(_ value: MeterConfiguration, replacementToken: String) throws {
        guard value.isComplete, value.tariff.isValid, (15...1440).contains(value.refreshMinutes), value.alertThreshold.isFinite, value.alertThreshold >= 0 else { throw MeterError.configuration }
        let clean = replacementToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            guard !clean.contains(where: { $0.isWhitespace || $0 == ";" }) else { throw SettingsError.invalidToken }
        }
        if isDemo {
            configuration = value
            onStatusChange?()
            return
        }
        if !tokenAvailable && clean.isEmpty { throw MeterError.configuration }
        // Write disk settings first. If Keychain fails, restore the previous settings.
        try disk.saveConfiguration(value)
        do { if !clean.isEmpty { try TokenVault.save(clean) } }
        catch { try? disk.saveConfiguration(configuration); throw error }
        let accountChanged = configuration.accountKey != value.accountKey
        generation = UUID(); loading = []; errors = [:]
        configuration = value
        if !clean.isEmpty { token = clean; tokenAvailable = true }
        if accountChanged { snapshots = disk.snapshots(account: value.accountKey) }
        storageError = nil; needsToken = false; pausedForAuth = false; failures = 0; nextRefresh = .distantPast
        onStatusChange?()
        refreshCurrent()
        if selectedMonth != currentMonth { refreshSelected() }
    }
    enum SettingsError: LocalizedError {
        case invalidToken
        var errorDescription: String? { "只粘贴 x-auth-token 的值，不要包含请求头名称、空格或 Cookie。" }
    }
    func requestNotifications() async -> Bool {
        guard !isDemo else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    private func notifyIfNeeded(_ snapshot: UsageSnapshot) async {
        guard !isDemo else { return }
        guard configuration.notifyNearLimit, snapshot.month == currentMonth, !snapshot.isDelayed(), snapshot.hasCompleteCoverage else { return }
        let analysis = UsageAnalysis(snapshot: snapshot, tariff: configuration.tariff)
        guard let remaining = analysis.remaining, remaining <= configuration.alertThreshold else { return }
        let id = "limit-\(configuration.accountKey)-\(snapshot.month.key)-\(analysis.tier)"
        guard !UserDefaults.standard.bool(forKey: id) else { return }
        let content = UNMutableNotificationContent()
        content.title = "szElectricityMeter · 阶梯提醒"
        content.body = String(format: "距第 %d 档还剩 %.1f 度，数据截至 %d 月 %d 日。", analysis.tier + 1, remaining, snapshot.month.month, snapshot.lastDay ?? 1)
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            UserDefaults.standard.set(true, forKey: id)
        } catch { /* Optional notifications must never interrupt data refresh. */ }
    }

    // Synthetic samples only. Demo initialization returns before reading disk or Keychain.
    func selectDemoTier(_ tier: Int) {
        guard isDemo, (1...3).contains(tier) else { return }
        demoTier = tier
        for key in Array(snapshots.keys) {
            if let month = snapshots[key]?.month { snapshots[key] = Self.demoSnapshot(month, tier: tier) }
        }
        onStatusChange?()
    }

    private static func demoSnapshot(_ month: YearMonth, tier: Int) -> UsageSnapshot {
        let today = ShenzhenTime.calendar.component(.day, from: Date())
        let lastDay = month == YearMonth() ? max(1, today - 1) : month.days
        let weights = (1...lastDay).map { Double(850 + ($0 * 137) % 700) }
        let sum = weights.reduce(0, +)
        let limits = Tariff().limits(for: month)
        let target = tier == 1 ? limits.0 * 0.895 : (tier == 2 ? limits.1 * 0.75 : limits.1 * 1.15)
        let daily = (1...lastDay).map { day in
            DailyUsage(day: day, kWh: (weights[day - 1] / sum * target * 100).rounded() / 100,
                       temperature: Double(26 + day % 7))
        }
        return UsageSnapshot(month: month, total: daily.reduce(0) { $0 + $1.kWh }, daily: daily)
    }
}
