import SwiftUI

struct EmailInboxView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    let initialSender: String?
    @State private var senderFilter: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""

    init(viewModel: ExpenseViewModel, initialSender: String? = nil) {
        self.viewModel = viewModel
        self.initialSender = initialSender
        _senderFilter = State(initialValue: initialSender ?? "")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Filter by sender (optional)", text: $senderFilter)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Menu("Fetch") {
                    Button("Recent") {
                        viewModel.fetchAllOutlookEmails(sender: senderFilter.isEmpty ? nil : senderFilter) { result in
                            if case .failure(let err) = result { alert(err.localizedDescription) }
                        }
                    }
                    Button("Last 30 days") {
                        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                        viewModel.fetchOutlookEmails(since: since, sender: senderFilter.isEmpty ? nil : senderFilter) { result in
                            if case .failure(let err) = result { alert(err.localizedDescription) }
                        }
                    }
                }
            }
            .padding(.horizontal)

            List(viewModel.fetchedEmails, id: \.id) { msg in
                EmailRow(message: msg, onParse: {
                    do {
                        let parsed = try EmailParser.parse(subject: msg.subject, body: msg.body?.content ?? msg.bodyPreview)
                        let pending = PendingTransactionItem(
                            subject: parsed.subject,
                            body: parsed.body,
                            amount: parsed.amount,
                            date: parsed.date,
                            isCredit: parsed.isCredit,
                            suggestedCategory: parsed.suggestedCategory,
                            notes: parsed.description
                        )
                        viewModel.addPendingTransaction(pending)
                        alert("Queued pending: \(parsed.suggestedCategory) \(parsed.amount)")
                    } catch {
                        alert("Parse failed: \(error.localizedDescription)")
                    }
                })
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Email Inbox")
        .onAppear {
            if viewModel.fetchedEmails.isEmpty {
                viewModel.fetchAllOutlookEmails(sender: initialSender) { result in
                    if case .failure(let err) = result { alert(err.localizedDescription) }
                }
            }
        }
        .alert("Info", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: { Text(alertMessage) }
    }

    private func alert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    private func previewText(for msg: OutlookMessage) -> String {
        let raw = (msg.body?.content ?? msg.bodyPreview) ?? ""
        let plain = EmailParser.htmlToPlainText(raw)
        return String(plain.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct EmailRow: View {
    let message: OutlookMessage
    let onParse: () -> Void
    @State private var preview: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.subject ?? "(No subject)")
                .font(.headline)
            Text(preview)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("Parse & Queue", action: onParse)
                Spacer()
                Text(message.receivedDateTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .task {
            let raw = (message.body?.content ?? message.bodyPreview) ?? ""
            await MainActor.run {
                preview = "Processing…"
            }
            let plain = EmailParser.htmlToPlainTextLightweight(raw)
            let clipped = String(plain.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                preview = clipped
            }
        }
    }
}


