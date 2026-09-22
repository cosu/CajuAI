import Foundation
import Security

/// Single Keychain item for every provider secret.
/// One item → one access prompt. In-memory cache so launch reads it once.
enum KeychainStore {
    private static let service = "ro.cosu.CajuAI"
    /// Historical account name; kept so existing Keychain ACLs still apply.
    private static let account = "claude_tokens"

    private static let legacyClaudeAccess = "claude_access_token"
    private static let legacyClaudeRefresh = "claude_refresh_token"
    private static let legacyClaudeExpiry = "claude_token_expires_at"
    private static let legacyDeepSeek = "deepseek_api_key"
    private static let legacyOpenRouter = "openrouter_api_key"

    struct Secrets: Codable {
        var claude: ClaudeTokens?
        var deepseekApiKey: String?
        var openrouterApiKey: String?

        var isEmpty: Bool {
            claude == nil && deepseekApiKey == nil && openrouterApiKey == nil
        }
    }

    struct ClaudeTokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: TimeInterval
    }

    private static var cached: Secrets?
    private static var loaded = false

    static func load() -> Secrets {
        if loaded { return cached ?? Secrets() }
        loaded = true
        migrateIfNeeded()
        return cached ?? Secrets()
    }

    static func update(_ mutate: (inout Secrets) -> Void) {
        var secrets = load()
        mutate(&secrets)
        cached = secrets
        persist(secrets)
    }

    // MARK: - Persist

    private static func persist(_ secrets: Secrets) {
        if secrets.isEmpty {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(secrets) else { return }
        var query = baseQuery()
        let fields: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, fields as CFDictionary) == errSecItemNotFound {
            query[kSecValueData] = data
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecAttrLabel] = "CajuAI"
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func readAccount(_ account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func deleteAccount(_ account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
    }

    // MARK: - Migration

    private static func migrateIfNeeded() {
        if let data = readAccount(account), let secrets = decodeSecrets(data) {
            var merged = secrets
            let pulled = pullProviderKeys(into: &merged)
            cached = merged
            if pulled { persist(merged) }
            return
        }

        var secrets = Secrets()
        secrets.claude = loadLegacyClaudeTokens()
        _ = pullProviderKeys(into: &secrets)
        cached = secrets
        if !secrets.isEmpty {
            persist(secrets)
        }
        deleteLegacyClaudeUserDefaults()
    }

    /// Returns true if DeepSeek/OpenRouter keys were copied out of their old items.
    private static func pullProviderKeys(into secrets: inout Secrets) -> Bool {
        var changed = false
        if secrets.deepseekApiKey == nil,
           let data = readAccount(legacyDeepSeek),
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            secrets.deepseekApiKey = key
            deleteAccount(legacyDeepSeek)
            changed = true
        }
        if secrets.openrouterApiKey == nil,
           let data = readAccount(legacyOpenRouter),
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            secrets.openrouterApiKey = key
            deleteAccount(legacyOpenRouter)
            changed = true
        }
        return changed
    }

    private static func decodeSecrets(_ data: Data) -> Secrets? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return try? JSONDecoder().decode(Secrets.self, from: data)
        }
        if obj["claude"] != nil || obj["deepseekApiKey"] != nil || obj["openrouterApiKey"] != nil {
            return try? JSONDecoder().decode(Secrets.self, from: data)
        }
        if obj["accessToken"] != nil,
           let tokens = try? JSONDecoder().decode(ClaudeTokens.self, from: data) {
            return Secrets(claude: tokens)
        }
        return try? JSONDecoder().decode(Secrets.self, from: data)
    }

    private static func loadLegacyClaudeTokens() -> ClaudeTokens? {
        let defaults = UserDefaults.standard
        let access = defaults.string(forKey: legacyClaudeAccess)
            ?? readAccount(legacyClaudeAccess).flatMap { String(data: $0, encoding: .utf8) }
        guard let access else { return nil }

        let refresh = defaults.string(forKey: legacyClaudeRefresh)
            ?? readAccount(legacyClaudeRefresh).flatMap { String(data: $0, encoding: .utf8) }

        var expiresAt = Date().addingTimeInterval(3600).timeIntervalSince1970
        if let raw = defaults.string(forKey: legacyClaudeExpiry)
            ?? readAccount(legacyClaudeExpiry).flatMap { String(data: $0, encoding: .utf8) },
           let interval = TimeInterval(raw) {
            expiresAt = interval
        } else if let date = defaults.object(forKey: legacyClaudeExpiry) as? Date {
            expiresAt = date.timeIntervalSince1970
        }

        [legacyClaudeAccess, legacyClaudeRefresh, legacyClaudeExpiry].forEach {
            defaults.removeObject(forKey: $0)
            deleteAccount($0)
        }
        return ClaudeTokens(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    private static func deleteLegacyClaudeUserDefaults() {
        let defaults = UserDefaults.standard
        [legacyClaudeAccess, legacyClaudeRefresh, legacyClaudeExpiry].forEach {
            defaults.removeObject(forKey: $0)
        }
    }
}
