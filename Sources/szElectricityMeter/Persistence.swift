import Foundation
import Security
import CryptoKit
import MeterCore

struct MeterConfiguration: Codable, Equatable {
    var areaCode = "090000"
    var customerID = ""
    var meteringPointID = ""
    var accountName = "深圳 · 我的家"
    var refreshMinutes = 60
    var tariff = Tariff()
    var menuStyle = "remaining"
    var appearance = "system"
    var notifyNearLimit = false
    var alertThreshold = 30.0
    var isComplete: Bool { !areaCode.isEmpty && !customerID.isEmpty && !meteringPointID.isEmpty }
    var accountKey: String {
        SHA256.hash(data: Data([areaCode, customerID, meteringPointID].joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum TokenVault {
    // Keep the original namespace so renaming the app does not lose existing credentials.
    private static let service = "cn.shenzhenmeter.credentials"
    private static let account = "csg-token"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw VaultError.unavailable }
        return value
    }
    static func save(_ token: String) throws {
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q.merge(attributes) { _, new in new }
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw VaultError.unavailable }
        } else if status != errSecSuccess { throw VaultError.unavailable }
    }
    enum VaultError: LocalizedError {
        case unavailable
        var errorDescription: String? { "无法访问系统钥匙串，请解锁钥匙串后重试。" }
    }
}

struct LocalStore {
    let directory: URL
    init() {
        // Stable on-disk namespace for installations made before the public project rename.
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ShenzhenMeter", isDirectory: true)
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func loadConfiguration() throws -> MeterConfiguration {
        let url = directory.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return MeterConfiguration() }
        let value = try JSONDecoder().decode(MeterConfiguration.self, from: Data(contentsOf: url))
        guard value.tariff.isValid else { throw MeterError.configuration }
        return value
    }
    func saveConfiguration(_ configuration: MeterConfiguration) throws {
        try write(configuration, to: directory.appendingPathComponent("settings.json"))
    }
    private func cacheURL(account: String) -> URL { directory.appendingPathComponent("usage-\(account).json") }
    func snapshots(account: String) -> [String: UsageSnapshot] {
        guard let data = try? Data(contentsOf: cacheURL(account: account)), let values = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data) else { return [:] }
        return values
    }
    func saveSnapshots(_ values: [String: UsageSnapshot], account: String) throws {
        let newest = values.keys.sorted().suffix(24)
        try write(values.filter { newest.contains($0.key) }, to: cacheURL(account: account))
    }
}
