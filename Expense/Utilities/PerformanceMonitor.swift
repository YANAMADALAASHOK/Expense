import Foundation

/// Performance monitoring utility to track CPU-intensive operations
class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private var measurements: [String: [TimeInterval]] = [:]
    private let queue = DispatchQueue(label: "com.expense.performance", qos: .utility)
    private let logFileURL: URL
    
    private init() {
        // Create log file in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logFileURL = documentsPath.appendingPathComponent("performance_log.txt")
        
        // Clear old log on init
        try? "=== Performance Monitor Started ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
        print("📊 Performance Monitor initialized. Log file: \(logFileURL.path)")
    }
    
    /// Measure execution time of a block of code
    func measure(_ label: String, block: () -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        block()
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        
        record(label: label, time: executionTime)
    }
    
    /// Measure async execution time
    func measureAsync(_ label: String, block: () async -> Void) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        await block()
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        
        record(label: label, time: executionTime)
    }
    
    /// Record execution time
    private func record(label: String, time: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Store measurement
            if self.measurements[label] == nil {
                self.measurements[label] = []
            }
            self.measurements[label]?.append(time)
            
            // Log to file
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            let logEntry = "[\(timestamp)] \(label): \(String(format: "%.4f", time * 1000))ms\n"
            
            if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                handle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
            
            // Warn if operation is slow
            if time > 0.1 { // More than 100ms
                print("⚠️ SLOW OPERATION: \(label) took \(String(format: "%.2f", time * 1000))ms")
            }
        }
    }
    
    /// Get statistics for a specific operation
    func getStats(for label: String) -> (count: Int, avg: Double, max: Double, min: Double)? {
        guard let times = measurements[label], !times.isEmpty else { return nil }
        
        let count = times.count
        let avg = times.reduce(0, +) / Double(count)
        let max = times.max() ?? 0
        let min = times.min() ?? 0
        
        return (count, avg * 1000, max * 1000, min * 1000) // Convert to ms
    }
    
    /// Print performance summary
    func printSummary() {
        queue.sync {
            print("\n" + String(repeating: "=", count: 60))
            print("📊 PERFORMANCE SUMMARY")
            print(String(repeating: "=", count: 60))
            
            let sortedKeys = measurements.keys.sorted { key1, key2 in
                let avg1 = (measurements[key1]?.reduce(0, +) ?? 0) / Double(measurements[key1]?.count ?? 1)
                let avg2 = (measurements[key2]?.reduce(0, +) ?? 0) / Double(measurements[key2]?.count ?? 1)
                return avg1 > avg2
            }
            
            for label in sortedKeys {
                if let stats = getStats(for: label) {
                    let indicator = stats.avg > 100 ? "🔴" : (stats.avg > 50 ? "🟡" : "🟢")
                    print("\(indicator) \(label)")
                    print("   Count: \(stats.count) | Avg: \(String(format: "%.2f", stats.avg))ms | Max: \(String(format: "%.2f", stats.max))ms | Min: \(String(format: "%.2f", stats.min))ms")
                }
            }
            
            print(String(repeating: "=", count: 60) + "\n")
        }
    }
    
    /// Clear all measurements
    func reset() {
        queue.async { [weak self] in
            self?.measurements.removeAll()
            try? "=== Performance Monitor Reset ===\n".write(to: self?.logFileURL ?? URL(fileURLWithPath: ""), atomically: true, encoding: .utf8)
        }
    }
    
    /// Get log file path for sharing
    func getLogFilePath() -> String {
        return logFileURL.path
    }
}

// MARK: - Convenience Extensions
extension PerformanceMonitor {
    /// Measure view rendering time
    func measureViewRender(_ viewName: String, block: () -> Void) {
        measure("View Render: \(viewName)", block: block)
    }
    
    /// Measure Core Data operations
    func measureCoreData(_ operation: String, block: () -> Void) {
        measure("CoreData: \(operation)", block: block)
    }
    
    /// Measure network operations
    func measureNetwork(_ operation: String, block: () async -> Void) async {
        await measureAsync("Network: \(operation)", block: block)
    }
}
