import Foundation

// MARK: - Safe FFI Utilities

/// Safely converts a C string pointer to Swift String
/// Returns empty string for nil pointers instead of crashing
///
/// This function should be used instead of direct String(cString:) when
/// the pointer might be nil. The dangerous pattern:
/// ```swift
/// // DANGEROUS - creates fake pointer that will crash
/// String(cString: cString ?? UnsafeMutablePointer<CChar>(bitPattern: 1)!)
/// ```
///
/// Should be replaced with:
/// ```swift
/// safeStringFromCChar(cString)
/// ```
///
/// - Parameter cString: Optional C string pointer
/// - Returns: String value, or empty string if pointer is nil
public func safeStringFromCChar(_ cString: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr = cString else { return "" }
    return String(cString: ptr)
}

/// Safely converts a const C string pointer to Swift String
/// Returns empty string for nil pointers instead of crashing
///
/// - Parameter cString: Optional const C string pointer
/// - Returns: String value, or empty string if pointer is nil
public func safeStringFromConstCChar(_ cString: UnsafePointer<CChar>?) -> String {
    guard let ptr = cString else { return "" }
    return String(cString: ptr)
}
