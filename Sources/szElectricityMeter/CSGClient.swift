import Foundation
import MeterCore

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A captured credential is scoped to this endpoint; never forward it through a redirect.
        completionHandler(nil)
    }
}

struct CSGClient {
    static let endpoint = URL(string: "https://weixin.csg.cn/ucs/ma/wx-api/charge/queryElectricityCalendar")!
    func fetch(month: YearMonth, configuration: MeterConfiguration, token: String) async throws -> UsageSnapshot {
        guard configuration.isComplete, !token.isEmpty else { throw MeterError.configuration }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["areaCode": configuration.areaCode, "eleCustId": configuration.customerID, "meteringPointId": configuration.meteringPointID, "yearMonth": month.key])
        request.setValue(token, forHTTPHeaderField: "x-auth-token")
        request.setValue("CAMSID=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("xcx", forHTTPHeaderField: "channel")
        request.setValue("1", forHTTPHeaderField: "xweb_xhr")
        request.setValue("https://servicewechat.com/wx325a533aedaafe35/544/page-frame.html", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 MicroMessenger/7.0.20.1781(0x6700143B) NetType/WIFI MiniProgramEnv/Mac MacWechat/WMPF MacWechat/3.8.7(0x13080712) UnifiedPCMacWechat(0xf2641d52) XWEB/25561", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw MeterError.transport }
            if response.statusCode == 401 || response.statusCode == 403 { throw MeterError.authentication }
            guard response.statusCode == 200 else { throw MeterError.server }
            guard bytes.count <= 2_000_000 else { throw MeterError.invalidResponse }
            return try CalendarParser.parse(bytes, month: month)
        } catch let error as MeterError { throw error }
        catch { throw MeterError.transport }
    }
}
