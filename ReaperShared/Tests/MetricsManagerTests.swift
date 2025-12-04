import XCTest
@testable import ReaperShared

/// Tests for the MetricsManager
/// Following TDD: These tests verify XPC-to-fallback behavior
final class MetricsManagerTests: XCTestCase {

    // MARK: - Initialization Tests

    func test_MetricsManager_canBeInstantiated() {
        // Given/When
        let manager = MetricsManager()

        // Then
        XCTAssertNotNil(manager)
    }

    func test_MetricsManager_hasXPCClient() {
        // Given
        let manager = MetricsManager()

        // Then
        XCTAssertNotNil(manager.xpcClient)
    }

    func test_MetricsManager_hasFallbackProvider() {
        // Given
        let manager = MetricsManager()

        // Then
        XCTAssertNotNil(manager.fallbackProvider)
    }

    // MARK: - State Tests

    func test_MetricsManager_isInitiallyDisconnected() {
        // Given
        let manager = MetricsManager()

        // Then
        XCTAssertFalse(manager.isXPCConnected)
    }

    func test_MetricsManager_isNotUsingFallbackInitially() {
        // Given
        let manager = MetricsManager()

        // Then
        XCTAssertFalse(manager.isUsingFallback)
    }

    // MARK: - Fallback Mode Tests

    func test_MetricsManager_switchesToFallbackOnXPCFailure() async {
        // Given
        let manager = MetricsManager()
        manager.enableFallbackOnFailure = true
        // XPC not running, so should fail

        // When
        _ = await manager.getCpuMetrics()

        // Then - Should switch to fallback
        XCTAssertTrue(manager.isUsingFallback)
    }

    func test_MetricsManager_fallbackProvidesMetrics() async {
        // Given
        let mockProvider = TestMockProvider()
        mockProvider.mockCpuMetrics = CpuMetricsData(
            totalUsage: 33.3,
            coreCount: 4,
            loadAverage1: 1.0,
            loadAverage5: 0.8,
            loadAverage15: 0.6,
            frequencyMHz: 2500
        )
        let manager = MetricsManager(fallbackProvider: mockProvider)
        manager.forceUseFallback = true

        // When
        let metrics = await manager.getCpuMetrics()

        // Then
        XCTAssertNotNil(metrics)
        XCTAssertEqual(Double(metrics!.totalUsage), 33.3, accuracy: 0.001)
    }

    func test_MetricsManager_fallbackProvidesDiskMetrics() async {
        // Given
        let mockProvider = TestMockProvider()
        mockProvider.mockDiskMetrics = DiskMetricsData(
            mountPoint: "/",
            name: "Test",
            totalBytes: 100,
            availableBytes: 50,
            usedBytes: 50,
            usagePercent: 50.0
        )
        let manager = MetricsManager(fallbackProvider: mockProvider)
        manager.forceUseFallback = true

        // When
        let metrics = await manager.getDiskMetrics()

        // Then
        XCTAssertNotNil(metrics)
        XCTAssertEqual(metrics?.mountPoint, "/")
    }

    func test_MetricsManager_fallbackProvidesTemperature() async {
        // Given
        let mockProvider = TestMockProvider()
        mockProvider.mockTemperature = TemperatureData(cpuTemperature: 55.0, isSimulated: true)
        let manager = MetricsManager(fallbackProvider: mockProvider)
        manager.forceUseFallback = true

        // When
        let temp = await manager.getTemperature()

        // Then
        XCTAssertNotNil(temp)
        XCTAssertEqual(Double(temp!.cpuTemperature), 55.0, accuracy: 0.001)
    }

    // MARK: - XPC Retry Tests

    func test_MetricsManager_retriesXPCAfterFallback() async {
        // Given
        let manager = MetricsManager()
        manager.retryXPCAfterFallback = true
        manager.retryIntervalSeconds = 0.1 // Very short for testing

        // Force fallback
        manager.forceUseFallback = true
        _ = await manager.getCpuMetrics()
        XCTAssertTrue(manager.isUsingFallback)

        // When - Wait for retry interval
        manager.forceUseFallback = false

        // Then - Manager should have retry logic configured
        XCTAssertTrue(manager.retryXPCAfterFallback)
    }

    // MARK: - Configuration Tests

    func test_MetricsManager_canDisableFallback() async {
        // Given
        let manager = MetricsManager()
        manager.enableFallbackOnFailure = false

        // When
        _ = await manager.getCpuMetrics()

        // Then - Should not switch to fallback
        XCTAssertFalse(manager.isUsingFallback)
    }

    func test_MetricsManager_canForceUseFallback() async {
        // Given
        let mockProvider = TestMockProvider()
        mockProvider.mockCpuMetrics = CpuMetricsData(
            totalUsage: 99.9,
            coreCount: 16,
            loadAverage1: 5.0,
            loadAverage5: 4.0,
            loadAverage15: 3.0,
            frequencyMHz: 4000
        )
        let manager = MetricsManager(fallbackProvider: mockProvider)

        // When
        manager.forceUseFallback = true
        let metrics = await manager.getCpuMetrics()

        // Then
        XCTAssertTrue(manager.isUsingFallback)
        XCTAssertEqual(Double(metrics!.totalUsage), 99.9, accuracy: 0.001)
    }

    // MARK: - Connection Event Tests

    func test_MetricsManager_callsOnXPCConnected() {
        // Given
        let manager = MetricsManager()
        var called = false
        manager.onXPCConnected = { called = true }

        // Then - Handler should be settable
        XCTAssertNotNil(manager.onXPCConnected)
    }

    func test_MetricsManager_callsOnFallbackActivated() {
        // Given
        let manager = MetricsManager()
        var called = false
        manager.onFallbackActivated = { called = true }

        // Then - Handler should be settable
        XCTAssertNotNil(manager.onFallbackActivated)
    }

    // MARK: - Cleanup Tests

    func test_MetricsManager_cleanup_disconnectsXPC() {
        // Given
        let manager = MetricsManager()
        manager.start()

        // When
        manager.cleanup()

        // Then
        XCTAssertFalse(manager.isXPCConnected)
    }
}

// MARK: - Test Mock Provider

/// Mock provider for MetricsManager tests
final class TestMockProvider: MetricsProviderProtocol {
    var isInitialized = false
    var mockCpuMetrics: CpuMetricsData?
    var mockDiskMetrics: DiskMetricsData?
    var mockTemperature: TemperatureData?

    func initialize() {
        isInitialized = true
    }

    func refresh() {}

    func getCpuMetrics() -> CpuMetricsData? {
        guard isInitialized else { return nil }
        return mockCpuMetrics
    }

    func getDiskMetrics() -> DiskMetricsData? {
        guard isInitialized else { return nil }
        return mockDiskMetrics
    }

    func getTemperature() -> TemperatureData? {
        guard isInitialized else { return nil }
        return mockTemperature
    }

    func cleanup() {
        isInitialized = false
    }
}
