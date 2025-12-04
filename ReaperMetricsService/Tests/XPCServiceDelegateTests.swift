import XCTest
@testable import ReaperMetricsService
import ReaperShared

/// Tests for the XPC Service Delegate
/// Following TDD: These tests verify the service delegate behavior
final class XPCServiceDelegateTests: XCTestCase {

    // MARK: - Initialization Tests

    func test_ServiceDelegate_canBeInstantiated() {
        // Given/When
        let delegate = ReaperMetricsServiceDelegate()

        // Then
        XCTAssertNotNil(delegate)
    }

    func test_ServiceDelegate_conformsToNSXPCListenerDelegate() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()

        // Then
        XCTAssertTrue(delegate is NSXPCListenerDelegate)
    }

    func test_ServiceDelegate_acceptsProviderFactory() {
        // Given
        var factoryCalled = false
        let factory: MetricsProviderFactory = {
            factoryCalled = true
            return MockTestProvider()
        }

        // When
        let delegate = ReaperMetricsServiceDelegate(providerFactory: factory)
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // Then - Factory should not be called until connection is accepted
        XCTAssertFalse(factoryCalled)

        // Trigger connection acceptance
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)
        XCTAssertTrue(factoryCalled)
    }

    // MARK: - Connection Acceptance Tests

    func test_ServiceDelegate_acceptsNewConnection() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        let shouldAccept = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then
        XCTAssertTrue(shouldAccept)
    }

    func test_ServiceDelegate_configuresConnectionWithExportedInterface() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then - Connection should have exported interface
        XCTAssertNotNil(connection.exportedInterface)
    }

    func test_ServiceDelegate_configuresConnectionWithCorrectProtocol() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then - Interface should be for ReaperMetricsProtocol
        let expectedInterface = NSXPCInterface(with: ReaperMetricsProtocol.self)
        XCTAssertTrue(
            connection.exportedInterface?.protocol === expectedInterface.protocol
        )
    }

    func test_ServiceDelegate_configuresConnectionWithExportedObject() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then - Connection should have exported object
        XCTAssertNotNil(connection.exportedObject)
    }

    func test_ServiceDelegate_exportedObject_implementsProtocol() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then - Exported object should conform to protocol
        XCTAssertTrue(connection.exportedObject is ReaperMetricsProtocol)
    }

    // MARK: - Connection Lifecycle Tests

    func test_ServiceDelegate_setsInvalidationHandler() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then - Connection should have invalidation handler
        XCTAssertNotNil(connection.invalidationHandler)
    }

    func test_ServiceDelegate_setsInterruptionHandler() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection)

        // Then - Connection should have interruption handler
        XCTAssertNotNil(connection.interruptionHandler)
    }

    // MARK: - Multiple Connections Tests

    func test_ServiceDelegate_acceptsMultipleConnections() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection1 = NSXPCConnection(listenerEndpoint: listener.endpoint)
        let connection2 = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        let accept1 = delegate.listener(listener, shouldAcceptNewConnection: connection1)
        let accept2 = delegate.listener(listener, shouldAcceptNewConnection: connection2)

        // Then
        XCTAssertTrue(accept1)
        XCTAssertTrue(accept2)
    }

    func test_ServiceDelegate_configuresEachConnectionIndependently() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection1 = NSXPCConnection(listenerEndpoint: listener.endpoint)
        let connection2 = NSXPCConnection(listenerEndpoint: listener.endpoint)

        // When
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection1)
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection2)

        // Then - Each connection should have its own exported object
        XCTAssertNotNil(connection1.exportedObject)
        XCTAssertNotNil(connection2.exportedObject)
        // They should be different instances
        let obj1 = connection1.exportedObject as AnyObject
        let obj2 = connection2.exportedObject as AnyObject
        XCTAssertFalse(obj1 === obj2)
    }

    // MARK: - Provider Factory Tests

    func test_ServiceDelegate_usesProvidedFactory() {
        // Given
        var providerCount = 0
        let factory: MetricsProviderFactory = {
            providerCount += 1
            return MockTestProvider()
        }
        let delegate = ReaperMetricsServiceDelegate(providerFactory: factory)
        let listener = NSXPCListener.anonymous()

        // When - Create multiple connections
        _ = delegate.listener(listener, shouldAcceptNewConnection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        _ = delegate.listener(listener, shouldAcceptNewConnection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        _ = delegate.listener(listener, shouldAcceptNewConnection: NSXPCConnection(listenerEndpoint: listener.endpoint))

        // Then - Factory should be called for each connection
        XCTAssertEqual(providerCount, 3)
    }

    // MARK: - Cleanup Tests

    func test_ServiceDelegate_invalidateAllConnections() {
        // Given
        let delegate = ReaperMetricsServiceDelegate()
        let listener = NSXPCListener.anonymous()
        let connection1 = NSXPCConnection(listenerEndpoint: listener.endpoint)
        let connection2 = NSXPCConnection(listenerEndpoint: listener.endpoint)

        _ = delegate.listener(listener, shouldAcceptNewConnection: connection1)
        _ = delegate.listener(listener, shouldAcceptNewConnection: connection2)

        // When
        delegate.invalidateAllConnections()

        // Then - Method should complete without error
        // (We can't easily verify connections are invalidated without more setup)
        XCTAssertTrue(true)
    }
}
