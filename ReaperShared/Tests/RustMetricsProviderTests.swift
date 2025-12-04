import XCTest
@testable import ReaperShared

/// Tests for RustMetricsProvider - the FFI wrapper for Rust metrics
/// These tests verify the integration with the Rust backend
///
/// IMPORTANT: These tests require the Rust dylib to be linked.
/// They are designed to be run in the full app build context where the
/// Rust libraries are available. When running as a standalone Swift package,
/// these tests will be skipped.
///
/// To run these tests with FFI:
/// 1. Build the Rust libraries: `cargo build --release`
/// 2. Run tests from ReaperApp or ReaperMetricsService context
final class RustMetricsProviderTests: XCTestCase {

    // Note: These tests are placeholder tests that verify the API contract
    // without actually calling FFI. The real FFI integration tests should be
    // run from the app context where the Rust library is linked.

    // MARK: - API Contract Tests (No FFI Required)

    func test_RustMetricsProvider_canBeInstantiated() {
        // This test verifies the class exists and can be created
        // It does NOT test FFI functionality
        let provider = RustMetricsProvider()
        XCTAssertNotNil(provider)
    }

    func test_RustMetricsProvider_conformsToMetricsProviderProtocol() {
        let provider = RustMetricsProvider()
        XCTAssertTrue(provider is MetricsProviderProtocol)
    }

    func test_RustMetricsProvider_isReadyInitiallyFalse() {
        let provider = RustMetricsProvider()
        XCTAssertFalse(provider.isReady)
    }

    func test_RustMetricsProvider_getCpuMetrics_returnsNilBeforeInit() {
        let provider = RustMetricsProvider()
        // Should return nil because not initialized
        // This doesn't call FFI, just checks the guard
        XCTAssertNil(provider.getCpuMetrics())
    }

    func test_RustMetricsProvider_getDiskMetrics_returnsNilBeforeInit() {
        let provider = RustMetricsProvider()
        XCTAssertNil(provider.getDiskMetrics())
    }

    func test_RustMetricsProvider_getTemperature_returnsNilBeforeInit() {
        let provider = RustMetricsProvider()
        XCTAssertNil(provider.getTemperature())
    }

    // MARK: - Documentation for FFI Integration Tests
    //
    // The following tests should be run when FFI is available:
    //
    // - test_RustMetricsProvider_initializesSuccessfully
    // - test_RustMetricsProvider_getCpuMetrics_returnsValidData
    // - test_RustMetricsProvider_getDiskMetrics_returnsValidData
    // - test_RustMetricsProvider_getTemperature_returnsValidData
    // - test_RustMetricsProvider_refresh_updatesMetrics
    // - test_RustMetricsProvider_cleanup_stopsReturningData
    // - test_RustMetricsProvider_isThreadSafe
    //
    // These tests are implemented in ReaperMetricsServiceTests when the full
    // app context is available with linked Rust libraries.
}

// MARK: - FFI Integration Test Template

/// Template for FFI integration tests to be used when Rust library is linked
/// Copy these tests to the integration test target
enum RustMetricsProviderFFITestTemplate {
    /*
    func test_RustMetricsProvider_initializesSuccessfully() {
        let provider = RustMetricsProvider()
        provider.initialize()
        XCTAssertTrue(provider.isReady)
    }

    func test_RustMetricsProvider_getCpuMetrics_returnsValidData() {
        let provider = RustMetricsProvider()
        provider.initialize()
        Thread.sleep(forTimeInterval: 0.6)
        provider.refresh()

        let metrics = provider.getCpuMetrics()
        XCTAssertNotNil(metrics)

        if let metrics = metrics {
            XCTAssertGreaterThanOrEqual(metrics.totalUsage, 0.0)
            XCTAssertLessThanOrEqual(metrics.totalUsage, 100.0)
            XCTAssertEqual(metrics.coreCount, ProcessInfo.processInfo.processorCount)
        }
    }

    func test_RustMetricsProvider_getDiskMetrics_returnsValidData() {
        let provider = RustMetricsProvider()
        provider.initialize()
        provider.refresh()

        let metrics = provider.getDiskMetrics()
        XCTAssertNotNil(metrics)

        if let metrics = metrics {
            XCTAssertEqual(metrics.mountPoint, "/")
            XCTAssertGreaterThan(metrics.totalBytes, 0)
        }
    }

    func test_RustMetricsProvider_getTemperature_returnsValidData() {
        let provider = RustMetricsProvider()
        provider.initialize()
        provider.refresh()

        let temperature = provider.getTemperature()
        XCTAssertNotNil(temperature)

        if let temp = temperature {
            XCTAssertGreaterThanOrEqual(temp.cpuTemperature, 20.0)
            XCTAssertLessThanOrEqual(temp.cpuTemperature, 110.0)
        }
    }

    func test_RustMetricsProvider_cleanup_stopsReturningData() {
        let provider = RustMetricsProvider()
        provider.initialize()
        provider.refresh()
        XCTAssertNotNil(provider.getCpuMetrics())

        provider.cleanup()

        XCTAssertFalse(provider.isReady)
        XCTAssertNil(provider.getCpuMetrics())
    }
    */
}
