//
//  SyncStatusView.swift
//  Expense
//
//  Firebase Sync Status Monitor
//

import SwiftUI

struct SyncStatusView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Compact Status Bar
            Button(action: { showingDetails.toggle() }) {
                HStack(spacing: 12) {
                    // Sync Icon
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: viewModel.isSyncing ? "arrow.triangle.2.circlepath" : "cloud")
                            .font(.system(size: 18))
                            .foregroundColor(statusColor)
                            .rotationEffect(.degrees(viewModel.isSyncing ? 360 : 0))
                            .animation(viewModel.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isSyncing)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Cloud Sync")
                                .font(.headline)
                            
                            if viewModel.isFullySynced {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text(viewModel.lastSyncStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Pending Badge
                    if viewModel.pendingSyncCount > 0 {
                        VStack(spacing: 2) {
                            Text("\(viewModel.pendingSyncCount)")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            Text("pending")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showingDetails) {
            SyncDetailsView(viewModel: viewModel)
        }
    }
    
    private var statusColor: Color {
        if viewModel.isSyncing {
            return .blue
        } else if viewModel.pendingSyncCount > 0 {
            return .orange
        } else {
            return .green
        }
    }
}

struct SyncDetailsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Status Section
                Section {
                    StatusRow(icon: "circle.fill", iconColor: viewModel.isSyncing ? .blue : (viewModel.isFullySynced ? .green : .orange),
                             title: "Status", value: viewModel.isSyncing ? "Syncing..." : (viewModel.isFullySynced ? "✅ Fully Synced" : "⚠️ Pending Changes"))
                    
                    StatusRow(icon: "percent", iconColor: .blue,
                             title: "Completion", value: "\(Int(viewModel.syncCompletionPercentage))%")
                    
                    StatusRow(icon: "clock.fill", iconColor: .blue,
                             title: "Last Sync", value: viewModel.lastSyncStatus)
                } header: {
                    Text("Sync Status")
                }
                
                // Pending Data Section
                Section {
                    StatusRow(icon: "tray.fill", iconColor: .orange,
                             title: "Pending Changes", value: "\(viewModel.pendingSyncCount) items")
                    
                    StatusRow(icon: "doc.fill", iconColor: .orange,
                             title: "Pending Size", value: formatBytes(viewModel.pendingSyncSize))
                } header: {
                    Text("Pending Data")
                }
                
                // Synced Data Section
                Section {
                    StatusRow(icon: "checkmark.circle.fill", iconColor: .green,
                             title: "Total Synced", value: formatBytes(viewModel.totalSyncedSize))
                    
                    StatusRow(icon: "icloud.fill", iconColor: .blue,
                             title: "Sync Strategy", value: "Smart Batching")
                    
                    StatusRow(icon: "timer.circle.fill", iconColor: .purple,
                             title: "Batch Size", value: "20 changes or 60s")
                } header: {
                    Text("Statistics")
                }
                
                // Actions Section
                Section {
                    Button(action: {
                        viewModel.verifySyncStatus()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                            Text("Verify Sync Status")
                        }
                    }
                    
                    Button(action: {
                        viewModel.manualSync()
                    }) {
                        HStack {
                            Image(systemName: viewModel.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .rotationEffect(.degrees(viewModel.isSyncing ? 360 : 0))
                                .animation(viewModel.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isSyncing)
                            Text(viewModel.isSyncing ? "Syncing..." : "Sync Now")
                            Spacer()
                            if viewModel.pendingSyncCount > 0 {
                                Text("\(viewModel.pendingSyncCount)")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .disabled(viewModel.isSyncing)
                } header: {
                    Text("Actions")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔄 Smart Batching: Changes are automatically synced after 20 saves or 60 seconds")
                        Text("⚡ Immediate Sync: Critical data syncs instantly")
                        Text("📦 Background Mode: Bulk operations sync when complete")
                        Text("💾 Local First: All data saved locally first, then synced in background")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Sync Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct StatusRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    SyncStatusView(viewModel: ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
}
