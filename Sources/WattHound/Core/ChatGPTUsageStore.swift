import AppKit
import Foundation
import Security

struct ChatGPTUsageWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowSeconds: TimeInterval
    let resetsAt: Date?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct ChatGPTUsageSnapshot: Codable, Equatable, Sendable {
    let plan: String?
    let session: ChatGPTUsageWindow?
    let weekly: ChatGPTUsageWindow?
    let isAllowed: Bool
    let fetchedAt: Date
}

@MainActor
final class ChatGPTUsageStore: ObservableObject {
    @Published private(set) var usage: ChatGPTUsageSnapshot?
    @Published private(set) var isConnected = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var deviceCode: String?
    @Published private(set) var errorMessage: String?

    private static let usageCacheKey = "chatGPTUsageSnapshot"

    private let session: URLSession
    private let credentialStore: ChatGPTCredentialStore
    private let notificationService = NotificationService()
    private var credential: ChatGPTCredential?
    private var refreshTimer: Timer?
    private var authenticationTask: Task<Void, Never>?

    init(
        session: URLSession = .shared,
        credentialStore: ChatGPTCredentialStore = .init()
    ) {
        self.session = session
        self.credentialStore = credentialStore
        let credential = credentialStore.load()
        self.credential = credential
        isConnected = credential != nil
        usage = credential == nil ? nil : Self.loadCachedUsage()
    }

    func start() {
        guard refreshTimer == nil else { return }
        if UserDefaults.standard.object(forKey: "chatGPTUsageNotificationsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "chatGPTUsageNotificationsEnabled")
            Task { _ = await notificationService.requestAuthorization() }
        }
        if isConnected { Task { await refresh() } }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isConnected else { return }
                await self.refresh()
            }
        }
    }

    func connect() {
        guard authenticationTask == nil else { return }
        authenticationTask = Task { [weak self] in
            guard let self else { return }
            await self.authenticateWithDeviceCode()
            self.authenticationTask = nil
        }
    }

    func cancelAuthentication() {
        authenticationTask?.cancel()
        isAuthenticating = false
        deviceCode = nil
    }

    func disconnect() {
        cancelAuthentication()
        credentialStore.delete()
        credential = nil
        usage = nil
        UserDefaults.standard.removeObject(forKey: Self.usageCacheKey)
        isConnected = false
        errorMessage = nil
    }

    func refresh() async {
        guard !isRefreshing, var credential else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if credential.expiresAt.timeIntervalSinceNow < 300 {
                credential = try await refreshCredential(credential)
                try credentialStore.save(credential)
                self.credential = credential
            }
            let previousUsage = usage
            let snapshot = try await fetchUsage(using: credential)
            usage = snapshot
            cache(snapshot)
            isConnected = true
            errorMessage = nil
            await notificationService.evaluateChatGPT(
                previous: previousUsage,
                current: snapshot,
                enabled: UserDefaults.standard.bool(forKey: "chatGPTUsageNotificationsEnabled")
            )
        } catch ChatGPTUsageError.unauthorized {
            self.credential = nil
            usage = nil
            UserDefaults.standard.removeObject(forKey: Self.usageCacheKey)
            isConnected = false
            errorMessage = "Your ChatGPT sign-in expired. Connect again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func authenticateWithDeviceCode() async {
        isAuthenticating = true
        errorMessage = nil
        deviceCode = nil
        defer {
            isAuthenticating = false
            deviceCode = nil
        }

        do {
            let device = try await requestDeviceCode()
            deviceCode = device.userCode
            NSWorkspace.shared.open(ChatGPTEndpoints.deviceVerification)

            let authorization = try await pollForAuthorization(device)
            let credential = try await exchangeAuthorization(authorization)
            try Task.checkCancellation()
            try credentialStore.save(credential)
            self.credential = credential
            isConnected = true
            let snapshot = try await fetchUsage(using: credential)
            usage = snapshot
            cache(snapshot)
            errorMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: ChatGPTEndpoints.deviceCode, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": ChatGPTEndpoints.clientID])
        return try await decode(DeviceCodeResponse.self, from: request)
    }

    private func pollForAuthorization(_ device: DeviceCodeResponse) async throws -> DeviceAuthorization {
        let deadline = Date().addingTimeInterval(15 * 60)
        var delay = max(1, device.intervalSeconds)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(delay))

            var request = URLRequest(url: ChatGPTEndpoints.deviceToken, timeoutInterval: 12)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_auth_id": device.deviceAuthID,
                "user_code": device.userCode
            ])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatGPTUsageError.invalidResponse }
            if http.statusCode == 200 {
                return try JSONDecoder().decode(DeviceAuthorization.self, from: data)
            }
            if http.statusCode == 403 || http.statusCode == 404 { continue }

            if let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data),
               oauthError.code == "slow_down" {
                delay += 5
                continue
            }
            throw ChatGPTUsageError.httpStatus(http.statusCode)
        }
        throw ChatGPTUsageError.authenticationTimedOut
    }

    private func exchangeAuthorization(_ authorization: DeviceAuthorization) async throws -> ChatGPTCredential {
        var request = URLRequest(url: ChatGPTEndpoints.token, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "client_id": ChatGPTEndpoints.clientID,
            "code": authorization.authorizationCode,
            "code_verifier": authorization.codeVerifier,
            "redirect_uri": ChatGPTEndpoints.deviceRedirect.absoluteString
        ])
        return try await tokenCredential(from: request)
    }

    private func refreshCredential(_ credential: ChatGPTCredential) async throws -> ChatGPTCredential {
        var request = URLRequest(url: ChatGPTEndpoints.token, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": credential.refreshToken,
            "client_id": ChatGPTEndpoints.clientID
        ])
        return try await tokenCredential(from: request)
    }

    private func tokenCredential(from request: URLRequest) async throws -> ChatGPTCredential {
        let token = try await decode(TokenResponse.self, from: request)
        guard let accountID = Self.accountID(fromJWT: token.accessToken) else {
            throw ChatGPTUsageError.missingAccountID
        }
        return ChatGPTCredential(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn),
            accountID: accountID
        )
    }

    private func fetchUsage(using credential: ChatGPTCredential) async throws -> ChatGPTUsageSnapshot {
        var request = URLRequest(url: ChatGPTEndpoints.usage, timeoutInterval: 12)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("WattHound/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTUsageError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatGPTUsageError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ChatGPTUsageError.httpStatus(http.statusCode) }
        guard let snapshot = Self.parseUsage(data) else { throw ChatGPTUsageError.invalidResponse }
        return snapshot
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from request: URLRequest) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTUsageError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ChatGPTUsageError.httpStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ChatGPTUsageError.invalidResponse
        }
    }

    private func formBody(_ fields: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func cache(_ snapshot: ChatGPTUsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.usageCacheKey)
    }

    private static func loadCachedUsage() -> ChatGPTUsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: usageCacheKey) else { return nil }
        return try? JSONDecoder().decode(ChatGPTUsageSnapshot.self, from: data)
    }

    nonisolated static func parseUsage(_ data: Data, now: Date = .now) -> ChatGPTUsageSnapshot? {
        guard let response = try? JSONDecoder().decode(UsageResponse.self, from: data) else { return nil }
        var session: ChatGPTUsageWindow?
        var weekly: ChatGPTUsageWindow?

        for rawWindow in [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow].compactMap({ $0 }) {
            let window = ChatGPTUsageWindow(
                usedPercent: max(0, min(100, rawWindow.usedPercent)),
                windowSeconds: rawWindow.windowSeconds,
                resetsAt: rawWindow.resetAt.map { Date(timeIntervalSince1970: $0) }
            )
            if rawWindow.windowSeconds > 0 && rawWindow.windowSeconds <= 86_400 {
                session = window
            } else {
                weekly = window
            }
        }

        guard session != nil || weekly != nil else { return nil }
        return ChatGPTUsageSnapshot(
            plan: response.planType,
            session: session,
            weekly: weekly,
            isAllowed: response.rateLimit?.allowed ?? true,
            fetchedAt: now
        )
    }

    nonisolated static func accountID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = root["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }
        return auth["chatgpt_account_id"] as? String
    }
}

struct ChatGPTCredential: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let accountID: String
}

struct ChatGPTCredentialStore: Sendable {
    private let service = "com.cristiandlahoz.watthound.chatgpt"
    private let account = "oauth"

    func load() -> ChatGPTCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredential.self, from: data)
    }

    func save(_ credential: ChatGPTCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw ChatGPTUsageError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw ChatGPTUsageError.keychain(status)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum ChatGPTEndpoints {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let deviceCode = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
    static let deviceToken = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    static let deviceVerification = URL(string: "https://auth.openai.com/codex/device")!
    static let deviceRedirect = URL(string: "https://auth.openai.com/deviceauth/callback")!
    static let token = URL(string: "https://auth.openai.com/oauth/token")!
    static let usage = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
}

private struct DeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let intervalSeconds: Double

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case intervalSeconds = "interval"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try values.decode(String.self, forKey: .deviceAuthID)
        userCode = try values.decode(String.self, forKey: .userCode)
        if let number = try? values.decode(Double.self, forKey: .intervalSeconds) {
            intervalSeconds = number
        } else {
            let value = try values.decode(String.self, forKey: .intervalSeconds)
            guard let number = Double(value) else { throw ChatGPTUsageError.invalidResponse }
            intervalSeconds = number
        }
    }
}

private struct DeviceAuthorization: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthErrorResponse: Decodable {
    let code: String?

    enum CodingKeys: String, CodingKey { case error }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? values.decode(String.self, forKey: .error) {
            code = text
        } else if let details = try? values.decode([String: String].self, forKey: .error) {
            code = details["code"]
        } else {
            code = nil
        }
    }
}

private struct UsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable {
        let allowed: Bool?
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case allowed
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowSeconds: TimeInterval
        let resetAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }
}

enum ChatGPTUsageError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unauthorized
    case missingAccountID
    case authenticationTimedOut
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "ChatGPT returned an unexpected response."
        case let .httpStatus(status): "ChatGPT usage request failed (HTTP \(status))."
        case .unauthorized: "Your ChatGPT sign-in expired."
        case .missingAccountID: "The ChatGPT sign-in did not include an account."
        case .authenticationTimedOut: "ChatGPT sign-in timed out. Try again."
        case let .keychain(status): "Couldn’t save ChatGPT sign-in to Keychain (\(status))."
        }
    }
}
