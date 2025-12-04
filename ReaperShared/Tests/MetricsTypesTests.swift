import XCTest
@testable import ReaperShared

/// Tests for metrics data types that will be serialized over XPC
/// Following TDD: These tests are written BEFORE the implementation
final class MetricsTypesTests: XCTestCase {

    // MARK: - CpuMetricsData Tests

    func test_CpuMetricsData_conformsToNSSecureCoding() {
        // Given
        let metricsType = CpuMetricsData.self

        // Then
        XCTAssertTrue(metricsType.supportsSecureCoding,
                      "CpuMetricsData must support NSSecureCoding for XPC")
    }

    func test_CpuMetricsData_encodesAndDecodesCorrectly() throws {
        // Given
        let original = CpuMetricsData(
            totalUsage: 45.5,
            coreCount: 8,
            loadAverage1: 2.5,
            loadAverage5: 2.0,
            loadAverage15: 1.8,
            frequencyMHz: 3200
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: CpuMetricsData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.totalUsage, original.totalUsage, accuracy: 0.001)
        XCTAssertEqual(decoded.coreCount, original.coreCount)
        XCTAssertEqual(decoded.loadAverage1, original.loadAverage1, accuracy: 0.001)
        XCTAssertEqual(decoded.loadAverage5, original.loadAverage5, accuracy: 0.001)
        XCTAssertEqual(decoded.loadAverage15, original.loadAverage15, accuracy: 0.001)
        XCTAssertEqual(decoded.frequencyMHz, original.frequencyMHz)
    }

    func test_CpuMetricsData_handlesZeroValues() throws {
        // Given - edge case with all zeros
        let original = CpuMetricsData(
            totalUsage: 0.0,
            coreCount: 0,
            loadAverage1: 0.0,
            loadAverage5: 0.0,
            loadAverage15: 0.0,
            frequencyMHz: 0
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: CpuMetricsData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.totalUsage, 0.0, accuracy: 0.001)
    }

    func test_CpuMetricsData_handlesMaxValues() throws {
        // Given - edge case with maximum realistic values
        let original = CpuMetricsData(
            totalUsage: 100.0,
            coreCount: 128,
            loadAverage1: 128.0,
            loadAverage5: 128.0,
            loadAverage15: 128.0,
            frequencyMHz: 6000
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: CpuMetricsData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.totalUsage, 100.0, accuracy: 0.001)
        XCTAssertEqual(decoded.coreCount, 128)
    }

    // MARK: - DiskMetricsData Tests

    func test_DiskMetricsData_conformsToNSSecureCoding() {
        // Given
        let metricsType = DiskMetricsData.self

        // Then
        XCTAssertTrue(metricsType.supportsSecureCoding,
                      "DiskMetricsData must support NSSecureCoding for XPC")
    }

    func test_DiskMetricsData_encodesAndDecodesCorrectly() throws {
        // Given
        let original = DiskMetricsData(
            mountPoint: "/",
            name: "Macintosh HD",
            totalBytes: 500_000_000_000,
            availableBytes: 250_000_000_000,
            usedBytes: 250_000_000_000,
            usagePercent: 50.0
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: DiskMetricsData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.mountPoint, original.mountPoint)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.totalBytes, original.totalBytes)
        XCTAssertEqual(decoded.availableBytes, original.availableBytes)
        XCTAssertEqual(decoded.usedBytes, original.usedBytes)
        XCTAssertEqual(decoded.usagePercent, original.usagePercent, accuracy: 0.001)
    }

    func test_DiskMetricsData_handlesEmptyStrings() throws {
        // Given - edge case with empty strings
        let original = DiskMetricsData(
            mountPoint: "",
            name: "",
            totalBytes: 0,
            availableBytes: 0,
            usedBytes: 0,
            usagePercent: 0.0
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: DiskMetricsData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.mountPoint, "")
        XCTAssertEqual(decoded.name, "")
    }

    func test_DiskMetricsData_handlesUnicodeStrings() throws {
        // Given - edge case with unicode characters
        let original = DiskMetricsData(
            mountPoint: "/Volumes/外部ディスク",
            name: "Disco Externo 日本語",
            totalBytes: 1_000_000_000_000,
            availableBytes: 500_000_000_000,
            usedBytes: 500_000_000_000,
            usagePercent: 50.0
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: DiskMetricsData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.mountPoint, original.mountPoint)
        XCTAssertEqual(decoded.name, original.name)
    }

    // MARK: - TemperatureData Tests

    func test_TemperatureData_conformsToNSSecureCoding() {
        // Given
        let metricsType = TemperatureData.self

        // Then
        XCTAssertTrue(metricsType.supportsSecureCoding,
                      "TemperatureData must support NSSecureCoding for XPC")
    }

    func test_TemperatureData_encodesAndDecodesCorrectly() throws {
        // Given
        let original = TemperatureData(
            cpuTemperature: 65.5,
            isSimulated: false
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: TemperatureData.self,
            from: encoded
        ))

        // Then
        XCTAssertEqual(decoded.cpuTemperature, original.cpuTemperature, accuracy: 0.001)
        XCTAssertEqual(decoded.isSimulated, original.isSimulated)
    }

    func test_TemperatureData_handlesSimulatedFlag() throws {
        // Given - simulated temperature (when real sensor unavailable)
        let original = TemperatureData(
            cpuTemperature: 45.0,
            isSimulated: true
        )

        // When
        let encoded = try NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        )

        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(
            ofClass: TemperatureData.self,
            from: encoded
        ))

        // Then
        XCTAssertTrue(decoded.isSimulated)
    }

    func test_TemperatureData_simulatedFromCpuUsage() {
        // Given
        let cpuUsage: Float = 50.0

        // When
        let temperature = TemperatureData.simulated(fromCpuUsage: cpuUsage)

        // Then
        XCTAssertTrue(temperature.isSimulated)
        XCTAssertEqual(temperature.cpuTemperature, 60.0, accuracy: 0.001) // 35 + 50*0.5 = 60
    }

    func test_TemperatureData_statusThresholds() {
        // Test cool
        let cool = TemperatureData(cpuTemperature: 45.0, isSimulated: false)
        XCTAssertEqual(cool.status, .cool)

        // Test warm
        let warm = TemperatureData(cpuTemperature: 60.0, isSimulated: false)
        XCTAssertEqual(warm.status, .warm)

        // Test hot
        let hot = TemperatureData(cpuTemperature: 75.0, isSimulated: false)
        XCTAssertEqual(hot.status, .hot)

        // Test critical
        let critical = TemperatureData(cpuTemperature: 90.0, isSimulated: false)
        XCTAssertEqual(critical.status, .critical)
    }
}
