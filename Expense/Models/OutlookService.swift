import Foundation

struct OutlookMessage: Decodable {
    let id: String
    let receivedDateTime: String
    let subject: String?
    let bodyPreview: String?
    let body: Body?
    struct Body: Decodable { let content: String? }
}

private struct GraphMessagesResponse: Decodable {
    let value: [OutlookMessage]
    let nextLink: String?
    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

final class OutlookService {
    static let shared = OutlookService()
    private init() {}

    // MARK: - MSAL placeholders (to be wired with MSAL)
    var clientId: String = "f2b5a207-b3fe-47b1-a1d3-93a6e790602b"
    var redirectUri: String = "msauth.com.Astro.Expense://auth"
    var scopes: [String] = ["Mail.Read", "openid", "profile", "offline_access"]

    func getAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        MicrosoftOAuthManager.shared.getAccessToken(completion: completion)
    }

    func fetchRecentMessages(since: Date?, sender: String? = nil, completion: @escaping (Result<[OutlookMessage], Error>) -> Void) {
        getAccessToken { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let token):
                var messages: [OutlookMessage] = []
                var nextLink: String? = self.buildInitialUrl(since: since, sender: sender)
                func fetchPage() {
                    guard let link = nextLink, let url = URL(string: link) else { completion(.success(messages)); return }
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    URLSession.shared.dataTask(with: req) { data, _, error in
                        if let error = error { completion(.failure(error)); return }
                        guard let data = data else { completion(.failure(NSError(domain: "Outlook", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"])) ); return }
                        do {
                            let response = try JSONDecoder().decode(GraphMessagesResponse.self, from: data)
                            messages.append(contentsOf: response.value)
                            nextLink = response.nextLink
                            if nextLink != nil && messages.count < 500 { // safety cap
                                fetchPage()
                            } else {
                                completion(.success(messages))
                            }
                        } catch {
                            completion(.failure(error))
                        }
                    }.resume()
                }
                fetchPage()
            }
        }
    }

    private func buildInitialUrl(since: Date?, sender: String?) -> String {
        var url = "https://graph.microsoft.com/v1.0/me/messages?$top=25&$select=id,subject,receivedDateTime,bodyPreview,body&$orderby=receivedDateTime%20desc"
        var filters: [String] = []
        if let since = since {
            let iso = ISO8601DateFormatter().string(from: since)
            filters.append("receivedDateTime gt \(iso)")
        }
        if let sender = sender, !sender.isEmpty {
            // Filter by sender address
            filters.append("from/emailAddress/address eq '\(sender)'")
        }
        if !filters.isEmpty {
            let filter = filters.joined(separator: " and ")
            url += "&$filter=\(filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filter)"
        }
        return url
    }
}


