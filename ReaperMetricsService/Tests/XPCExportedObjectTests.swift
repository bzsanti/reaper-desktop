import XCTest
@testable import ReaperMetricsService
import ReaperShared

/// Tests for the XPC Exported Object (ReaperMetricsExporter)
/// Following TDD: These tests verify the exported object behavior
final class XPCExportedObjectTests: XCTestCase {

    // MARK: - Initialization Tests

    func test_Exporter_canBeInstantiatedWithProvider() {
        // Given
        let provider = MockTestProvider()

        // When
        let exporter = ReaperMetricsExporter(provider: provider)

        // Then
        XCTAssertNotNil(exporter)
    }

    func test_Exporter_conformsToReaperMetricsProtocol() {
        // Given
        let provider = MockTestProvider()
        let exporter = ReaperMetricsExporter(provider: provider)

        // Then
        XCTAssertTrue(exporter is ReaperMetricsProtocol)
    }

    // MARK: - Ping Tests

    func test_Exporter_ping_returnsTrue() {
        // Given
        let provider = MockTestProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "Ping reply")

        // When
        exporter.ping { result in
            // Then
            XCTAssertTrue(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - CPU Metrics Tests

    func test_Exporter_getCpuMetrics_returnsMetrics() {
        // Given
        let provider = MockTestProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "CPU metrics reply")

        // When
        exporter.getCpuMetrics { metrics, error in
            // Then
            XCTAssertNotNil(metrics)
            XCTAssertNil(error)
            XCTAssertEqual(Double(metrics!.totalUsage), 25.0, accuracy: 0.001)
            XCTAssertEqual(metrics?.coreCount, 8)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_Exporter_getCpuMetrics_initializesProviderOnFirstCall() {
        // Given
        var initCalled = false
        let provider = TrackingMockProvider(onInit: { initCalled = true })
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "CPU metrics reply")

        XCTAssertFalse(initCalled)

        // When
        exporter.getCpuMetrics { _, _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(initCalled)
    }

    func test_Exporter_getCpuMetrics_refreshesProviderEachCall() {
        // Given
        var refreshCount = 0
        let provider = TrackingMockProvider(onRefresh: { refreshCount += 1 })
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation1 = XCTestExpectation(description: "First call")
        let expectation2 = XCTestExpectation(description: "Second call")

        // When
        exporter.getCpuMetrics { _, _ in expectation1.fulfill() }
        wait(for: [expectation1], timeout: 1.0)

        exporter.getCpuMetrics { _, _ in expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)

        // Then
        XCTAssertEqual(refreshCount, 2)
    }

    // MARK: - Disk Metrics Tests

    func test_Exporter_getDiskMetrics_returnsMetrics() {
        // Given
        let provider = MockTestProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "Disk metrics reply")

        // When
        exporter.getDiskMetrics { metrics, error in
            // Then
            XCTAssertNotNil(metrics)
            XCTAssertNil(error)
            XCTAssertEqual(metrics?.mountPoint, "/")
            XCTAssertEqual(Double(metrics!.usagePercent), 50.0, accuracy: 0.001)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Temperature Tests

    func test_Exporter_getTemperature_returnsTemperature() {
        // Given
        let provider = MockTestProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "Temperature reply")

        // When
        exporter.getTemperature { temp, error in
            // Then
            XCTAssertNotNil(temp)
            XCTAssertNil(error)
            XCTAssertEqual(Double(temp!.cpuTemperature), 45.0, accuracy: 0.001)
            XCTAssertTrue(temp?.isSimulated ?? false)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Error Handling Tests

    func test_Exporter_getCpuMetrics_returnsErrorWhenProviderFails() {
        // Given
        let provider = FailingMockProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "CPU metrics error")

        // When
        exporter.getCpuMetrics { metrics, error in
            // Then
            XCTAssertNil(metrics)
            XCTAssertNotNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_Exporter_getDiskMetrics_returnsErrorWhenProviderFails() {
        // Given
        let provider = FailingMockProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "Disk metrics error")

        // When
        exporter.getDiskMetrics { metrics, error in
            // Then
            XCTAssertNil(metrics)
            XCTAssertNotNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_Exporter_getTemperature_returnsErrorWhenProviderFails() {
        // Given
        let provider = FailingMockProvider()
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation = XCTestExpectation(description: "Temperature error")

        // When
        exporter.getTemperature { temp, error in
            // Then
            XCTAssertNil(temp)
            XCTAssertNotNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Lazy Initialization Tests

    func test_Exporter_initializesProviderOnlyOnce() {
        // Given
        var initCount = 0
        let provider = TrackingMockProvider(onInit: { initCount += 1 })
        let exporter = ReaperMetricsExporter(provider: provider)
        let expectation1 = XCTestExpectation(description: "First call")
        let expectation2 = XCTestExpectation(description: "Second call")
        let expectation3 = XCTestExpectation(description: "Third call")

        // When
        exporter.getCpuMetrics { _, _ in expectation1.fulfill() }
        wait(for: [expectation1], timeout: 1.0)

        exporter.getDiskMetrics { _, _ in expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)

        exporter.getTemperature { _, _ in expectation3.fulfill() }
        wait(for: [expectation3], timeout: 1.0)

        // Then
        XCTAssertEqual(initCount, 1)
    }
}

// MARK: - Test Helpers

/// Mock provider that tracks method calls
final class TrackingMockProvider: MetricsProviderProtocol {
    private var initialized = false
    private let onInit: () -> Void
    private let onRefresh: () -> Void

    init(onInit: @escaping () -> Void = {}, onRefresh: @escaping () -> Void = {}) {
        self.onInit = onInit
        self.onRefresh = onRefresh
    }

    func initialize() {
        initialized = true
        onInit()
    }

    func refresh() {
        onRefresh()
    }

    func getCpuMetrics() -> CpuMetricsData? {
        guard initialized else { return nil }
        return CpuMetricsData(
            totalUsage: 25.0,
            coreCount: 8,
            loadAverage1: 2.0,
            loadAverage5: 1.5,
            loadAverage15: 1.0,
            frequencyMHz: 3000
        )
    }

    func getDiskMetrics() -> DiskMetricsData? {
        guard initialized else { return nil }
        return DiskMetricsData(
            mountPoint: "/",
            name: "Test Disk",
            totalBytes: 500_000_000_000,
            availableBytes: 250_000_000_000,
            usedBytes: 250_000_000_000,
            usagePercent: 50.0
        )
    }

    func getTemperature() -> TemperatureData? {
        guard initialized else { return nil }
        return TemperatureData(cpuTemperature: 45.0, isSimulated: true)
    }

    func cleanup() {
        initialized = false
    }
}

/// Mock provider that always returns nil (simulates failure)
final class FailingMockProvider: MetricsProviderProtocol {
    func initialize() {}
    func refresh() {}
    func getCpuMetrics() -> CpuMetricsData? { return nil }
    func getDiskMetrics() -> DiskMetricsData? { return nil }
    func getTemperature() -> TemperatureData? { return nil }
    func cleanup() {}
}
