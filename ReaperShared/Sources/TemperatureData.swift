import Foundation

/// Temperature data that can be serialized over XPC using NSSecureCoding
/// This type is shared between ReaperApp, ReaperMenuBar, and ReaperMetricsService
@objc public final class TemperatureData: NSObject, NSSecureCoding {

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { true }

    // MARK: - Properties

    /// CPU temperature in Celsius
    @objc public let cpuTemperature: Float

    /// Whether the temperature is simulated (true when real sensor unavailable on macOS)
    @objc public let isSimulated: Bool

    // MARK: - Coding Keys

    private enum CodingKeys: String {
        case cpuTemperature
        case isSimulated
    }

    // MARK: - Computed Properties

    /// Temperature status based on thresholds
    public var status: TemperatureStatus {
        switch cpuTemperature {
        case ..<50:
            return .cool
        case 50..<70:
            return .warm
        case 70..<85:
            return .hot
        default:
            return .critical
        }
    }

    // MARK: - Initialization

    public init(cpuTemperature: Float, isSimulated: Bool) {
        self.cpuTemperature = cpuTemperature
        self.isSimulated = isSimulated
        super.init()
    }

    /// Create a simulated temperature based on CPU usage
    /// Used as fallback when real temperature sensors are unavailable
    public static func simulated(fromCpuUsage usage: Float) -> TemperatureData {
        let baseTemp: Float = 35.0
        let usageTemp = usage * 0.5
        return TemperatureData(cpuTemperature: baseTemp + usageTemp, isSimulated: true)
    }

    // MARK: - NSCoding

    public required init?(coder: NSCoder) {
        self.cpuTemperature = coder.decodeFloat(forKey: CodingKeys.cpuTemperature.rawValue)
        self.isSimulated = coder.decodeBool(forKey: CodingKeys.isSimulated.rawValue)
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(cpuTemperature, forKey: CodingKeys.cpuTemperature.rawValue)
        coder.encode(isSimulated, forKey: CodingKeys.isSimulated.rawValue)
    }

    // MARK: - Equatable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TemperatureData else { return false }
        return cpuTemperature == other.cpuTemperature &&
               isSimulated == other.isSimulated
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(cpuTemperature)
        hasher.combine(isSimulated)
        return hasher.finalize()
    }
}

// MARK: - Temperature Status

public enum TemperatureStatus: String {
    case cool     // < 50C
    case warm     // 50-70C
    case hot      // 70-85C
    case critical // > 85C

    public var emoji: String {
        switch self {
        case .cool: return "🟢"
        case .warm: return "🟡"
        case .hot: return "🟠"
        case .critical: return "🔴"
        }
    }
}
