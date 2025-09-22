import Foundation

struct OutlookMessage: Decodable {
    let id: String
    let receivedDateTime: String
    let subject: String?
    let bodyPreview: String?
    let body: Body?
    let from: From?
    
    struct Body: Decodable { 
        let content: String? 
    }
    
    struct From: Decodable {
        let emailAddress: EmailAddress?
    }
    
    struct EmailAddress: Decodable {
        let address: String?
        let name: String?
    }
}

struct OutlookAttachment: Decodable {
    let id: String
    let name: String?
    let contentType: String?
    let size: Int?
    let isInline: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contentType
        case size
        case isInline
    }
}

private struct GraphMessagesResponse: Decodable {
    let value: [OutlookMessage]
    let nextLink: String?
    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct GraphAttachmentsResponse: Decodable {
    let value: [OutlookAttachment]
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
                    print("DEBUG: Fetching from URL: \(link)")
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    URLSession.shared.dataTask(with: req) { data, _, error in
                        if let error = error { completion(.failure(error)); return }
                        guard let data = data else { completion(.failure(NSError(domain: "Outlook", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"])) ); return }
                        do {
                            let response = try JSONDecoder().decode(GraphMessagesResponse.self, from: data)
                            print("DEBUG: Received \(response.value.count) messages in this batch")
                            messages.append(contentsOf: response.value)
                            nextLink = response.nextLink
                            if nextLink != nil && messages.count < 500 { // safety cap
                                print("DEBUG: Fetching next page, total so far: \(messages.count)")
                                fetchPage()
                            } else {
                                print("DEBUG: Finished fetching, total messages: \(messages.count)")
                                completion(.success(messages))
                            }
                        } catch {
                            print("DEBUG: JSON decode error: \(error)")
                            if let dataString = String(data: data, encoding: .utf8) {
                                print("DEBUG: Response data: \(dataString)")
                            }
                            completion(.failure(error))
                        }
                    }.resume()
                }
                fetchPage()
            }
        }
    }

    private func buildInitialUrl(since: Date?, sender: String?) -> String {
        // Microsoft Graph API has issues with $orderby and $search together
        // Use simpler approach with proper URL encoding
        
        if let sender = sender, !sender.isEmpty {
            // Use search for specific sender - this searches all folders automatically
            let searchQuery = "from:\(sender)"
            let encodedSearch = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
            var url = "https://graph.microsoft.com/v1.0/me/messages?$top=50&$select=id,subject,receivedDateTime,bodyPreview,body,from&$search=\"\(encodedSearch)\""
            
            // Add date filter if specified
            if let since = since {
                let iso = ISO8601DateFormatter().string(from: since)
                let dateQuery = "received>=\(iso)"
                url = url.replacingOccurrences(of: "$search=\"\(encodedSearch)\"", with: "$search=\"\(dateQuery) AND \(encodedSearch)\"")
            }
            
            return url
        } else {
            // For no sender filter, use standard messages endpoint with filter
            var url = "https://graph.microsoft.com/v1.0/me/messages?$top=50&$select=id,subject,receivedDateTime,bodyPreview,body,from&$orderby=receivedDateTime desc"
            
            // Add date filter if specified
            if let since = since {
                let iso = ISO8601DateFormatter().string(from: since)
                url += "&$filter=receivedDateTime gt \(iso)"
            }
            
            return url
        }
    }
    
    // MARK: - New Methods for AccountsView
    
    func fetchEmails(from sender: String) async throws -> [OutlookMessage] {
        return try await withCheckedThrowingContinuation { continuation in
            // Fetch all emails from this sender (no time limit)
            fetchRecentMessages(since: nil, sender: sender) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func fetchAttachments(for messageId: String) async throws -> [OutlookAttachment] {
        return try await withCheckedThrowingContinuation { continuation in
            getAccessToken { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let token):
                    let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(messageId)/attachments")!
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        guard let data = data else {
                            continuation.resume(throwing: NSError(domain: "OutlookService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                            return
                        }
                        
                        do {
                            let attachmentsResponse = try JSONDecoder().decode(GraphAttachmentsResponse.self, from: data)
                            continuation.resume(returning: attachmentsResponse.value)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }.resume()
                }
            }
        }
    }
    
    func downloadAttachment(messageId: String, attachmentId: String) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            getAccessToken { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let token):
                    let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(messageId)/attachments/\(attachmentId)/$value")!
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        continuation.resume(returning: data)
                    }.resume()
                }
            }
        }
    }
}


