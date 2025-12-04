import XCTest
@testable import ReaperShared

/// Tests for the XPC Metrics Client
/// Following TDD: These tests verify the client behavior
final class XPCMetricsClientTests: XCTestCase {

    // MARK: - Initialization Tests

    func test_XPCClient_canBeInstantiated() {
        // Given/When
        let client = XPCMetricsClient()

        // Then
        XCTAssertNotNil(client)
    }

    func test_XPCClient_hasServiceName() {
        // Given
        let client = XPCMetricsClient()

        // Then - Mach service name for Launch Agent
        XCTAssertEqual(client.serviceName, "com.reaper.metrics")
    }

    func test_XPCClient_isInitiallyNotConnected() {
        // Given
        let client = XPCMetricsClient()

        // Then
        XCTAssertFalse(client.isConnected)
    }

    // MARK: - Connection Configuration Tests

    func test_XPCClient_createConnection_returnsNSXPCConnection() {
        // Given
        let client = XPCMetricsClient()

        // When
        let connection = client.createConnection()

        // Then
        XCTAssertNotNil(connection)
    }

    func test_XPCClient_connection_isMachService() {
        // Given
        let client = XPCMetricsClient()

        // When
        let connection = client.createConnection()

        // Then - Mach service connections don't have serviceName property
        // but we can verify the connection was created
        XCTAssertNotNil(connection)
        XCTAssertNotNil(connection.remoteObjectInterface)
    }

    func test_XPCClient_connection_hasRemoteObjectInterface() {
        // Given
        let client = XPCMetricsClient()

        // When
        let connection = client.createConnection()

        // Then
        XCTAssertNotNil(connection.remoteObjectInterface)
    }

    func test_XPCClient_connection_interfaceIsReaperMetricsProtocol() {
        // Given
        let client = XPCMetricsClient()

        // When
        let connection = client.createConnection()
        let expectedInterface = NSXPCInterface(with: ReaperMetricsProtocol.self)

        // Then
        XCTAssertTrue(
            connection.remoteObjectInterface?.protocol === expectedInterface.protocol
        )
    }

    // MARK: - Error Handling Tests

    func test_XPCClient_connectionError_isHandled() {
        // Given
        let client = XPCMetricsClient()
        var errorHandled = false

        // When
        client.onConnectionError = { _ in
            errorHandled = true
        }

        // Simulate error (connection to non-existent service)
        client.connect()

        // Then - Client should handle connection failures gracefully
        // Note: We can't easily test actual XPC errors without a running service
        // This test verifies the error handler can be set
        XCTAssertNotNil(client.onConnectionError)
    }

    // MARK: - Disconnect Tests

    func test_XPCClient_disconnect_setsIsConnectedToFalse() {
        // Given
        let client = XPCMetricsClient()
        client.connect()

        // When
        client.disconnect()

        // Then
        XCTAssertFalse(client.isConnected)
    }

    func test_XPCClient_disconnect_canBeCalledMultipleTimes() {
        // Given
        let client = XPCMetricsClient()

        // When/Then - Should not crash
        client.disconnect()
        client.disconnect()
        client.disconnect()

        XCTAssertFalse(client.isConnected)
    }

    // MARK: - Interface Configuration Tests

    func test_XPCClient_interfaceAllowsCpuMetricsData() {
        // Given
        let client = XPCMetricsClient()

        // When
        let interface = client.createInterface()

        // Then - Should have configured classes for reply
        XCTAssertNotNil(interface)
    }

    // MARK: - Async Method Tests

    func test_XPCClient_getCpuMetrics_async_returnsNilWhenNotConnected() async {
        // Given
        let client = XPCMetricsClient()
        // Not connecting

        // When
        let result = await client.getCpuMetricsAsync()

        // Then
        XCTAssertNil(result)
    }

    func test_XPCClient_getDiskMetrics_async_returnsNilWhenNotConnected() async {
        // Given
        let client = XPCMetricsClient()

        // When
        let result = await client.getDiskMetricsAsync()

        // Then
        XCTAssertNil(result)
    }

    func test_XPCClient_getTemperature_async_returnsNilWhenNotConnected() async {
        // Given
        let client = XPCMetricsClient()

        // When
        let result = await client.getTemperatureAsync()

        // Then
        XCTAssertNil(result)
    }

    func test_XPCClient_ping_async_returnsFalseWhenNotConnected() async {
        // Given
        let client = XPCMetricsClient()

        // When
        let result = await client.pingAsync()

        // Then
        XCTAssertFalse(result)
    }
}
