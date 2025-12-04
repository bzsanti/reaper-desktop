import XCTest
@testable import ReaperShared

/// Tests for safe C string conversion utilities
/// These tests validate that null pointers are handled safely without crashes
final class PointerSafetyTests: XCTestCase {

    // MARK: - Safe String Conversion Tests

    func test_safeStringFromCChar_withValidPointer_returnsString() {
        let testString = "test_mount_point"
        var mutableCString = Array(testString.utf8CString)

        mutableCString.withUnsafeMutableBufferPointer { buffer in
            let result = safeStringFromCChar(buffer.baseAddress)
            XCTAssertEqual(result, testString)
        }
    }

    func test_safeStringFromCChar_withNullPointer_returnsEmptyString() {
        let result = safeStringFromCChar(nil)
        XCTAssertEqual(result, "", "Null pointer should return empty string, not crash")
    }

    func test_safeStringFromCChar_withEmptyString_returnsEmptyString() {
        let emptyString = ""
        var mutableCString = Array(emptyString.utf8CString)

        mutableCString.withUnsafeMutableBufferPointer { buffer in
            let result = safeStringFromCChar(buffer.baseAddress)
            XCTAssertEqual(result, "")
        }
    }

    func test_safeStringFromCChar_withUnicodeString_returnsCorrectString() {
        let unicodeString = "Disco /Volumen"
        var mutableCString = Array(unicodeString.utf8CString)

        mutableCString.withUnsafeMutableBufferPointer { buffer in
            let result = safeStringFromCChar(buffer.baseAddress)
            XCTAssertEqual(result, unicodeString)
        }
    }

    func test_safeStringFromCChar_withSpecialCharacters_returnsCorrectString() {
        let specialString = "/Volumes/WD_BLACK/repos"
        var mutableCString = Array(specialString.utf8CString)

        mutableCString.withUnsafeMutableBufferPointer { buffer in
            let result = safeStringFromCChar(buffer.baseAddress)
            XCTAssertEqual(result, specialString)
        }
    }

    // MARK: - DiskMetricsData Safety Tests

    func test_DiskMetricsData_initWithEmptyMountPoint_createsValidInstance() {
        // Simulates what happens when C string is null and converted to empty string
        let data = DiskMetricsData(
            mountPoint: "",  // Result of safe conversion from nil
            name: "Disk",
            totalBytes: 1000,
            availableBytes: 500,
            usedBytes: 500,
            usagePercent: 50.0
        )

        XCTAssertEqual(data.mountPoint, "")
        XCTAssertEqual(data.name, "Disk")
    }

    func test_DiskMetricsData_initWithEmptyName_createsValidInstance() {
        let data = DiskMetricsData(
            mountPoint: "/",
            name: "",  // Result of safe conversion from nil
            totalBytes: 1000,
            availableBytes: 500,
            usedBytes: 500,
            usagePercent: 50.0
        )

        XCTAssertEqual(data.mountPoint, "/")
        XCTAssertEqual(data.name, "")
    }
}

// Note: safeStringFromCChar is defined in FFIUtilities.swift
