// PerformanceOptimizedView.swift - SwiftUI view modifier for performance optimization
import SwiftUI
import Combine

// MARK: - Performance Optimized View Modifier
struct PerformanceOptimizedView<Content: View>: View {
    let content: Content
    @ObservedObject private var performanceOptimizer = AudioPerformanceOptimizer.shared
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .onReceive(performanceOptimizer.$currentUIFPS) { _ in
                // This will trigger view updates when FPS changes
            }
    }
}

// MARK: - Performance Optimized View Modifier
struct ThrottledUpdateModifier: ViewModifier {
    @ObservedObject private var performanceOptimizer = AudioPerformanceOptimizer.shared
    private let updateAction: () -> Void
    
    init(updateAction: @escaping () -> Void) {
        self.updateAction = updateAction
    }
    
    func body(content: Content) -> some View {
        content
            .onReceive(performanceOptimizer.$currentUIFPS) { _ in
                // Throttle updates based on current FPS setting
                performanceOptimizer.throttleUIUpdate {
                    updateAction()
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    /// Applies performance optimization to the view
    func performanceOptimized() -> some View {
        modifier(ThrottledUpdateModifier(updateAction: {}))
    }
    
    /// Throttles UI updates based on performance settings
    func throttledUpdate(_ action: @escaping () -> Void) -> some View {
        modifier(ThrottledUpdateModifier(updateAction: action))
    }
}

// MARK: - Performance Monitoring View
struct PerformanceMonitorView: View {
    @ObservedObject private var performanceOptimizer = AudioPerformanceOptimizer.shared
    @State private var showDetailedMetrics = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Performance Monitor")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Button(showDetailedMetrics ? "Hide Details" : "Show Details") {
                    showDetailedMetrics.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Basic metrics
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(label: "Buffer Size", value: "\(performanceOptimizer.currentBufferSize) samples")
                MetricRow(label: "UI FPS", value: "\(performanceOptimizer.currentUIFPS)")
                MetricRow(label: "Buffer Latency", value: String(format: "%.1f ms", performanceOptimizer.getBufferLatency() * 1000))
                MetricRow(label: "Optimizations", value: performanceOptimizer.isOptimized ? "Enabled" : "Disabled", isEnabled: performanceOptimizer.isOptimized)
                MetricRow(label: "Hardware Accel", value: performanceOptimizer.isHardwareAccelerated ? "Enabled" : "Disabled", isEnabled: performanceOptimizer.isHardwareAccelerated)
            }
            
            if showDetailedMetrics {
                DetailedMetricsView()
            }
            
            // Performance actions
            HStack(spacing: 12) {
                Button("Optimize for Playback") {
                    performanceOptimizer.optimizeForPlayback()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Optimize for Editing") {
                    performanceOptimizer.optimizeForEditing()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Restore Defaults") {
                    performanceOptimizer.restoreDefaultOptimizations()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Metric Row
struct MetricRow: View {
    let label: String
    let value: String
    var isEnabled: Bool?
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .foregroundColor(isEnabled != nil ? (isEnabled! ? .green : .red) : .secondary)
        }
    }
}

// MARK: - Detailed Metrics View
struct DetailedMetricsView: View {
    @ObservedObject private var performanceOptimizer = AudioPerformanceOptimizer.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detailed Metrics")
                .font(.subheadline)
                .foregroundColor(.blue)
            
            let metrics = performanceOptimizer.getPerformanceMetrics()
            
            ForEach(Array(metrics.keys.sorted()), id: \.self) { key in
                if let value = metrics[key] {
                    HStack {
                        Text(key)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(String(describing: value))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.leading, 16)
    }
}

// MARK: - Preview
struct PerformanceOptimizedView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PerformanceMonitorView()
            
            Text("Performance Optimized Content")
                .performanceOptimized()
        }
        .padding()
    }
}
