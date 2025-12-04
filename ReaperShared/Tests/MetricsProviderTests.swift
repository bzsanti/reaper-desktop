import XCTest
@testable import ReaperShared

/// Tests for the MetricsProvider protocol and implementations
/// Following TDD: These tests are written BEFORE the implementation
final class MetricsProviderTests: XCTestCase {

    // MARK: - Protocol Conformance Tests

    func test_MetricsProviderProtocol_canBeImplementedByMock() {
        // Given
        let mock = MockMetricsProvider()

        // Then - Mock should conform to the protocol
        XCTAssertTrue(mock is MetricsProviderProtocol)
    }

    func test_MetricsProviderProtocol_hasAllRequiredMethods() {
        // Given
        let provider: MetricsProviderProtocol = MockMetricsProvider()

        // Then - All methods should be callable
        provider.initialize()
        provider.refresh()
        _ = provider.getCpuMetrics()
        _ = provider.getDiskMetrics()
        _ = provider.getTemperature()
        provider.cleanup()

        // No crash means success
        XCTAssertTrue(true)
    }

    // MARK: - Mock Provider Tests

    func test_MockProvider_initialize_setsIsInitializedToTrue() {
        // Given
        let mock = MockMetricsProvider()
        XCTAssertFalse(mock.isInitialized)

        // When
        mock.initialize()

        // Then
        XCTAssertTrue(mock.isInitialized)
    }

    func test_MockProvider_getCpuMetrics_returnsMockData() {
        // Given
        let mock = MockMetricsProvider()
        let expectedMetrics = CpuMetricsData(
            totalUsage: 42.5,
            coreCount: 8,
            loadAverage1: 2.0,
            loadAverage5: 1.5,
            loadAverage15: 1.0,
            frequencyMHz: 3000
        )
        mock.mockCpuMetrics = expectedMetrics
        mock.initialize()

        // When
        let result = mock.getCpuMetrics()

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.totalUsage, 42.5, accuracy: 0.001)
        XCTAssertEqual(result!.coreCount, 8)
    }

    func test_MockProvider_getCpuMetrics_returnsNilWhenNotInitialized() {
        // Given
        let mock = MockMetricsProvider()
        mock.mockCpuMetrics = CpuMetricsData(
            totalUsage: 42.5,
            coreCount: 8,
            loadAverage1: 2.0,
            loadAverage5: 1.5,
            loadAverage15: 1.0,
            frequencyMHz: 3000
        )
        // Not calling initialize()

        // When
        let result = mock.getCpuMetrics()

        // Then
        XCTAssertNil(result)
    }

    func test_MockProvider_getDiskMetrics_returnsMockData() {
        // Given
        let mock = MockMetricsProvider()
        let expectedMetrics = DiskMetricsData(
            mountPoint: "/",
            name: "Macintosh HD",
            totalBytes: 500_000_000_000,
            availableBytes: 250_000_000_000,
            usedBytes: 250_000_000_000,
            usagePercent: 50.0
        )
        mock.mockDiskMetrics = expectedMetrics
        mock.initialize()

        // When
        let result = mock.getDiskMetrics()

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.mountPoint, "/")
        XCTAssertEqual(result!.usagePercent, 50.0, accuracy: 0.001)
    }

    func test_MockProvider_getTemperature_returnsMockData() {
        // Given
        let mock = MockMetricsProvider()
        let expectedTemp = TemperatureData(cpuTemperature: 65.0, isSimulated: false)
        mock.mockTemperature = expectedTemp
        mock.initialize()

        // When
        let result = mock.getTemperature()

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.cpuTemperature, 65.0, accuracy: 0.001)
        XCTAssertFalse(result!.isSimulated)
    }

    func test_MockProvider_refresh_incrementsRefreshCount() {
        // Given
        let mock = MockMetricsProvider()
        mock.initialize()
        XCTAssertEqual(mock.refreshCount, 0)

        // When
        mock.refresh()
        mock.refresh()
        mock.refresh()

        // Then
        XCTAssertEqual(mock.refreshCount, 3)
    }

    func test_MockProvider_cleanup_setsIsInitializedToFalse() {
        // Given
        let mock = MockMetricsProvider()
        mock.initialize()
        XCTAssertTrue(mock.isInitialized)

        // When
        mock.cleanup()

        // Then
        XCTAssertFalse(mock.isInitialized)
    }

    func test_MockProvider_cleanup_resetsRefreshCount() {
        // Given
        let mock = MockMetricsProvider()
        mock.initialize()
        mock.refresh()
        mock.refresh()
        XCTAssertEqual(mock.refreshCount, 2)

        // When
        mock.cleanup()

        // Then
        XCTAssertEqual(mock.refreshCount, 0)
    }

    // MARK: - Error Handling Tests

    func test_MockProvider_canSimulateError() {
        // Given
        let mock = MockMetricsProvider()
        mock.shouldFail = true
        mock.initialize()

        // When
        let cpuResult = mock.getCpuMetrics()
        let diskResult = mock.getDiskMetrics()
        let tempResult = mock.getTemperature()

        // Then
        XCTAssertNil(cpuResult)
        XCTAssertNil(diskResult)
        XCTAssertNil(tempResult)
    }
}

// MARK: - Mock Implementation for Testing

/// Mock implementation of MetricsProviderProtocol for testing
class MockMetricsProvider: MetricsProviderProtocol {
    var isInitialized: Bool = false
    var refreshCount: Int = 0
    var shouldFail: Bool = false

    var mockCpuMetrics: CpuMetricsData?
    var mockDiskMetrics: DiskMetricsData?
    var mockTemperature: TemperatureData?

    func initialize() {
        isInitialized = true
    }

    func refresh() {
        guard isInitialized else { return }
        refreshCount += 1
    }

    func getCpuMetrics() -> CpuMetricsData? {
        guard isInitialized && !shouldFail else { return nil }
        return mockCpuMetrics
    }

    func getDiskMetrics() -> DiskMetricsData? {
        guard isInitialized && !shouldFail else { return nil }
        return mockDiskMetrics
    }

    func getTemperature() -> TemperatureData? {
        guard isInitialized && !shouldFail else { return nil }
        return mockTemperature
    }

    func cleanup() {
        isInitialized = false
        refreshCount = 0
    }
}
