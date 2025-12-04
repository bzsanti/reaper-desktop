import Foundation
import ReaperShared

/// ReaperMetricsService - Launch Agent for system metrics
///
/// This Launch Agent provides a single source of truth for system metrics,
/// ensuring both ReaperApp and ReaperMenuBar show consistent values.
///
/// Architecture:
/// - Runs as a launchd agent (~/Library/LaunchAgents/com.reaper.metrics.plist)
/// - Both apps connect via Mach service name "com.reaper.metrics"
/// - Single instance serves all clients
///
/// The service uses lazy initialization of the Rust metrics provider,
/// which requires a warm-up period for accurate CPU delta calculations.

/// Mach service name - must match launchd plist and client
let machServiceName = "com.reaper.metrics"

// Create the provider factory
// Uses RustMetricsProvider for real system metrics via FFI
let providerFactory: MetricsProviderFactory = { () -> any MetricsProviderProtocol in
    return RustMetricsProvider()
}

// Create the service delegate with the provider factory
let delegate = ReaperMetricsServiceDelegate(providerFactory: providerFactory)

// Create Mach service listener
// This allows any app to connect using the service name
let listener = NSXPCListener(machServiceName: machServiceName)

// Set the delegate
listener.delegate = delegate

// Resume the listener to start accepting connections
listener.resume()

print("ReaperMetricsService started (Mach service: \(machServiceName))")

// Keep the service running
RunLoop.current.run()
