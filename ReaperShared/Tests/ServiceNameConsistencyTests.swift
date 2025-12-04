import XCTest
@testable import ReaperShared

/// Tests to ensure service name consistency across the codebase
final class ServiceNameConsistencyTests: XCTestCase {

    /// The expected service name that matches the launchd plist
    private let expectedServiceName = "com.reaper.metrics"

    func test_ReaperMetricsServiceName_matchesExpected() {
        XCTAssertEqual(
            ReaperMetricsServiceName,
            expectedServiceName,
            "ReaperMetricsServiceName constant must match launchd plist Label"
        )
    }

    func test_XPCMetricsClient_serviceName_matchesExpected() {
        let client = XPCMetricsClient()
        XCTAssertEqual(
            client.serviceName,
            expectedServiceName,
            "XPCMetricsClient.serviceName must match launchd plist Label"
        )
    }

    func test_ServiceName_followsReversDNSConvention() {
        XCTAssertTrue(
            ReaperMetricsServiceName.hasPrefix("com.reaper."),
            "Service name should use reverse-DNS notation starting with com.reaper."
        )
    }

    func test_ServiceName_isLowercase() {
        XCTAssertEqual(
            ReaperMetricsServiceName,
            ReaperMetricsServiceName.lowercased(),
            "Service name should be lowercase for consistency"
        )
    }

    func test_XPCMetricsClient_usesReaperMetricsServiceName() {
        // Verify that both constants refer to the same value
        let client = XPCMetricsClient()
        XCTAssertEqual(
            client.serviceName,
            ReaperMetricsServiceName,
            "XPCMetricsClient should use the same service name as ReaperMetricsServiceName constant"
        )
    }
}
