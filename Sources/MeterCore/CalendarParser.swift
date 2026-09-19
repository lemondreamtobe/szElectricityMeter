import Foundation

public enum MeterError: Error, LocalizedError, Equatable {
    case authentication, accountBinding, server, invalidResponse, noData, configuration, transport
    public var errorDescription: String? {
        switch self {
        case .authentication: return "登录凭证已失效，请到设置粘贴新的 Token。"
        case .accountBinding: return "电表绑定信息不匹配。请从最新成功请求中更新用电客户 ID（eleCustId）及计量点 ID，不能只更新 Token。"
        case .server: return "南网暂未返回可用结果，请稍后重试；若持续失败，请检查 Token 和户号配置。"
        case .invalidResponse: return "接口数据格式有变化，暂时无法读取。已保留上次成功的数据。"
        case .noData: return "这个月暂无用电数据，可切换月份或稍后刷新。"
        case .configuration: return "请先填写 Token、区域代码、用电客户 ID 和计量点 ID。"
        case .transport: return "连接南网失败，请检查网络后重试。"
        }
    }
}

public enum CalendarParser {
    private static func text(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
    private static func number(_ value: Any?) -> Double? {
        guard let value = text(value), let n = Double(value), n.isFinite, n >= 0 else { return nil }
        return n
    }
    public static func parse(_ bytes: Data, month: YearMonth, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], let status = text(root["sta"]) else { throw MeterError.invalidResponse }
        guard status == "00" || status == "0" else {
            let message = (text(root["message"]) ?? "").lowercased()
            if message.contains("绑定id") || message.contains("绑定 id") || message.contains("绑定关系") {
                throw MeterError.accountBinding
            }
            if ["04", "401", "403", "10001", "10002"].contains(status) || ["登录", "登陆", "token", "凭证", "认证", "会话", "login", "unauthorized"].contains(where: { message.contains($0) }) {
                throw MeterError.authentication
            }
            throw MeterError.server
        }
        guard let body = root["data"] as? [String: Any] else { throw MeterError.noData }
        guard let rows = body["result"] as? [[String: Any]] else {
            if body["result"] == nil || body["result"] is NSNull { throw MeterError.noData }
            throw MeterError.invalidResponse
        }
        var days: [Int: DailyUsage] = [:]
        for row in rows {
            // Null power denotes an unpublished day, never zero consumption.
            if row["power"] == nil || row["power"] is NSNull || text(row["power"]) == "" { continue }
            guard let rawDate = text(row["date"]), let power = number(row["power"]) else { throw MeterError.invalidResponse }
            let parts = rawDate.split(separator: "-")
            guard parts.count == 3, Int(parts[0]) == month.year, Int(parts[1]) == month.month,
                  let day = Int(parts[2]), (1...month.days).contains(day), month.date(day: day) <= now,
                  days[day] == nil else { throw MeterError.invalidResponse }
            days[day] = DailyUsage(day: day, kWh: power, temperature: number(row["averageTemperature"]), estimated: ["1", "true"].contains(text(row["isEstimate"]) ?? ""))
        }
        guard let total = number(body["totalPower"]) else {
            if days.isEmpty && (body["totalPower"] == nil || body["totalPower"] is NSNull || text(body["totalPower"]) == "") { throw MeterError.noData }
            throw MeterError.invalidResponse
        }
        if days.isEmpty && total == 0 { throw MeterError.noData }
        return UsageSnapshot(month: month, total: total, daily: Array(days.values), fetchedAt: now,
                             peak: number(body["totalPeakPeriod"]), flat: number(body["totalParallelPeriod"]), valley: number(body["totalValleyStage"]))
    }
}
