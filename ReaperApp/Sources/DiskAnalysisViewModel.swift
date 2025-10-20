import SwiftUI

@MainActor
class DiskAnalysisViewModel: ObservableObject {
    @Published var largestFiles: [FileEntry] = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var categoryStats: FileCategoryStats?
    @Published var scanProgress: Double = 0
    @Published var isScanning: Bool = false
    @Published var scanError: String?
    @Published var selectedPath: String = ""
    @Published var totalSize: UInt64 = 0
    @Published var fileCount: Int = 0

    private let bridge: RustBridge

    init(bridge: RustBridge) {
        self.bridge = bridge
    }

    func startDirectoryScan(path: String, topN: Int = 100, minSize: UInt64 = 1024 * 1024) async {
        isScanning = true
        scanError = nil
        scanProgress = 0
        largestFiles = []
        categoryStats = nil
        totalSize = 0
        fileCount = 0

        do {
            let analysis = try await bridge.analyzeDirectory(
                path: path,
                topN: topN,
                minSize: minSize,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = progress
                    }
                }
            )

            largestFiles = analysis.largestFiles
            categoryStats = analysis.categoryStats
            totalSize = analysis.totalSize
            fileCount = analysis.fileCount
        } catch {
            scanError = error.localizedDescription
        }

        isScanning = false
    }

    func startDuplicateScan(path: String, minSize: UInt64 = 1024 * 1024) async {
        isScanning = true
        scanError = nil
        scanProgress = 0
        duplicates = []

        do {
            duplicates = try await bridge.findDuplicates(
                path: path,
                minSize: minSize,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = progress
                    }
                }
            )
        } catch {
            scanError = error.localizedDescription
        }

        isScanning = false
    }

    func cancelScan() {
        bridge.cancelCurrentAnalysis()
        isScanning = false
    }

    var totalWastedSpace: UInt64 {
        duplicates.reduce(0) { $0 + $1.wastedSpace }
    }

    var totalWastedSpaceFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalWastedSpace), countStyle: .file)
    }
}
