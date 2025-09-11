import SwiftUI

struct MailLoginsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingInfo = false
    @State private var infoMessage = ""
    @State private var gmailClientId: String = GmailOAuthManager.shared.clientId ?? ""
    @State private var gmailRedirectUri: String = GmailOAuthManager.shared.redirectUri ?? ""

    var body: some View {
        Form {
            Section(header: Text("Email Login")) {
                Button("Connect Outlook (Mail.Read)") {
                    MicrosoftOAuthManager.shared.signIn { result in
                        switch result {
                        case .success: show("Outlook connected.")
                        case .failure(let err): show("Outlook sign-in failed: \(err.localizedDescription)")
                        }
                    }
                }
                Button("Sign in to Gmail") {
                    GmailOAuthManager.shared.signIn { success, message in
                        show(success ? "Gmail connected." : (message ?? "Gmail sign-in failed"))
                    }
                }
                if GmailService.shared.isSignedIn {
                    Button("Sign Out of Gmail") { GmailService.shared.signOut(); show("Signed out of Gmail") }
                }
            }

            Section(header: Text("Inboxes")) {
                HStack {
                    Image(systemName: "envelope.badge")
                    NavigationLink(destination: EmailInboxView(viewModel: viewModel, initialSender: "alerts@axisbank.com")) {
                        Text("Axis Alerts (Outlook)")
                    }
                }
                HStack {
                    Image(systemName: "tray.full")
                    NavigationLink(destination: GmailInboxView(viewModel: viewModel)) {
                        Text("ICICI Gmail")
                    }
                }
            }
        }
        .navigationTitle("Email Login")
        .alert("Info", isPresented: $showingInfo) {
            Button("OK", role: .cancel) { }
        } message: { Text(infoMessage) }
    }

    private func show(_ message: String) {
        infoMessage = message
        showingInfo = true
    }
}

struct GmailInboxView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var items: [ParsedItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var infoMessage: String? = nil

    struct ParsedItem: Identifiable {
        let id = UUID()
        let subject: String
        let body: String
        let date: Date
        let amount: Double
        let isCredit: Bool
        let description: String
        let suggestedCategory: String
        var preview: String { EmailParser.htmlToPlainTextLightweight(body) }
    }

    var body: some View {
        List {
            if loading { ProgressView() }
            if let error = error { Text(error).foregroundColor(.red) }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.isCredit ? "+ ₹\(formatAmount(item.amount))" : "- ₹\(formatAmount(item.amount))")
                            .font(.headline)
                            .foregroundColor(item.isCredit ? .green : .red)
                        Spacer()
                        Text(item.date.formatted())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.subheadline)
                    }
                    Text(item.subject)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Text(item.preview)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                    HStack {
                        Button("Parse & Queue") {
                            let pending = PendingTransactionItem(
                                subject: item.subject,
                                body: item.body,
                                amount: item.amount,
                                date: item.date,
                                isCredit: item.isCredit,
                                suggestedCategory: item.suggestedCategory,
                                notes: item.description
                            )
                            viewModel.addPendingTransaction(pending)
                            infoMessage = "Queued: ₹\(formatAmount(item.amount))"
                        }
                        Spacer()
                        Text(item.suggestedCategory)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Gmail: ICICI")
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh", action: load)
            }
        }
        .alert("Info", isPresented: Binding(get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } })) {
            Button("OK", role: .cancel) { infoMessage = nil }
        } message: { Text(infoMessage ?? "") }
    }

    private func load() {
        guard GmailService.shared.isSignedIn else { error = "Not signed in"; return }
        loading = true
        error = nil
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        GmailService.shared.fetchMessages(query: "from:credit_cards@icicibank.com", since: since, max: 50) { result in
            DispatchQueue.main.async {
                loading = false
                switch result {
                case .failure(let err): error = err.localizedDescription
                case .success(let msgs):
                    print("[GmailInbox] Received \(msgs.count) messages")
                    var mapped: [ParsedItem] = msgs.compactMap { msg in
                        print("[GmailInbox] Raw subj: \(msg.subject)")
                        let preview = EmailParser.htmlToPlainTextLightweight(msg.body)
                        print("[GmailInbox] Raw body first 200: \(String(preview.prefix(200)))")
                        if let parsed = try? EmailParser.parse(subject: msg.subject, body: msg.body) {
                            print("[GmailInbox] Parsed amount=\(parsed.amount) isCredit=\(parsed.isCredit) desc=\(parsed.description)")
                            return ParsedItem(
                                subject: parsed.subject,
                                body: parsed.body,
                                date: msg.received,
                                amount: parsed.amount,
                                isCredit: parsed.isCredit,
                                description: parsed.description,
                                suggestedCategory: parsed.suggestedCategory
                            )
                        } else {
                            print("[GmailInbox] Parse failed; defaulting")
                            return ParsedItem(
                                subject: msg.subject,
                                body: msg.body,
                                date: msg.received,
                                amount: 0,
                                isCredit: false,
                                description: "",
                                suggestedCategory: TransactionCategory.other.rawValue
                            )
                        }
                    }
                    mapped.sort { $0.date > $1.date }
                    items = mapped
                }
            }
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}


