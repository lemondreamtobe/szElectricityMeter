import Foundation
import MeterCore

final class MeterCoreTests {
    let september = YearMonth(year: 2026, month: 9)
    let now = ShenzhenTime.calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12))!
    func snapshot(total: Double = 222.46) -> UsageSnapshot {
        UsageSnapshot(month: september, total: total, daily: (1...18).map { DailyUsage(day: $0, kWh: total / 18) }, fetchedAt: now)
    }
    func response(_ data: [String: Any], status: Any = "00", message: String = "") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sta": status, "message": message, "data": data])
    }
    func testSummerAndWinterLimits() {
        let tariff = Tariff()
        for month in 1...12 {
            let value = YearMonth(year: 2026, month: month)
            expectEqual(tariff.limits(for: value).0, (5...10).contains(month) ? 260 : 200)
            expectEqual(tariff.limits(for: value).1, (5...10).contains(month) ? 600 : 400)
        }
    }
    func testProgressiveBillingDoesNotRepricePreviousUnits() {
        let tariff = Tariff()
        expectEqual(tariff.tieredCost(total: 260, month: september), 170.092, accuracy: 0.00001)
        expectEqual(tariff.tieredCost(total: 261, month: september), 170.7962, accuracy: 0.00001)
        expectEqual(tariff.tieredCost(total: 600, month: september), 409.52, accuracy: 0.00001)
        expectEqual(tariff.tieredCost(total: 601, month: september), 410.4742, accuracy: 0.00001)
        expectEqual(tariff.tieredCost(total: 222.46, month: september), 145.533332, accuracy: 0.00001)
    }
    func testBoundaryDescribesNextUnitPrice() {
        let tariff = Tariff()
        expectEqual(tariff.tier(for: 259.99, month: september), 1)
        expectEqual(tariff.tier(for: 260, month: september), 2)
        expectEqual(tariff.tier(for: 599.99, month: september), 2)
        expectEqual(tariff.tier(for: 600, month: september), 3)
        expectEqual(tariff.buckets(total: 600, month: september), [260, 340, 0])
    }
    func testProjectionUsesPublishedCutoffNotComputerDay() {
        let analysis = UsageAnalysis(snapshot: snapshot(), tariff: Tariff(), now: now)
        expectEqual(analysis.remaining!, 37.54, accuracy: 0.00001)
        expectEqual(analysis.projected!, 370.76666667, accuracy: 0.00001)
        expectEqual(analysis.dailyBudget!, 3.128333333, accuracy: 0.00001)
        expectEqual(analysis.unreportedDays, 12)
        expectEqual(analysis.expectedCrossingDay, 22)
        expectEqual(analysis.savings(reducingDaily: 2)!, 16.9008, accuracy: 0.00001)
        expectEqual(analysis.savings(reducingDaily: 100)!, analysis.projectedCost! - Tariff().cost(snapshot: snapshot())!, accuracy: 0.00001)
    }
    func testNoForecastForMissingDaysMismatchedTotalsOrStaleData() {
        let partial = UsageSnapshot(month: september, total: 20, daily: [DailyUsage(day: 1, kWh: 10), DailyUsage(day: 18, kWh: 10)])
        expectNil(UsageAnalysis(snapshot: partial, tariff: Tariff(), now: now).projected)
        let mismatch = UsageSnapshot(month: september, total: 300, daily: snapshot().daily)
        expectNil(UsageAnalysis(snapshot: mismatch, tariff: Tariff(), now: now).projected)
        let staleNow = september.date(day: 22)
        expectNil(UsageAnalysis(snapshot: snapshot(), tariff: Tariff(), now: staleNow).projected)
        expectNil(UsageAnalysis(snapshot: snapshot(), tariff: Tariff(), now: september.offset(1).start).projected)
    }
    func testZeroUsageIsValidAndHasNoCrossingDate() {
        let analysis = UsageAnalysis(snapshot: snapshot(total: 0), tariff: Tariff(), now: now)
        expectEqual(analysis.projected, 0)
        expectNil(analysis.expectedCrossingDay)
        expectEqual(analysis.dailyBudget!, 260.0 / 12, accuracy: 0.00001)
    }
    func testThirdTierHasNoNextLimitAndSavingsStillWork() {
        let analysis = UsageAnalysis(snapshot: snapshot(total: 650), tariff: Tariff(), now: now)
        expectEqual(analysis.tier, 3)
        expectNil(analysis.remaining)
        expectNil(analysis.dailyBudget)
        expectGreaterThan(analysis.savings(reducingDaily: 2)!, 0)
    }
    func testCombinedTariffDoesNotHaveTiers() {
        var tariff = Tariff(); tariff.mode = .combined
        let analysis = UsageAnalysis(snapshot: snapshot(), tariff: tariff, now: now)
        expectNil(analysis.nextLimit)
        expectEqual(tariff.cost(snapshot: snapshot())!, 222.46 * 0.6912, accuracy: 0.00001)
    }
    func testTOURequiresCompletePeriodTotals() {
        var tariff = Tariff(); tariff.mode = .timeOfUse
        expectNil(tariff.cost(snapshot: snapshot()))
        let invalid = UsageSnapshot(month: september, total: 300, daily: [], peak: 50, flat: 100, valley: 100)
        expectNil(tariff.cost(snapshot: invalid))
        let valid = UsageSnapshot(month: september, total: 300, daily: [], peak: 100, flat: 100, valley: 100)
        expectEqual(tariff.cost(snapshot: valid)!, 100 * (1.1121 + 0.6542 + 0.2486) + 40 * 0.05, accuracy: 0.00001)
    }
    func testSurchargeAndCustomLimits() {
        var tariff = Tariff(); tariff.surcharge = 0.00866875; tariff.summerFirst = 360; tariff.summerSecond = 800
        expectEqual(tariff.tieredCost(total: 400, month: september), 360 * 0.6542 + 40 * 0.7042 + 400 * 0.00866875, accuracy: 0.00001)
        expectTrue(tariff.isValid)
        tariff.summerSecond = 300; expectFalse(tariff.isValid)
        tariff.summerSecond = .infinity; expectFalse(tariff.isValid)
    }
    func testLeapYearAndMonthRollover() {
        expectEqual(YearMonth(year: 2024, month: 2).days, 29)
        expectEqual(YearMonth(year: 2026, month: 2).days, 28)
        expectEqual(YearMonth(year: 2026, month: 12).offset(1), YearMonth(year: 2027, month: 1))
    }
    func testParserAcceptsActualSchemaStringsNumbersAndUnsortedRows() throws {
        let bytes = try response(["totalPower": "3.5", "result": [
            ["date": "2026-09-02", "power": 2, "isEstimate": "1"],
            ["date": "2026-09-01", "power": "1.5", "averageTemperature": "27.2"],
            ["date": "2026-09-03", "power": NSNull()]
        ]])
        let value = try CalendarParser.parse(bytes, month: september, now: now)
        expectEqual(value.total, 3.5)
        expectEqual(value.daily.map(\.day), [1, 2])
        expectEqual(value.daily[0].temperature, 27.2)
        expectTrue(value.daily[1].estimated)
        expectTrue(value.hasCompleteCoverage)
        expectNil(value.peak)
    }
    func testParserAuthenticationErrorsDoNotExposeServerMessage() throws {
        let bytes = try response([:], status: "99", message: "登录凭证 TOKEN-SHOULD-NOT-LEAK 过期")
        expectThrows(try CalendarParser.parse(bytes, month: september, now: now)) { error in
            expectEqual(error as? MeterError, .authentication)
            expectFalse(error.localizedDescription.contains("TOKEN-SHOULD-NOT-LEAK"))
        }
    }
    func testBindingMismatchIsDistinctFromExpiredToken() throws {
        let bytes = try response([:], status: "02", message: "请确认绑定id是否正确")
        expectThrows(try CalendarParser.parse(bytes, month: september, now: now)) { error in
            expectEqual(error as? MeterError, .accountBinding)
        }
        let unrelated = try response([:], status: "02", message: "服务暂不可用")
        expectThrows(try CalendarParser.parse(unrelated, month: september, now: now)) { error in
            expectEqual(error as? MeterError, .server)
        }
    }
    func testParserRejectsMalformedNumbersDuplicatesWrongMonthAndFutureDate() throws {
        for rows in [
            [["date": "2026-09-01", "power": "NaN"]],
            [["date": "2026-09-01", "power": "-1"]],
            [["date": "2026-09-01", "power": "1"], ["date": "2026-09-01", "power": "1"]],
            [["date": "2026-08-01", "power": "1"]],
            [["date": "2026-09-31", "power": "1"]],
            [["date": "2026-09-20", "power": "1"]]
        ] {
            expectThrows(try CalendarParser.parse(response(["totalPower": "1", "result": rows]), month: september, now: now)) { expectEqual($0 as? MeterError, .invalidResponse) }
        }
    }
    func testParserEmptyMonthIsNotFakeZero() throws {
        expectThrows(try CalendarParser.parse(response(["totalPower": "0", "result": []]), month: september, now: now)) { expectEqual($0 as? MeterError, .noData) }
        let zero = try CalendarParser.parse(response(["totalPower": "0", "result": [["date": "2026-09-01", "power": "0"]]]), month: september, now: now)
        expectEqual(zero.total, 0)
    }
    func testParserMissingTotalIsNotAssumedComplete() throws {
        expectThrows(try CalendarParser.parse(response(["result": [["date": "2026-09-01", "power": "1"]]]), month: september, now: now)) { expectEqual($0 as? MeterError, .invalidResponse) }
    }
}

private var failures = 0
private var assertions = 0
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    if !value { failures += 1; print("FAIL \(file):\(line)") }
}
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { expectTrue(actual == expected, file: file, line: line) }
func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    if abs(actual - expected) > accuracy { print("Actual: \(actual), expected: \(expected)") }
    expectTrue(abs(actual - expected) <= accuracy, file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
func expectGreaterThan(_ actual: Double, _ expected: Double, file: StaticString = #file, line: UInt = #line) { expectTrue(actual > expected, file: file, line: line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line, check: (Error) -> Void) {
    do { _ = try expression(); expectTrue(false, file: file, line: line) }
    catch { assertions += 1; check(error) }
}
@main enum CoreCheckRunner {
    static func main() {
        let suite = MeterCoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("testSummerAndWinterLimits", suite.testSummerAndWinterLimits),
            ("testProgressiveBillingDoesNotRepricePreviousUnits", suite.testProgressiveBillingDoesNotRepricePreviousUnits),
            ("testBoundaryDescribesNextUnitPrice", suite.testBoundaryDescribesNextUnitPrice),
            ("testProjectionUsesPublishedCutoffNotComputerDay", suite.testProjectionUsesPublishedCutoffNotComputerDay),
            ("testNoForecastForMissingDaysMismatchedTotalsOrStaleData", suite.testNoForecastForMissingDaysMismatchedTotalsOrStaleData),
            ("testZeroUsageIsValidAndHasNoCrossingDate", suite.testZeroUsageIsValidAndHasNoCrossingDate),
            ("testThirdTierHasNoNextLimitAndSavingsStillWork", suite.testThirdTierHasNoNextLimitAndSavingsStillWork),
            ("testCombinedTariffDoesNotHaveTiers", suite.testCombinedTariffDoesNotHaveTiers),
            ("testTOURequiresCompletePeriodTotals", suite.testTOURequiresCompletePeriodTotals),
            ("testSurchargeAndCustomLimits", suite.testSurchargeAndCustomLimits),
            ("testLeapYearAndMonthRollover", suite.testLeapYearAndMonthRollover),
            ("testParserAcceptsActualSchemaStringsNumbersAndUnsortedRows", suite.testParserAcceptsActualSchemaStringsNumbersAndUnsortedRows),
            ("testParserAuthenticationErrorsDoNotExposeServerMessage", suite.testParserAuthenticationErrorsDoNotExposeServerMessage),
            ("testBindingMismatchIsDistinctFromExpiredToken", suite.testBindingMismatchIsDistinctFromExpiredToken),
            ("testParserRejectsMalformedNumbersDuplicatesWrongMonthAndFutureDate", suite.testParserRejectsMalformedNumbersDuplicatesWrongMonthAndFutureDate),
            ("testParserEmptyMonthIsNotFakeZero", suite.testParserEmptyMonthIsNotFakeZero),
            ("testParserMissingTotalIsNotAssumedComplete", suite.testParserMissingTotalIsNotAssumedComplete)
        ]
        for (name, run) in cases {
            let previous = failures
            do { try run() } catch { failures += 1; print("ERROR \(name): \(error)") }
            print("\(failures == previous ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) cases, \(assertions) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
