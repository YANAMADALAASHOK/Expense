import Foundation
import AuthenticationServices
import CryptoKit

final class MicrosoftOAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MicrosoftOAuthManager()

    // Config
    private let clientId = "f2b5a207-b3fe-47b1-a1d3-93a6e790602b"
    private let redirectUri = "msauth.com.Astro.Expense://auth"
    private let tenant = "common" // or your tenant id
    private let scopes = ["openid", "profile", "offline_access", "Mail.Read"]

    // Keychain keys
    private let kAccessToken = "ms_access_token"
    private let kRefreshToken = "ms_refresh_token"
    private let kAccessTokenExpiry = "ms_access_token_expiry"

    private var currentSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            return window
        }
        #endif
        return ASPresentationAnchor()
    }

    // MARK: - Public API
    func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
        let (verifier, challenge) = pkce()
        let authURL = authorizationURL(codeChallenge: challenge)

        currentSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectUriScheme()) { [weak self] callbackURL, error in
            guard let self = self else { return }
            if let error = error { completion(.failure(error)); return }
            guard let url = callbackURL, let code = self.extractAuthCode(from: url) else {
                completion(.failure(NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth code"])) )
                return
            }
            self.exchangeCodeForToken(code: code, verifier: verifier) { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
        currentSession?.presentationContextProvider = self
        currentSession?.prefersEphemeralWebBrowserSession = true
        _ = currentSession?.start()
    }

    func handleRedirect(url: URL) -> Bool {
        // Not needed with ASWebAuthenticationSession; handled in the session closure
        return false
    }

    func getAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        // Return valid access token or refresh
        do {
            if let token = try KeychainHelper.shared.getString(for: kAccessToken),
               let expirySeconds = UserDefaults.standard.object(forKey: kAccessTokenExpiry) as? TimeInterval {
                let expiry = Date(timeIntervalSince1970: expirySeconds)
                if Date() < expiry.addingTimeInterval(-60) { // 60s skew
                    completion(.success(token))
                    return
                }
            }
            // refresh
            guard let refresh = try KeychainHelper.shared.getString(for: kRefreshToken) else {
                completion(.failure(NSError(domain: "OAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])) )
                return
            }
            refreshToken(refresh) { result in
                switch result {
                case .success(let token): completion(.success(token))
                case .failure(let err): completion(.failure(err))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Private helpers
    private func authorizationURL(codeChallenge: String) -> URL {
        var comps = URLComponents(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return comps.url!
    }

    private func extractAuthCode(from url: URL) -> String? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let item = comps.queryItems?.first(where: { $0.name == "code" }),
              let code = item.value else { return nil }
        return code
    }

    private func exchangeCodeForToken(code: String, verifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token")!)
        req.httpMethod = "POST"
        let bodyItems: [URLQueryItem] = [
            .init(name: "client_id", value: clientId),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirectUri),
            .init(name: "code_verifier", value: verifier),
            .init(name: "scope", value: scopes.joined(separator: " "))
        ]
        req.httpBody = bodyItems.percentEncoded().data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "OAuth", code: 0))); return }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let access = json?["access_token"] as? String,
                      let refresh = json?["refresh_token"] as? String,
                      let expiresIn = json?["expires_in"] as? Double else {
                    throw NSError(domain: "OAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Token parse failed"]) }
                try KeychainHelper.shared.setString(access, for: self.kAccessToken)
                try KeychainHelper.shared.setString(refresh, for: self.kRefreshToken)
                let expiry = Date().addingTimeInterval(expiresIn)
                UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: self.kAccessTokenExpiry)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func refreshToken(_ refresh: String, completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token")!)
        req.httpMethod = "POST"
        let bodyItems: [URLQueryItem] = [
            .init(name: "client_id", value: clientId),
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "refresh_token", value: refresh),
            .init(name: "redirect_uri", value: redirectUri)
        ]
        req.httpBody = bodyItems.percentEncoded().data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "OAuth", code: 0))); return }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let access = json?["access_token"] as? String,
                      let expiresIn = json?["expires_in"] as? Double else {
                    throw NSError(domain: "OAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Token parse failed"]) }
                try KeychainHelper.shared.setString(access, for: self.kAccessToken)
                if let newRefresh = json?["refresh_token"] as? String {
                    try KeychainHelper.shared.setString(newRefresh, for: self.kRefreshToken)
                }
                let expiry = Date().addingTimeInterval(expiresIn)
                UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: self.kAccessTokenExpiry)
                completion(.success(access))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func redirectUriScheme() -> String {
        if let scheme = URL(string: redirectUri)?.scheme { return scheme }
        return "msauth.com.Astro.Expense"
    }

    private func pkce() -> (verifier: String, challenge: String) {
        let verifier = randomURLSafeString(length: 64)
        let challenge = verifier.sha256Base64URL()
        return (verifier, challenge)
    }
}

// MARK: - Utils
private func randomURLSafeString(length: Int) -> String {
    let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    var s = ""
    for _ in 0..<length { s.append(chars.randomElement()!) }
    return s
}

private extension String {
    func sha256Base64URL() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        let digest = SHA256.hash(data: data)
        let b64 = Data(digest).base64EncodedString()
        return b64.replacingOccurrences(of: "+", with: "-")
                  .replacingOccurrences(of: "/", with: "_")
                  .replacingOccurrences(of: "=", with: "")
    }
}

private extension Array where Element == URLQueryItem {
    func percentEncoded() -> String {
        map { "\($0.name)=\(($0.value ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
    }
}


