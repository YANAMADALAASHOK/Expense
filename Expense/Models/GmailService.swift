import Foundation

struct GmailSimpleMessage: Decodable {
    let id: String
    let threadId: String?
}

private struct GmailListResponse: Decodable {
    let messages: [GmailSimpleMessage]?
    let nextPageToken: String?
}

private struct GmailPayloadPart: Decodable {
    let mimeType: String?
    let filename: String?
    let body: GmailBody?
    let parts: [GmailPayloadPart]?
}

private struct GmailBody: Decodable {
    let size: Int?
    let data: String?
}

private struct GmailMessageFull: Decodable {
    struct Header: Decodable { let name: String; let value: String }
    struct Payload: Decodable { let mimeType: String?; let body: GmailBody?; let parts: [GmailPayloadPart]?; let headers: [Header]? }
    let id: String
    let internalDate: String?
    let snippet: String?
    let payload: Payload?
}

final class GmailService {
    static let shared = GmailService()
    private init() {}

    var isSignedIn: Bool {
        (try? KeychainHelper.shared.getString(for: "GmailRefreshToken")) != nil
    }

    func signOut() {
        try? KeychainHelper.shared.setString("", for: "GmailRefreshToken")
        try? KeychainHelper.shared.setString("", for: "GmailAccessToken")
        try? KeychainHelper.shared.setString("0", for: "GmailAccessTokenExpiry")
    }

    // MARK: - Fetch
    func fetchICICIMessages(since: Date?, max: Int = 25, completion: @escaping (Result<[(subject: String, body: String, received: Date)], Error>) -> Void) {
        fetchMessages(query: "from:icicibank", since: since, max: max, completion: completion)
    }

    func fetchMessages(query: String, since: Date?, max: Int = 25, completion: @escaping (Result<[(subject: String, body: String, received: Date)], Error>) -> Void) {
        GmailOAuthManager.shared.getValidAccessToken { token in
            guard let token = token else {
                completion(.failure(NSError(domain: "Gmail", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in to Gmail"])) )
                return
            }
            self.fetchListAndBodies(query: query, since: since, max: max, token: token, completion: completion)
        }
    }

    private func fetchListAndBodies(query: String, since: Date?, max: Int, token: String, completion: @escaping (Result<[(subject: String, body: String, received: Date)], Error>) -> Void) {
        var q = query
        if let since = since {
            let df = DateFormatter()
            df.dateFormat = "yyyy/MM/dd"
            q += " after:\(df.string(from: since))"
        }
        let encodedQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let listUrl = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(encodedQ)&maxResults=\(max)")!
        var req = URLRequest(url: listUrl)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "Gmail", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"]))); return }
            do {
                let list = try JSONDecoder().decode(GmailListResponse.self, from: data)
                let ids = list.messages?.map { $0.id } ?? []
                if ids.isEmpty { completion(.success([])); return }
                self.fetchFullMessages(ids: ids, token: token) { result in
                    switch result {
                    case .failure(let err): completion(.failure(err))
                    case .success(let fulls):
                        let mapped: [(String,String,Date)] = fulls.compactMap { full in
                            let subject = full.payload?.headers?.first(where: { $0.name.caseInsensitiveCompare("Subject") == .orderedSame })?.value ?? full.snippet ?? "(No subject)"
                            let date = self.parseInternalDate(full.internalDate) ?? Date()
                            let body = self.extractBody(from: full)
                            return (subject, body, date)
                        }
                        completion(.success(mapped))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func fetchFullMessages(ids: [String], token: String, completion: @escaping (Result<[GmailMessageFull], Error>) -> Void) {
        let group = DispatchGroup()
        var results: [GmailMessageFull] = []
        var anyError: Error?
        let lock = NSLock()
        for id in ids {
            group.enter()
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, _, error in
                defer { group.leave() }
                if let error = error { anyError = error; return }
                guard let data = data else { anyError = NSError(domain: "Gmail", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"]); return }
                if let msg = try? JSONDecoder().decode(GmailMessageFull.self, from: data) {
                    lock.lock(); results.append(msg); lock.unlock()
                }
            }.resume()
        }
        group.notify(queue: .main) {
            if let err = anyError { completion(.failure(err)) } else { completion(.success(results)) }
        }
    }

    private func parseInternalDate(_ internalDate: String?) -> Date? {
        guard let msStr = internalDate, let ms = Double(msStr) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    private func extractBody(from full: GmailMessageFull) -> String {
        func decodeBody(_ body: GmailBody?) -> String {
            guard let b64 = body?.data else { return "" }
            let normalized = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]), let text = String(data: data, encoding: .utf8) {
                return EmailParser.htmlToPlainText(text)
            }
            return ""
        }
        guard let root = full.payload else { return full.snippet ?? "" }

        // DFS collect bodies
        var plainCandidate: String = ""
        var htmlCandidate: String = ""
        var stack: [GmailPayloadPart] = root.parts ?? []
        while !stack.isEmpty {
            let p = stack.removeFirst()
            let mime = (p.mimeType ?? "").lowercased()
            if mime.contains("text/plain"), plainCandidate.isEmpty {
                plainCandidate = decodeBody(p.body)
            } else if mime.contains("text/html"), htmlCandidate.isEmpty {
                htmlCandidate = decodeBody(p.body)
            }
            if let nested = p.parts { stack.append(contentsOf: nested) }
        }
        if !plainCandidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainCandidate
        }
        if !htmlCandidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return htmlCandidate
        }
        // Fallbacks
        let rootBody = decodeBody(root.body)
        if !rootBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return rootBody }
        return full.snippet ?? ""
    }
}


