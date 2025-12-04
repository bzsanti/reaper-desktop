import Foundation

/// XPC Protocol for ReaperMetricsService
/// This protocol defines the interface between client apps (ReaperApp, ReaperMenuBar)
/// and the XPC service that provides metrics.
///
/// All methods use completion handlers (reply blocks) as required by XPC.
/// Error handling is done via optional Error parameters in reply blocks.
@objc public protocol ReaperMetricsProtocol {

    /// Get current CPU metrics
    /// - Parameter reply: Completion handler with CPU metrics or error
    func getCpuMetrics(reply: @escaping (CpuMetricsData?, Error?) -> Void)

    /// Get current disk metrics for the primary disk
    /// - Parameter reply: Completion handler with disk metrics or error
    func getDiskMetrics(reply: @escaping (DiskMetricsData?, Error?) -> Void)

    /// Get current CPU temperature
    /// - Parameter reply: Completion handler with temperature data or error
    func getTemperature(reply: @escaping (TemperatureData?, Error?) -> Void)

    /// Health check to verify the service is alive
    /// - Parameter reply: Completion handler with true if service is healthy
    func ping(reply: @escaping (Bool) -> Void)
}

// MARK: - XPC Interface Configuration

/// Helper to configure NSXPCInterface with our custom types
public extension NSXPCInterface {

    /// Configure the interface to allow our custom NSSecureCoding types
    /// Must be called on both client and service side
    static func configuredInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Define allowed classes for each method's reply handler
        // Using NSSet for class type literals, then bridging to Set<AnyHashable>
        // This bridging cast is safe - NSSet with class types always bridges successfully
        let cpuClasses = NSSet(objects: CpuMetricsData.self, NSError.self) as! Set<AnyHashable>
        let diskClasses = NSSet(objects: DiskMetricsData.self, NSError.self) as! Set<AnyHashable>
        let temperatureClasses = NSSet(objects: TemperatureData.self, NSError.self) as! Set<AnyHashable>

        // Configure getCpuMetrics reply handler
        interface.setClasses(
            cpuClasses,
            for: #selector(ReaperMetricsProtocol.getCpuMetrics(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // Configure getDiskMetrics reply handler
        interface.setClasses(
            diskClasses,
            for: #selector(ReaperMetricsProtocol.getDiskMetrics(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // Configure getTemperature reply handler
        interface.setClasses(
            temperatureClasses,
            for: #selector(ReaperMetricsProtocol.getTemperature(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        return interface
    }
}

// MARK: - Error Types

/// Errors that can occur in the ReaperMetrics XPC service
public enum ReaperMetricsError: Int, Error, LocalizedError {
    case serviceUnavailable = 1
    case connectionInterrupted = 2
    case connectionInvalidated = 3
    case metricsUnavailable = 4
    case timeout = 5

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "ReaperMetricsService is not available"
        case .connectionInterrupted:
            return "Connection to ReaperMetricsService was interrupted"
        case .connectionInvalidated:
            return "Connection to ReaperMetricsService was invalidated"
        case .metricsUnavailable:
            return "Metrics data is not available"
        case .timeout:
            return "Request to ReaperMetricsService timed out"
        }
    }
}

// MARK: - Service Identifier

/// Mach service name for the Launch Agent
/// Must match the Label in com.reaper.metrics.plist
public let ReaperMetricsServiceName = "com.reaper.metrics"
