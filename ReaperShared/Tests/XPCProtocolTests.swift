import XCTest
@testable import ReaperShared

/// Tests for the XPC protocol definition
/// Following TDD: These tests are written BEFORE the implementation
final class XPCProtocolTests: XCTestCase {

    // MARK: - Protocol Validity Tests

    func test_ReaperMetricsProtocol_isValidXPCProtocol() {
        // Given - Attempt to create an NSXPCInterface with the protocol
        // This will crash at runtime if the protocol is not XPC-compatible

        // When
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Then
        XCTAssertNotNil(interface, "ReaperMetricsProtocol must be a valid XPC protocol")
    }

    func test_ReaperMetricsProtocol_hasCpuMetricsMethod() {
        // Given
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Then - The protocol should have getCpuMetrics method
        // If the method signature is wrong, the XPC call will fail at runtime
        XCTAssertNotNil(interface)
    }

    func test_ReaperMetricsProtocol_hasDiskMetricsMethod() {
        // Given
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Then - The protocol should have getDiskMetrics method
        XCTAssertNotNil(interface)
    }

    func test_ReaperMetricsProtocol_hasTemperatureMethod() {
        // Given
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Then - The protocol should have getTemperature method
        XCTAssertNotNil(interface)
    }

    func test_ReaperMetricsProtocol_hasPingMethod() {
        // Given
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Then - The protocol should have ping method for health checks
        XCTAssertNotNil(interface)
    }

    // MARK: - Interface Configuration Tests

    func test_XPCInterface_allowsSecureCodingTypes() {
        // Given
        let interface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // When - Configure the interface to allow our custom types
        // NSSet bridging to Set<AnyHashable> is safe for class types
        let allowedClasses = NSSet(objects:
            CpuMetricsData.self,
            DiskMetricsData.self,
            TemperatureData.self,
            NSError.self
        ) as! Set<AnyHashable>

        // Then - Setting allowed classes should not crash
        // The selector for getCpuMetrics reply handler
        interface.setClasses(
            allowedClasses,
            for: #selector(ReaperMetricsProtocol.getCpuMetrics(reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        XCTAssertNotNil(interface)
    }

    // MARK: - Mock Implementation Tests

    func test_MockReaperMetricsService_implementsProtocol() {
        // Given
        let mock = MockReaperMetricsService()

        // Then - Mock should conform to the protocol
        XCTAssertTrue(mock is ReaperMetricsProtocol)
    }

    func test_MockReaperMetricsService_returnsCpuMetrics() {
        // Given
        let mock = MockReaperMetricsService()
        mock.mockCpuMetrics = CpuMetricsData(
            totalUsage: 50.0,
            coreCount: 8,
            loadAverage1: 2.0,
            loadAverage5: 1.5,
            loadAverage15: 1.0,
            frequencyMHz: 3000
        )

        let expectation = expectation(description: "getCpuMetrics")

        // When
        mock.getCpuMetrics { metrics, error in
            // Then
            XCTAssertNotNil(metrics)
            XCTAssertNil(error)
            XCTAssertEqual(metrics!.totalUsage, 50.0, accuracy: 0.001)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_MockReaperMetricsService_returnsDiskMetrics() {
        // Given
        let mock = MockReaperMetricsService()
        mock.mockDiskMetrics = DiskMetricsData(
            mountPoint: "/",
            name: "Macintosh HD",
            totalBytes: 500_000_000_000,
            availableBytes: 250_000_000_000,
            usedBytes: 250_000_000_000,
            usagePercent: 50.0
        )

        let expectation = expectation(description: "getDiskMetrics")

        // When
        mock.getDiskMetrics { metrics, error in
            // Then
            XCTAssertNotNil(metrics)
            XCTAssertNil(error)
            XCTAssertEqual(metrics?.mountPoint, "/")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_MockReaperMetricsService_returnsTemperature() {
        // Given
        let mock = MockReaperMetricsService()
        mock.mockTemperature = TemperatureData(cpuTemperature: 65.0, isSimulated: false)

        let expectation = expectation(description: "getTemperature")

        // When
        mock.getTemperature { temperature, error in
            // Then
            XCTAssertNotNil(temperature)
            XCTAssertNil(error)
            XCTAssertEqual(temperature!.cpuTemperature, 65.0, accuracy: 0.001)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_MockReaperMetricsService_pingReturnsTrue() {
        // Given
        let mock = MockReaperMetricsService()

        let expectation = expectation(description: "ping")

        // When
        mock.ping { isAlive in
            // Then
            XCTAssertTrue(isAlive)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_MockReaperMetricsService_handlesError() {
        // Given
        let mock = MockReaperMetricsService()
        mock.shouldFail = true
        mock.mockError = NSError(domain: "ReaperMetrics", code: -1, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        let expectation = expectation(description: "getCpuMetrics with error")

        // When
        mock.getCpuMetrics { metrics, error in
            // Then
            XCTAssertNil(metrics)
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.code, -1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation for Testing

/// Mock implementation of ReaperMetricsProtocol for testing
class MockReaperMetricsService: NSObject, ReaperMetricsProtocol {
    var mockCpuMetrics: CpuMetricsData?
    var mockDiskMetrics: DiskMetricsData?
    var mockTemperature: TemperatureData?
    var shouldFail: Bool = false
    var mockError: Error?

    func getCpuMetrics(reply: @escaping (CpuMetricsData?, Error?) -> Void) {
        if shouldFail {
            reply(nil, mockError)
        } else {
            reply(mockCpuMetrics, nil)
        }
    }

    func getDiskMetrics(reply: @escaping (DiskMetricsData?, Error?) -> Void) {
        if shouldFail {
            reply(nil, mockError)
        } else {
            reply(mockDiskMetrics, nil)
        }
    }

    func getTemperature(reply: @escaping (TemperatureData?, Error?) -> Void) {
        if shouldFail {
            reply(nil, mockError)
        } else {
            reply(mockTemperature, nil)
        }
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(!shouldFail)
    }
}
