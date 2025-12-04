import Foundation

/// Disk metrics data that can be serialized over XPC using NSSecureCoding
/// This type is shared between ReaperApp, ReaperMenuBar, and ReaperMetricsService
@objc public final class DiskMetricsData: NSObject, NSSecureCoding {

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { true }

    // MARK: - Properties

    @objc public let mountPoint: String
    @objc public let name: String
    @objc public let totalBytes: UInt64
    @objc public let availableBytes: UInt64
    @objc public let usedBytes: UInt64
    @objc public let usagePercent: Float

    // MARK: - Coding Keys

    private enum CodingKeys: String {
        case mountPoint
        case name
        case totalBytes
        case availableBytes
        case usedBytes
        case usagePercent
    }

    // MARK: - Computed Properties

    /// Available space in gigabytes
    public var availableGB: Double {
        Double(availableBytes) / 1_073_741_824.0 // 1024^3
    }

    /// Total space in gigabytes
    public var totalGB: Double {
        Double(totalBytes) / 1_073_741_824.0
    }

    /// Human-readable available space string
    public var formattedAvailable: String {
        formatBytes(availableBytes)
    }

    /// Human-readable total space string
    public var formattedTotal: String {
        formatBytes(totalBytes)
    }

    // MARK: - Initialization

    public init(
        mountPoint: String,
        name: String,
        totalBytes: UInt64,
        availableBytes: UInt64,
        usedBytes: UInt64,
        usagePercent: Float
    ) {
        self.mountPoint = mountPoint
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.usedBytes = usedBytes
        self.usagePercent = usagePercent
        super.init()
    }

    // MARK: - NSCoding

    public required init?(coder: NSCoder) {
        self.mountPoint = coder.decodeObject(of: NSString.self, forKey: CodingKeys.mountPoint.rawValue) as String? ?? ""
        self.name = coder.decodeObject(of: NSString.self, forKey: CodingKeys.name.rawValue) as String? ?? ""
        self.totalBytes = UInt64(coder.decodeInt64(forKey: CodingKeys.totalBytes.rawValue))
        self.availableBytes = UInt64(coder.decodeInt64(forKey: CodingKeys.availableBytes.rawValue))
        self.usedBytes = UInt64(coder.decodeInt64(forKey: CodingKeys.usedBytes.rawValue))
        self.usagePercent = coder.decodeFloat(forKey: CodingKeys.usagePercent.rawValue)
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(mountPoint as NSString, forKey: CodingKeys.mountPoint.rawValue)
        coder.encode(name as NSString, forKey: CodingKeys.name.rawValue)
        coder.encode(Int64(totalBytes), forKey: CodingKeys.totalBytes.rawValue)
        coder.encode(Int64(availableBytes), forKey: CodingKeys.availableBytes.rawValue)
        coder.encode(Int64(usedBytes), forKey: CodingKeys.usedBytes.rawValue)
        coder.encode(usagePercent, forKey: CodingKeys.usagePercent.rawValue)
    }

    // MARK: - Equatable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? DiskMetricsData else { return false }
        return mountPoint == other.mountPoint &&
               name == other.name &&
               totalBytes == other.totalBytes &&
               availableBytes == other.availableBytes &&
               usedBytes == other.usedBytes &&
               usagePercent == other.usagePercent
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(mountPoint)
        hasher.combine(name)
        hasher.combine(totalBytes)
        hasher.combine(availableBytes)
        hasher.combine(usedBytes)
        hasher.combine(usagePercent)
        return hasher.finalize()
    }

    // MARK: - Private Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024.0 && unitIndex < units.count - 1 {
            size /= 1024.0
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        } else {
            return String(format: "%.1f %@", size, units[unitIndex])
        }
    }
}
