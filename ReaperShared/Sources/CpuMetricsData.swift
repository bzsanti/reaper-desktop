import Foundation

/// CPU metrics data that can be serialized over XPC using NSSecureCoding
/// This type is shared between ReaperApp, ReaperMenuBar, and ReaperMetricsService
@objc public final class CpuMetricsData: NSObject, NSSecureCoding {

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { true }

    // MARK: - Properties

    @objc public let totalUsage: Float
    @objc public let coreCount: Int
    @objc public let loadAverage1: Double
    @objc public let loadAverage5: Double
    @objc public let loadAverage15: Double
    @objc public let frequencyMHz: UInt64

    // MARK: - Coding Keys

    private enum CodingKeys: String {
        case totalUsage
        case coreCount
        case loadAverage1
        case loadAverage5
        case loadAverage15
        case frequencyMHz
    }

    // MARK: - Initialization

    public init(
        totalUsage: Float,
        coreCount: Int,
        loadAverage1: Double,
        loadAverage5: Double,
        loadAverage15: Double,
        frequencyMHz: UInt64
    ) {
        self.totalUsage = totalUsage
        self.coreCount = coreCount
        self.loadAverage1 = loadAverage1
        self.loadAverage5 = loadAverage5
        self.loadAverage15 = loadAverage15
        self.frequencyMHz = frequencyMHz
        super.init()
    }

    // MARK: - NSCoding

    public required init?(coder: NSCoder) {
        self.totalUsage = coder.decodeFloat(forKey: CodingKeys.totalUsage.rawValue)
        self.coreCount = coder.decodeInteger(forKey: CodingKeys.coreCount.rawValue)
        self.loadAverage1 = coder.decodeDouble(forKey: CodingKeys.loadAverage1.rawValue)
        self.loadAverage5 = coder.decodeDouble(forKey: CodingKeys.loadAverage5.rawValue)
        self.loadAverage15 = coder.decodeDouble(forKey: CodingKeys.loadAverage15.rawValue)
        self.frequencyMHz = UInt64(coder.decodeInt64(forKey: CodingKeys.frequencyMHz.rawValue))
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(totalUsage, forKey: CodingKeys.totalUsage.rawValue)
        coder.encode(coreCount, forKey: CodingKeys.coreCount.rawValue)
        coder.encode(loadAverage1, forKey: CodingKeys.loadAverage1.rawValue)
        coder.encode(loadAverage5, forKey: CodingKeys.loadAverage5.rawValue)
        coder.encode(loadAverage15, forKey: CodingKeys.loadAverage15.rawValue)
        coder.encode(Int64(frequencyMHz), forKey: CodingKeys.frequencyMHz.rawValue)
    }

    // MARK: - Equatable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CpuMetricsData else { return false }
        return totalUsage == other.totalUsage &&
               coreCount == other.coreCount &&
               loadAverage1 == other.loadAverage1 &&
               loadAverage5 == other.loadAverage5 &&
               loadAverage15 == other.loadAverage15 &&
               frequencyMHz == other.frequencyMHz
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(totalUsage)
        hasher.combine(coreCount)
        hasher.combine(loadAverage1)
        hasher.combine(loadAverage5)
        hasher.combine(loadAverage15)
        hasher.combine(frequencyMHz)
        return hasher.finalize()
    }
}
