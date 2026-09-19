import Foundation

public enum ShenzhenTime {
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
}

public struct YearMonth: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public init(year: Int, month: Int) { self.year = year; self.month = month }
    public init(date: Date = Date()) {
        year = ShenzhenTime.calendar.component(.year, from: date)
        month = ShenzhenTime.calendar.component(.month, from: date)
    }
    public var key: String { String(format: "%04d%02d", year, month) }
    public var title: String { "\(year) 年 \(month) 月" }
    public var start: Date { ShenzhenTime.calendar.date(from: DateComponents(year: year, month: month, day: 1))! }
    public var days: Int { ShenzhenTime.calendar.range(of: .day, in: .month, for: start)!.count }
    public var isSummer: Bool { (5...10).contains(month) }
    public func offset(_ n: Int) -> YearMonth {
        YearMonth(date: ShenzhenTime.calendar.date(byAdding: .month, value: n, to: start)!)
    }
    public func date(day: Int) -> Date {
        ShenzhenTime.calendar.date(byAdding: .day, value: day - 1, to: start)!
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.key < rhs.key }
}

public struct DailyUsage: Codable, Identifiable, Equatable, Sendable {
    public var id: Int { day }
    public let day: Int
    public let kWh: Double
    public let temperature: Double?
    public let estimated: Bool
    public init(day: Int, kWh: Double, temperature: Double? = nil, estimated: Bool = false) {
        self.day = day; self.kWh = kWh; self.temperature = temperature; self.estimated = estimated
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let month: YearMonth
    public let total: Double
    public let daily: [DailyUsage]
    public let fetchedAt: Date
    public let peak: Double?
    public let flat: Double?
    public let valley: Double?
    public init(month: YearMonth, total: Double, daily: [DailyUsage], fetchedAt: Date = Date(), peak: Double? = nil, flat: Double? = nil, valley: Double? = nil) {
        self.month = month; self.total = total; self.daily = daily.sorted { $0.day < $1.day }
        self.fetchedAt = fetchedAt; self.peak = peak; self.flat = flat; self.valley = valley
    }
    public var lastDay: Int? { daily.last?.day }
    public var hasCompleteCoverage: Bool {
        guard let lastDay, lastDay > 0 else { return false }
        return daily.map(\.day) == Array(1...lastDay) && abs(daily.reduce(0) { $0 + $1.kWh } - total) <= 0.05
    }
    public var hasTOU: Bool {
        guard let peak, let flat, let valley else { return false }
        return abs(peak + flat + valley - total) <= 0.05
    }
    public func isDelayed(at now: Date = Date()) -> Bool {
        guard let lastDay else { return true }
        let age = ShenzhenTime.calendar.dateComponents([.day], from: month.date(day: lastDay), to: now).day ?? 0
        return month == YearMonth(date: now) && age > 2
    }
}

public enum BillingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case tiered, timeOfUse, combined
    public var id: String { rawValue }
    public var title: String {
        switch self { case .tiered: return "居民阶梯"; case .timeOfUse: return "居民峰谷"; case .combined: return "居民合表" }
    }
}

public struct Tariff: Codable, Equatable, Sendable {
    public var mode: BillingMode = .tiered
    public var firstRate: Double = 0.6542
    public var secondRate: Double = 0.7042
    public var thirdRate: Double = 0.9542
    public var peakRate: Double = 1.1121
    public var valleyRate: Double = 0.2486
    public var combinedRate: Double = 0.6912
    public var surcharge: Double = 0
    public var summerFirst: Double = 260
    public var summerSecond: Double = 600
    public var winterFirst: Double = 200
    public var winterSecond: Double = 400
    public init() {}
    public func limits(for month: YearMonth) -> (Double, Double) {
        month.isSummer ? (summerFirst, summerSecond) : (winterFirst, winterSecond)
    }
    public var isValid: Bool {
        let numbers = [firstRate, secondRate, thirdRate, peakRate, valleyRate, combinedRate, surcharge, summerFirst, summerSecond, winterFirst, winterSecond]
        return numbers.allSatisfy { $0.isFinite && $0 >= 0 } && firstRate > 0 && secondRate >= firstRate && thirdRate >= secondRate && combinedRate > 0 && peakRate > 0 && summerFirst > 0 && summerSecond > summerFirst && winterFirst > 0 && winterSecond > winterFirst
    }
    public func tier(for total: Double, month: YearMonth) -> Int {
        let (first, second) = limits(for: month)
        return total < first ? 1 : (total < second ? 2 : 3)
    }
    public func rate(tier: Int) -> Double { [firstRate, secondRate, thirdRate][max(0, min(2, tier - 1))] + surcharge }
    public func buckets(total: Double, month: YearMonth) -> [Double] {
        let (first, second) = limits(for: month), value = max(0, total)
        return [min(value, first), min(max(0, value - first), second - first), max(0, value - second)]
    }
    public func tieredCost(total: Double, month: YearMonth) -> Double {
        zip(buckets(total: total, month: month), [firstRate, secondRate, thirdRate]).reduce(0) { $0 + $1.0 * $1.1 } + max(0, total) * surcharge
    }
    public func cost(snapshot: UsageSnapshot) -> Double? {
        switch mode {
        case .tiered: return tieredCost(total: snapshot.total, month: snapshot.month)
        case .combined: return snapshot.total * (combinedRate + surcharge)
        case .timeOfUse:
            guard snapshot.hasTOU, let peak = snapshot.peak, let flat = snapshot.flat, let valley = snapshot.valley else { return nil }
            let buckets = buckets(total: snapshot.total, month: snapshot.month)
            return peak * peakRate + flat * firstRate + valley * valleyRate + buckets[1] * (secondRate - firstRate) + buckets[2] * (thirdRate - firstRate) + snapshot.total * surcharge
        }
    }
}

public struct UsageAnalysis: Sendable {
    public let snapshot: UsageSnapshot
    public let tariff: Tariff
    public let now: Date
    public init(snapshot: UsageSnapshot, tariff: Tariff, now: Date = Date()) { self.snapshot = snapshot; self.tariff = tariff; self.now = now }
    public var tier: Int { tariff.tier(for: snapshot.total, month: snapshot.month) }
    public var nextLimit: Double? {
        guard tariff.mode != .combined, tier < 3 else { return nil }
        let limits = tariff.limits(for: snapshot.month)
        return tier == 1 ? limits.0 : limits.1
    }
    public var remaining: Double? { nextLimit.map { max(0, $0 - snapshot.total) } }
    public var remainingFraction: Double { guard let remaining, let nextLimit else { return 0 }; return remaining / nextLimit }
    public var unreportedDays: Int { snapshot.month.days - (snapshot.lastDay ?? 0) }
    public var average: Double? {
        guard snapshot.hasCompleteCoverage, let day = snapshot.lastDay else { return nil }
        return snapshot.total / Double(day)
    }
    public var projected: Double? {
        guard snapshot.month == YearMonth(date: now), !snapshot.isDelayed(at: now), let average, (snapshot.lastDay ?? 0) >= 3 else { return nil }
        return average * Double(snapshot.month.days)
    }
    public var dailyBudget: Double? {
        guard projected != nil, let remaining, unreportedDays > 0 else { return nil }
        return remaining / Double(unreportedDays)
    }
    public var expectedCrossingDay: Int? {
        guard projected != nil, let average, average > 0, let nextLimit else { return nil }
        let day = Int(floor(nextLimit / average)) + 1
        return day <= snapshot.month.days ? day : nil
    }
    public var projectedCost: Double? {
        guard let projected else { return nil }
        if tariff.mode == .tiered { return tariff.tieredCost(total: projected, month: snapshot.month) }
        if tariff.mode == .combined { return projected * (tariff.combinedRate + tariff.surcharge) }
        return nil
    }
    public var timeRemainingFraction: Double {
        guard snapshot.month == YearMonth(date: now) else { return 0 }
        let elapsed = ShenzhenTime.calendar.component(.day, from: now) - 1
        return Double(snapshot.month.days - elapsed) / Double(snapshot.month.days)
    }
    public var goal: Double { nextLimit ?? tariff.limits(for: snapshot.month).1 }
    public var requiredDailyReduction: Double? {
        guard let average, let dailyBudget else { return nil }
        return max(0, average - dailyBudget)
    }
    public func savings(reducingDaily reduction: Double) -> Double? {
        guard let projected, let projectedCost else { return nil }
        let reduced = max(snapshot.total, projected - max(0, reduction) * Double(unreportedDays))
        let newCost = tariff.mode == .combined ? reduced * (tariff.combinedRate + tariff.surcharge) : tariff.tieredCost(total: reduced, month: snapshot.month)
        return max(0, projectedCost - newCost)
    }
}
