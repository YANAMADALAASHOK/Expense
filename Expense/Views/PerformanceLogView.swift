import SwiftUI

struct PerformanceLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = "Loading..."
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
            }
            .navigationTitle("Performance Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        UIPasteboard.general.string = logContent
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: logContent) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            loadLogContent()
        }
    }
    
    private func loadLogContent() {
        let logPath = PerformanceMonitor.shared.getLogFilePath()
        
        do {
            let content = try String(contentsOfFile: logPath, encoding: .utf8)
            logContent = content.isEmpty ? "No performance data logged yet." : content
        } catch {
            logContent = "Error reading log file: \(error.localizedDescription)"
        }
    }
}
