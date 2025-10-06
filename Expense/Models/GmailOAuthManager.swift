import Foundation
import AuthenticationServices
import CryptoKit

final class GmailOAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GmailOAuthManager()
    private override init() {}

    // Configure these in Settings (stored in UserDefaults)
    private let clientIdKey = "GmailClientID"
    private let redirectUriKey = "GmailRedirectURI" // e.g., com.your.app:/oauth2redirect
    private let refreshKeychainKey = "GmailRefreshToken"
    private let accessTokenKeychainKey = "GmailAccessToken"
    private let accessTokenExpiryKey = "GmailAccessTokenExpiry"

    // Defaults (pre-configured)
    private let defaultClientId = "994409100325-sa3pn872or0shomru1fbk12rfn81t3cm.apps.googleusercontent.com"
    private let defaultRedirectUri = "com.googleusercontent.apps.994409100325-sa3pn872or0shomru1fbk12rfn81t3cm:/oauth2redirect"

    var clientId: String? {
        get {
            if let v = UserDefaults.standard.string(forKey: clientIdKey), !v.isEmpty { return v }
            return defaultClientId
        }
        set { if let v = newValue { UserDefaults.standard.set(v, forKey: clientIdKey) } else { UserDefaults.standard.removeObject(forKey: clientIdKey) } }
    }
    var redirectUri: String? {
        get {
            if let v = UserDefaults.standard.string(forKey: redirectUriKey), !v.isEmpty { return v }
            return defaultRedirectUri
        }
        set { if let v = newValue { UserDefaults.standard.set(v, forKey: redirectUriKey) } else { UserDefaults.standard.removeObject(forKey: redirectUriKey) } }
    }

    private var currentSession: ASWebAuthenticationSession?
    private var currentCodeVerifier: String?
    private var pendingCompletion: ((Bool, String?) -> Void)?

    private let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    // MARK: - Public
    func signIn(completion: @escaping (Bool, String?) -> Void) {
        guard let clientId = clientId, let redirect = redirectUri, let redirectURL = URL(string: redirect) else {
            completion(false, "Missing Client ID or Redirect URI in Settings")
            return
        }
        let (challenge, verifier) = Self.generatePKCE()
        currentCodeVerifier = verifier

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"), // request refresh token
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else {
            completion(false, "Failed to build auth URL")
            return
        }
        pendingCompletion = completion
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectURL.scheme) { [weak self] callbackURL, error in
            guard let self = self else { return }
            if let error = error {
                self.pendingCompletion?(false, error.localizedDescription)
                self.pendingCompletion = nil
                return
            }
            guard let url = callbackURL, let code = Self.extractQuery(from: url)["code"], let verifier = self.currentCodeVerifier else {
                self.pendingCompletion?(false, "Authorization code not found")
                self.pendingCompletion = nil
                return
            }
            self.exchangeCodeForTokens(code: code, codeVerifier: verifier) { success, message in
                self.pendingCompletion?(success, message)
                self.pendingCompletion = nil
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        currentSession = session
        _ = session.start()
    }

    func handleRedirect(_ url: URL) -> Bool {
        // Not needed when using ASWebAuthenticationSession; included for completeness.
        return false
    }

    func getValidAccessToken(completion: @escaping (String?) -> Void) {
        // If access token exists and not expired (minus safety), return it; else refresh
        let expiryMaybe: String?? = try? KeychainHelper.shared.getString(for: accessTokenExpiryKey)
        let tokenMaybe: String?? = try? KeychainHelper.shared.getString(for: accessTokenKeychainKey)
        let expiryStr: String? = expiryMaybe ?? nil
        let tokenStr: String? = tokenMaybe ?? nil
        if let expiryStr = expiryStr,
           let expiry = TimeInterval(expiryStr),
           Date().timeIntervalSince1970 < expiry - 60,
           let token = tokenStr {
            completion(token)
            return
        }
        // Refresh
        let refreshMaybe: String?? = try? KeychainHelper.shared.getString(for: refreshKeychainKey)
        let refreshTokenOpt: String? = refreshMaybe ?? nil
        guard let refreshToken = refreshTokenOpt else {
            completion(nil)
            return
        }
        refreshAccessToken(refreshToken: refreshToken) { token in
            completion(token)
        }
    }

    // MARK: - Token Exchange
    private func exchangeCodeForTokens(code: String, codeVerifier: String, completion: @escaping (Bool, String?) -> Void) {
        guard let clientId = clientId, let redirect = redirectUri else {
            completion(false, "Missing Client ID/Redirect URI")
            return
        }
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        let params: [String: String] = [
            "client_id": clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirect,
            "grant_type": "authorization_code"
        ]
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\(($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))!)" }.joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(false, error.localizedDescription); return }
            guard let data = data else { completion(false, "No data from token endpoint"); return }
            struct TokenResponse: Decodable { let access_token: String; let expires_in: Int; let refresh_token: String? }
            do {
                let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
                try? KeychainHelper.shared.setString(resp.access_token, for: self.accessTokenKeychainKey)
                let expiry = Date().timeIntervalSince1970 + Double(resp.expires_in)
                try? KeychainHelper.shared.setString(String(expiry), for: self.accessTokenExpiryKey)
                if let refresh = resp.refresh_token { try? KeychainHelper.shared.setString(refresh, for: self.refreshKeychainKey) }
                completion(true, nil)
            } catch {
                completion(false, "Token parse failed: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func refreshAccessToken(refreshToken: String, completion: @escaping (String?) -> Void) {
        guard let clientId = clientId else { completion(nil); return }
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        let params: [String: String] = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\(($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))!)" }.joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(nil); print("[GmailOAuth] Refresh error: \(error)"); return }
            guard let data = data else { completion(nil); return }
            struct TokenResponse: Decodable { let access_token: String; let expires_in: Int }
            if let resp = try? JSONDecoder().decode(TokenResponse.self, from: data) {
                try? KeychainHelper.shared.setString(resp.access_token, for: self.accessTokenKeychainKey)
                let expiry = Date().timeIntervalSince1970 + Double(resp.expires_in)
                try? KeychainHelper.shared.setString(String(expiry), for: self.accessTokenExpiryKey)
                completion(resp.access_token)
            } else {
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Helpers
    private static func extractQuery(from url: URL) -> [String: String] {
        var result: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            for item in items { result[item.name] = item.value }
        }
        return result
    }

    private static func generatePKCE() -> (challenge: String, verifier: String) {
        let verifier = randomURLSafeString(length: 64)
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (challenge, verifier)
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var result = ""
        for _ in 0..<length { result.append(chars.randomElement()!) }
        return result
    }

    // ASWebAuthenticationPresentationContextProviding
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}


