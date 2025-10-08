import Foundation

// Gmail message structure to match OutlookMessage interface
struct GmailMessage: Decodable {
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

struct GmailAttachment: Decodable {
    let id: String
    let name: String?
    let contentType: String?
    let size: Int?
    let isInline: Bool?
}

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
    let attachmentId: String?
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
        guard let token = try? KeychainHelper.shared.getString(for: "GmailRefreshToken") else {
            return false
        }
        return !token.isEmpty
    }

    func signOut() {
        try? KeychainHelper.shared.deleteString(for: "GmailRefreshToken")
        try? KeychainHelper.shared.deleteString(for: "GmailAccessToken")
        try? KeychainHelper.shared.deleteString(for: "GmailAccessTokenExpiry")
        print("DEBUG: 🔓 Gmail tokens deleted from Keychain")
    }

    // MARK: - Fetch
    func fetchICICIMessages(since: Date?, max: Int = 25, completion: @escaping (Result<[(subject: String, body: String, received: Date)], Error>) -> Void) {
        fetchMessages(query: "from:icicibank", since: since, max: max, completion: completion)
    }
    
    // MARK: - New Methods for Credit Card Statements (similar to OutlookService)
    
    func fetchEmails(from sender: String) async throws -> [GmailMessage] {
        return try await withCheckedThrowingContinuation { continuation in
            fetchGmailMessages(query: "from:\(sender)", since: nil, max: 500) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func fetchAttachments(for messageId: String) async throws -> [GmailAttachment] {
        print("DEBUG: 🚀 Gmail fetchAttachments called for messageId: \(messageId)")
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                GmailOAuthManager.shared.getValidAccessToken { token in
                guard let token = token else {
                    continuation.resume(throwing: NSError(domain: "Gmail", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in to Gmail"]))
                    return
                }
                
                let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=full")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let httpResponse = response as? HTTPURLResponse {
                        print("DEBUG: Gmail API status code: \(httpResponse.statusCode)")
                    }
                    
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let data = data else {
                        continuation.resume(throwing: NSError(domain: "GmailService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                        return
                    }
                    
                    // Log the raw response for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("DEBUG: Gmail API response: \(responseString.prefix(500))...")
                    }
                    
                    do {
                        let message = try JSONDecoder().decode(GmailMessageFull.self, from: data)
                        print("DEBUG: Gmail message payload parts count: \(message.payload?.parts?.count ?? 0)")
                        if let parts = message.payload?.parts {
                            for (index, part) in parts.enumerated() {
                                print("DEBUG: Gmail part \(index): filename='\(part.filename ?? "none")', mimeType='\(part.mimeType ?? "none")', size=\(part.body?.size ?? 0)")
                            }
                        }
                        let attachments = self.extractAttachments(from: message)
                        continuation.resume(returning: attachments)
                    } catch {
                        print("DEBUG: Gmail attachment parsing error: \(error)")
                        continuation.resume(throwing: error)
                    }
                }.resume()
                }
            }
        }
    }
    
    func downloadAttachment(messageId: String, attachmentId: String) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            print("DEBUG: Gmail downloading attachment - MessageID: \(messageId), AttachmentID: \(attachmentId)")
            
            Task { @MainActor in
                GmailOAuthManager.shared.getValidAccessToken { token in
                guard let token = token else {
                    print("DEBUG: Gmail download failed - No access token")
                    continuation.resume(throwing: NSError(domain: "Gmail", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in to Gmail"]))
                    return
                }
                
                let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/attachments/\(attachmentId)")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                print("DEBUG: Gmail download URL: \(url.absoluteString)")
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("DEBUG: Gmail download network error: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("DEBUG: Gmail download HTTP status: \(httpResponse.statusCode)")
                    }
                    
                    guard let data = data else {
                        print("DEBUG: Gmail download - No data received")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    print("DEBUG: Gmail download - Received \(data.count) bytes")
                    
                    do {
                        // Gmail returns attachment data in a specific format
                        let attachmentResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        if let attachmentData = attachmentResponse?["data"] as? String {
                            print("DEBUG: Gmail download - Found base64 data, length: \(attachmentData.count)")
                            // Decode base64url encoded data
                            let normalized = attachmentData.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                            let decodedData = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters])
                            print("DEBUG: Gmail download - Decoded to \(decodedData?.count ?? 0) bytes")
                            continuation.resume(returning: decodedData)
                        } else {
                            print("DEBUG: Gmail download - No 'data' field in response")
                            if let responseString = String(data: data, encoding: .utf8) {
                                print("DEBUG: Gmail download response: \(responseString.prefix(200))")
                            }
                            continuation.resume(returning: nil)
                        }
                    } catch {
                        print("DEBUG: Gmail download JSON parsing error: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }.resume()
                }
            }
        }
    }
    
    private func fetchGmailMessages(query: String, since: Date?, max: Int, completion: @escaping (Result<[GmailMessage], Error>) -> Void) {
        GmailOAuthManager.shared.getValidAccessToken { token in
            guard let token = token else {
                completion(.failure(NSError(domain: "Gmail", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in to Gmail"])))
                return
            }
            
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
                if let error = error { 
                    completion(.failure(error))
                    return 
                }
                guard let data = data else { 
                    completion(.failure(NSError(domain: "Gmail", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                    return 
                }
                
                do {
                    let list = try JSONDecoder().decode(GmailListResponse.self, from: data)
                    let ids = list.messages?.map { $0.id } ?? []
                    if ids.isEmpty { 
                        completion(.success([]))
                        return 
                    }
                    
                    self.fetchFullGmailMessages(ids: ids, token: token) { result in
                        switch result {
                        case .failure(let err): 
                            completion(.failure(err))
                        case .success(let fulls):
                            let gmailMessages: [GmailMessage] = fulls.compactMap { full in
                                self.convertToGmailMessage(from: full)
                            }
                            completion(.success(gmailMessages))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
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
    
    // MARK: - Helper Methods for Gmail Message Conversion
    
    private func fetchFullGmailMessages(ids: [String], token: String, completion: @escaping (Result<[GmailMessageFull], Error>) -> Void) {
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
                if let error = error { 
                    anyError = error
                    return 
                }
                guard let data = data else { 
                    anyError = NSError(domain: "Gmail", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"])
                    return 
                }
                
                if let msg = try? JSONDecoder().decode(GmailMessageFull.self, from: data) {
                    lock.lock()
                    results.append(msg)
                    lock.unlock()
                }
            }.resume()
        }
        
        group.notify(queue: .main) {
            if let err = anyError { 
                completion(.failure(err)) 
            } else { 
                completion(.success(results)) 
            }
        }
    }
    
    private func convertToGmailMessage(from full: GmailMessageFull) -> GmailMessage? {
        guard let headers = full.payload?.headers else { return nil }
        
        let subject = headers.first(where: { $0.name.caseInsensitiveCompare("Subject") == .orderedSame })?.value
        let fromHeader = headers.first(where: { $0.name.caseInsensitiveCompare("From") == .orderedSame })?.value
        let dateHeader = headers.first(where: { $0.name.caseInsensitiveCompare("Date") == .orderedSame })?.value
        
        // Parse the date from header or use internal date
        let receivedDateTime: String
        if let dateHeader = dateHeader {
            receivedDateTime = dateHeader
        } else if let internalDate = full.internalDate {
            receivedDateTime = internalDate
        } else {
            receivedDateTime = ISO8601DateFormatter().string(from: Date())
        }
        
        // Extract email address from "Name <email@domain.com>" format
        var emailAddress: GmailMessage.EmailAddress?
        var _ = ""  // fromName was never read
        
        if let fromHeader = fromHeader {
            if let emailMatch = fromHeader.range(of: #"<(.+?)>"#, options: .regularExpression) {
                let email = String(fromHeader[emailMatch]).replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
                let name = fromHeader.replacingOccurrences(of: #"\s*<.+?>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                emailAddress = GmailMessage.EmailAddress(address: email, name: name.isEmpty ? nil : name)
            } else {
                emailAddress = GmailMessage.EmailAddress(address: fromHeader, name: nil)
            }
        }
        
        let from = emailAddress != nil ? GmailMessage.From(emailAddress: emailAddress) : nil
        let bodyContent = extractBody(from: full)
        let body = GmailMessage.Body(content: bodyContent.isEmpty ? nil : bodyContent)
        
        return GmailMessage(
            id: full.id,
            receivedDateTime: receivedDateTime,
            subject: subject,
            bodyPreview: full.snippet,
            body: body,
            from: from
        )
    }
    
    private func extractAttachments(from message: GmailMessageFull) -> [GmailAttachment] {
        var attachments: [GmailAttachment] = []
        
        func processPayloadPart(_ part: GmailPayloadPart, partId: String = "") {
            // Check if this part has a filename (indicates attachment)
            if let filename = part.filename, !filename.isEmpty {
                // For Gmail, we need the actual attachmentId from the body, not the part index
                let attachmentId = part.body?.attachmentId ?? partId
                
                let attachment = GmailAttachment(
                    id: attachmentId,
                    name: filename,
                    contentType: part.mimeType,
                    size: part.body?.size,
                    isInline: false
                )
                attachments.append(attachment)
                print("DEBUG: Gmail attachment found - ID: \(attachmentId), Name: \(filename), Size: \(part.body?.size ?? 0)")
            }
            
            // Process nested parts
            if let nestedParts = part.parts {
                for (index, nestedPart) in nestedParts.enumerated() {
                    processPayloadPart(nestedPart, partId: "\(partId).\(index)")
                }
            }
        }
        
        // Process all parts of the message
        if let parts = message.payload?.parts {
            for (index, part) in parts.enumerated() {
                processPayloadPart(part, partId: String(index))
            }
        }
        
        print("DEBUG: Gmail extracted \(attachments.count) attachments")
        return attachments
    }
}


