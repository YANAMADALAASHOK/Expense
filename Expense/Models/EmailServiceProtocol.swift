import Foundation

// Protocol to unify Outlook and Gmail services
protocol EmailServiceProtocol {
    func fetchEmails(from sender: String) async throws -> [EmailMessage]
    func fetchAttachments(for messageId: String) async throws -> [EmailAttachment]
    func downloadAttachment(messageId: String, attachmentId: String) async throws -> Data?
}

// Unified email message structure
struct EmailMessage {
    let id: String
    let receivedDateTime: String
    let subject: String?
    let bodyPreview: String?
    let body: EmailBody?
    let from: EmailFrom?
    
    struct EmailBody {
        let content: String?
    }
    
    struct EmailFrom {
        let emailAddress: EmailAddress?
    }
    
    struct EmailAddress {
        let address: String?
        let name: String?
    }
}

// Unified attachment structure
struct EmailAttachment {
    let id: String
    let name: String?
    let contentType: String?
    let size: Int?
    let isInline: Bool?
}

// Email service manager to handle both Outlook and Gmail
class EmailServiceManager {
    static let shared = EmailServiceManager()
    private init() {}
    
    enum EmailProvider {
        case outlook
        case gmail
    }
    
    var preferredProvider: EmailProvider = .outlook
    
    func getEmailService() -> EmailServiceProtocol {
        switch preferredProvider {
        case .outlook:
            return OutlookEmailServiceAdapter()
        case .gmail:
            return GmailEmailServiceAdapter()
        }
    }
    
    func isSignedIn(provider: EmailProvider) -> Bool {
        switch provider {
        case .outlook:
            // Check if Outlook is signed in (implement based on your OAuth setup)
            return true // Placeholder
        case .gmail:
            return GmailService.shared.isSignedIn
        }
    }
}

// Adapter for OutlookService to conform to EmailServiceProtocol
class OutlookEmailServiceAdapter: EmailServiceProtocol {
    private let outlookService = OutlookService.shared
    
    func fetchEmails(from sender: String) async throws -> [EmailMessage] {
        let outlookMessages = try await outlookService.fetchEmails(from: sender)
        return outlookMessages.map { convertToEmailMessage($0) }
    }
    
    func fetchAttachments(for messageId: String) async throws -> [EmailAttachment] {
        let outlookAttachments = try await outlookService.fetchAttachments(for: messageId)
        return outlookAttachments.map { convertToEmailAttachment($0) }
    }
    
    func downloadAttachment(messageId: String, attachmentId: String) async throws -> Data? {
        return try await outlookService.downloadAttachment(messageId: messageId, attachmentId: attachmentId)
    }
    
    private func convertToEmailMessage(_ outlook: OutlookMessage) -> EmailMessage {
        let body = outlook.body != nil ? EmailMessage.EmailBody(content: outlook.body?.content) : nil
        let emailAddress = outlook.from?.emailAddress != nil ? 
            EmailMessage.EmailAddress(address: outlook.from?.emailAddress?.address, name: outlook.from?.emailAddress?.name) : nil
        let from = emailAddress != nil ? EmailMessage.EmailFrom(emailAddress: emailAddress) : nil
        
        return EmailMessage(
            id: outlook.id,
            receivedDateTime: outlook.receivedDateTime,
            subject: outlook.subject,
            bodyPreview: outlook.bodyPreview,
            body: body,
            from: from
        )
    }
    
    private func convertToEmailAttachment(_ outlook: OutlookAttachment) -> EmailAttachment {
        return EmailAttachment(
            id: outlook.id,
            name: outlook.name,
            contentType: outlook.contentType,
            size: outlook.size,
            isInline: outlook.isInline
        )
    }
}

// Adapter for GmailService to conform to EmailServiceProtocol
class GmailEmailServiceAdapter: EmailServiceProtocol {
    private let gmailService = GmailService.shared
    
    func fetchEmails(from sender: String) async throws -> [EmailMessage] {
        let gmailMessages = try await gmailService.fetchEmails(from: sender)
        return gmailMessages.map { convertToEmailMessage($0) }
    }
    
    func fetchAttachments(for messageId: String) async throws -> [EmailAttachment] {
        let gmailAttachments = try await gmailService.fetchAttachments(for: messageId)
        return gmailAttachments.map { convertToEmailAttachment($0) }
    }
    
    func downloadAttachment(messageId: String, attachmentId: String) async throws -> Data? {
        return try await gmailService.downloadAttachment(messageId: messageId, attachmentId: attachmentId)
    }
    
    private func convertToEmailMessage(_ gmail: GmailMessage) -> EmailMessage {
        let body = gmail.body != nil ? EmailMessage.EmailBody(content: gmail.body?.content) : nil
        let emailAddress = gmail.from?.emailAddress != nil ? 
            EmailMessage.EmailAddress(address: gmail.from?.emailAddress?.address, name: gmail.from?.emailAddress?.name) : nil
        let from = emailAddress != nil ? EmailMessage.EmailFrom(emailAddress: emailAddress) : nil
        
        return EmailMessage(
            id: gmail.id,
            receivedDateTime: gmail.receivedDateTime,
            subject: gmail.subject,
            bodyPreview: gmail.bodyPreview,
            body: body,
            from: from
        )
    }
    
    private func convertToEmailAttachment(_ gmail: GmailAttachment) -> EmailAttachment {
        return EmailAttachment(
            id: gmail.id,
            name: gmail.name,
            contentType: gmail.contentType,
            size: gmail.size,
            isInline: gmail.isInline
        )
    }
}
