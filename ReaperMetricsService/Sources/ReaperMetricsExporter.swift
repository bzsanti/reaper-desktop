import Foundation
import ReaperShared

/// Factory for creating metrics providers
public typealias MetricsProviderFactory = () -> MetricsProviderProtocol

/// The exported object that provides metrics to XPC clients
/// This class implements ReaperMetricsProtocol and uses a MetricsProvider
/// to fetch the actual system metrics
@objc public final class ReaperMetricsExporter: NSObject, ReaperMetricsProtocol {

    // MARK: - Properties

    /// The metrics provider that fetches actual system data
    private let provider: MetricsProviderProtocol

    /// Whether the provider has been initialized
    private var isInitialized = false
    private let initLock = NSLock()

    // MARK: - Initialization

    /// Initialize with a provider (required)
    public init(provider: MetricsProviderProtocol) {
        self.provider = provider
        super.init()
    }

    // MARK: - Private Helpers

    /// Ensure the provider is initialized (lazy initialization)
    private func ensureInitialized() {
        initLock.lock()
        defer { initLock.unlock() }

        guard !isInitialized else { return }
        provider.initialize()
        isInitialized = true
    }

    // MARK: - ReaperMetricsProtocol

    public func getCpuMetrics(reply: @escaping (CpuMetricsData?, Error?) -> Void) {
        ensureInitialized()
        provider.refresh()

        if let metrics = provider.getCpuMetrics() {
            reply(metrics, nil)
        } else {
            let error = NSError(
                domain: "com.reaper.metrics",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get CPU metrics"]
            )
            reply(nil, error)
        }
    }

    public func getDiskMetrics(reply: @escaping (DiskMetricsData?, Error?) -> Void) {
        ensureInitialized()
        provider.refresh()

        if let metrics = provider.getDiskMetrics() {
            reply(metrics, nil)
        } else {
            let error = NSError(
                domain: "com.reaper.metrics",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get disk metrics"]
            )
            reply(nil, error)
        }
    }

    public func getTemperature(reply: @escaping (TemperatureData?, Error?) -> Void) {
        ensureInitialized()
        provider.refresh()

        if let temp = provider.getTemperature() {
            reply(temp, nil)
        } else {
            let error = NSError(
                domain: "com.reaper.metrics",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get temperature"]
            )
            reply(nil, error)
        }
    }

    public func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    // MARK: - Cleanup

    deinit {
        if isInitialized {
            provider.cleanup()
        }
    }
}
