import Compression
import CoreML
import Foundation
import Observation

// MARK: - Nutrition Model Manager

extension BarcodeScanner {
    /// Manages the download, storage, and loading of the nutrition extraction CoreML model
    @Observable final class NutritionModelManager {
        // MARK: - Shared Instance

        static let shared = NutritionModelManager()

        // MARK: - Types

        enum ModelState: Equatable {
            case notDownloaded
            case downloading(progress: Double)
            case downloaded
            case loading
            case ready
            case error(String)

            static func == (lhs: ModelState, rhs: ModelState) -> Bool {
                switch (lhs, rhs) {
                case (.downloaded, .downloaded),
                     (.loading, .loading),
                     (.notDownloaded, .notDownloaded),
                     (.ready, .ready):
                    true
                case let (.downloading(p1), .downloading(p2)):
                    p1 == p2
                case let (.error(e1), .error(e2)):
                    e1 == e2
                default:
                    false
                }
            }
        }

        enum ModelError: LocalizedError {
            case invalidURL
            case downloadFailed(String)
            case extractionFailed(String)
            case compilationFailed(String)
            case loadingFailed(String)
            case modelNotFound

            var errorDescription: String? {
                switch self {
                case .invalidURL:
                    String(localized: "Invalid model URL provided.")
                case let .downloadFailed(reason):
                    String(localized: "Download failed: \(reason)")
                case let .extractionFailed(reason):
                    String(localized: "Failed to extract model: \(reason)")
                case let .compilationFailed(reason):
                    String(localized: "Failed to compile model: \(reason)")
                case let .loadingFailed(reason):
                    String(localized: "Failed to load model: \(reason)")
                case .modelNotFound:
                    String(localized: "Model file not found.")
                }
            }
        }

        // MARK: - Properties

        var state: ModelState = .notDownloaded
        var downloadProgress: Double = 0

        private var model: MLModel?
        private var downloadTask: URLSessionDownloadTask?
        private var downloadDelegate: DownloadDelegate?

        // File paths
        private let modelDirectoryName = "NutritionExtractor"
        private let mlpackageName = "nutrition_extractor.mlpackage"
        private let compiledModelName = "nutrition_extractor.mlmodelc"

        private var documentsDirectory: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }

        private var modelDirectory: URL {
            documentsDirectory.appendingPathComponent(modelDirectoryName)
        }

        private var mlpackagePath: URL {
            modelDirectory.appendingPathComponent(mlpackageName)
        }

        private var compiledModelPath: URL {
            modelDirectory.appendingPathComponent(compiledModelName)
        }

        /// Gets the loaded model for direct access
        var loadedModel: MLModel? {
            model
        }

        /// Whether the model is ready for inference
        var isReady: Bool {
            state == .ready && model != nil
        }

        // MARK: - Initialization

        init() {
            checkModelStatus()
        }

        // MARK: - Public Methods

        /// Checks if the model is already downloaded and compiled
        func checkModelStatus() {
            // Don't reset state if model is already loaded
            if case .ready = state { return }
            if case .loading = state { return }

            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: compiledModelPath.path) {
                state = .downloaded
            } else if fileManager.fileExists(atPath: mlpackagePath.path) {
                state = .downloaded
            } else {
                state = .notDownloaded
            }
        }

        /// Downloads the model from the given URL
        func downloadModel(from urlString: String) async {
            guard let url = URL(string: urlString) else {
                state = .error(ModelError.invalidURL.localizedDescription)
                return
            }

            state = .downloading(progress: 0)
            downloadProgress = 0

            do {
                try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
                let archivePath = try await downloadFile(from: url)

                state = .downloading(progress: 0.8)
                try await extractArchive(at: archivePath)

                try? FileManager.default.removeItem(at: archivePath)

                state = .downloading(progress: 0.9)
                try await compileModel()

                state = .downloaded
                downloadProgress = 1.0
            } catch {
                state = .error(error.localizedDescription)
            }
        }

        /// Loads the model into memory for inference
        func loadModel() async throws {
            guard state == .downloaded || state == .ready else {
                throw ModelError.modelNotFound
            }

            state = .loading

            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all

                if FileManager.default.fileExists(atPath: compiledModelPath.path) {
                    model = try MLModel(contentsOf: compiledModelPath, configuration: config)
                } else if FileManager.default.fileExists(atPath: mlpackagePath.path) {
                    try await compileModel()
                    model = try MLModel(contentsOf: compiledModelPath, configuration: config)
                } else {
                    throw ModelError.modelNotFound
                }

                state = .ready
            } catch {
                state = .error(ModelError.loadingFailed(error.localizedDescription).localizedDescription)
                throw ModelError.loadingFailed(error.localizedDescription)
            }
        }

        /// Runs inference on the model with the given inputs
        func predict(with featureProvider: MLFeatureProvider) async throws -> MLFeatureProvider {
            guard let model else {
                throw ModelError.modelNotFound
            }

            return try await Task.detached(priority: .userInitiated) {
                try model.prediction(from: featureProvider)
            }.value
        }

        /// Deletes the downloaded model
        func deleteModel() {
            try? FileManager.default.removeItem(at: modelDirectory)
            model = nil
            state = .notDownloaded
            downloadProgress = 0
        }

        /// Cancels ongoing download
        func cancelDownload() {
            downloadTask?.cancel()
            downloadTask = nil
            state = .notDownloaded
            downloadProgress = 0
        }

        /// Imports a model from a file URL
        func importModel(from fileURL: URL) async {
            state = .downloading(progress: 0.1)
            downloadProgress = 0.1

            do {
                let accessing = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw ModelError.extractionFailed("File does not exist")
                }

                try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

                let fileExtension = fileURL.pathExtension.lowercased()

                switch fileExtension {
                case "tar",
                     "zip":
                    let localArchivePath = modelDirectory.appendingPathComponent("model.\(fileExtension)")
                    try? FileManager.default.removeItem(at: localArchivePath)
                    try FileManager.default.copyItem(at: fileURL, to: localArchivePath)

                    state = .downloading(progress: 0.4)
                    try await extractArchive(at: localArchivePath)
                    try? FileManager.default.removeItem(at: localArchivePath)

                case "mlpackage":
                    try? FileManager.default.removeItem(at: mlpackagePath)
                    try FileManager.default.copyItem(at: fileURL, to: mlpackagePath)

                case "mlmodelc":
                    try? FileManager.default.removeItem(at: compiledModelPath)
                    try FileManager.default.copyItem(at: fileURL, to: compiledModelPath)
                    state = .downloaded
                    downloadProgress = 1.0
                    return

                case "mlmodel":
                    let mlmodelPath = modelDirectory.appendingPathComponent("nutrition_extractor.mlmodel")
                    try? FileManager.default.removeItem(at: mlmodelPath)
                    try FileManager.default.copyItem(at: fileURL, to: mlmodelPath)

                    state = .downloading(progress: 0.7)
                    let compiledURL = try await Task.detached(priority: .userInitiated) {
                        try MLModel.compileModel(at: mlmodelPath)
                    }.value

                    try? FileManager.default.removeItem(at: compiledModelPath)
                    try FileManager.default.moveItem(at: compiledURL, to: compiledModelPath)
                    try? FileManager.default.removeItem(at: mlmodelPath)

                    state = .downloaded
                    downloadProgress = 1.0
                    return

                default:
                    throw ModelError.extractionFailed("Unsupported file type: .\(fileExtension)")
                }

                state = .downloading(progress: 0.8)
                try await compileModel()

                state = .downloaded
                downloadProgress = 1.0
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - Download Delegate

private extension BarcodeScanner.NutritionModelManager {
    class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        weak var manager: BarcodeScanner.NutritionModelManager?
        var continuation: CheckedContinuation<URL, Error>?
        var destinationURL: URL?

        func urlSession(
            _: URLSession,
            downloadTask _: URLSessionDownloadTask,
            didWriteData _: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            let progress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0

            Task { @MainActor [weak self] in
                let downloadProgress = progress * 0.7
                self?.manager?.downloadProgress = downloadProgress
                self?.manager?.state = .downloading(progress: downloadProgress)
            }
        }

        func urlSession(
            _: URLSession,
            downloadTask _: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            guard let destinationURL else {
                continuation?.resume(
                    throwing: BarcodeScanner.NutritionModelManager.ModelError.downloadFailed("No destination URL")
                )
                return
            }

            do {
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.moveItem(at: location, to: destinationURL)
                continuation?.resume(returning: destinationURL)
            } catch {
                continuation?.resume(
                    throwing: BarcodeScanner.NutritionModelManager.ModelError.downloadFailed(error.localizedDescription)
                )
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(
                    throwing: BarcodeScanner.NutritionModelManager.ModelError.downloadFailed(error.localizedDescription)
                )
            }
        }
    }
}

// MARK: - Private Methods

private extension BarcodeScanner.NutritionModelManager {
    func downloadFile(from url: URL) async throws -> URL {
        let destinationURL = modelDirectory.appendingPathComponent("model.zip")

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate()
            delegate.manager = self
            delegate.continuation = continuation
            delegate.destinationURL = destinationURL
            self.downloadDelegate = delegate

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 1200

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
            let task = session.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    func extractArchive(at archiveURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) { [self] in
            let fileManager = FileManager.default
            let destinationURL = modelDirectory

            try unzipFile(at: archiveURL, to: destinationURL)

            let contents = try fileManager.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil)
            var foundMLPackage = false

            for item in contents {
                var isDir: ObjCBool = false
                let exists = fileManager.fileExists(atPath: item.path, isDirectory: &isDir)

                if exists, isDir.boolValue, item.pathExtension == "mlpackage" {
                    if item.lastPathComponent != mlpackageName {
                        let targetPath = mlpackagePath
                        try? fileManager.removeItem(at: targetPath)
                        try fileManager.moveItem(at: item, to: targetPath)
                    }
                    foundMLPackage = true
                    break
                }

                // Check subdirectories
                if exists, isDir.boolValue {
                    let subContents = try fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                    for subItem in subContents {
                        var subIsDir: ObjCBool = false
                        let subExists = fileManager.fileExists(atPath: subItem.path, isDirectory: &subIsDir)

                        if subExists, subIsDir.boolValue, subItem.pathExtension == "mlpackage" {
                            let targetPath = mlpackagePath
                            try? fileManager.removeItem(at: targetPath)
                            try fileManager.moveItem(at: subItem, to: targetPath)
                            foundMLPackage = true
                            break
                        }
                    }
                }

                if foundMLPackage { break }
            }

            if !foundMLPackage {
                throw ModelError.extractionFailed("No .mlpackage directory found in archive")
            }
        }.value
    }

    func unzipFile(at sourceURL: URL, to destinationURL: URL) throws {
        let zipData = try Data(contentsOf: sourceURL)
        try extractZipData(zipData, to: destinationURL)
    }

    func extractZipData(_ data: Data, to destinationURL: URL) throws {
        let localFileHeaderSignature: UInt32 = 0x0403_4B50
        let centralDirectorySignature: UInt32 = 0x0201_4B50

        var offset = 0

        while offset < data.count - 4 {
            let signature = readUInt32(from: data, at: offset)

            if signature == localFileHeaderSignature {
                let entry = try parseLocalFileHeader(data: data, offset: offset)

                let dataStart = offset + 30 + Int(entry.fileNameLength) + Int(entry.extraFieldLength)
                let dataEnd = dataStart + Int(entry.compressedSize)

                guard dataEnd <= data.count else {
                    throw ModelError.extractionFailed("Invalid ZIP structure")
                }

                let fileData = data.subdata(in: dataStart ..< dataEnd)

                let decompressedData: Data
                if entry.compressionMethod == 0 {
                    decompressedData = fileData
                } else if entry.compressionMethod == 8 {
                    decompressedData = try decompressDeflate(fileData, uncompressedSize: Int(entry.uncompressedSize))
                } else {
                    throw ModelError.extractionFailed("Unsupported compression method: \(entry.compressionMethod)")
                }

                let filePath = destinationURL.appendingPathComponent(entry.fileName)

                if entry.fileName.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: filePath, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(
                        at: filePath.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try decompressedData.write(to: filePath)
                }

                offset = dataEnd
            } else if signature == centralDirectorySignature {
                break
            } else {
                offset += 1
            }
        }
    }

    struct ZipEntry {
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let fileNameLength: UInt16
        let extraFieldLength: UInt16
        let fileName: String
    }

    func parseLocalFileHeader(data: Data, offset: Int) throws -> ZipEntry {
        guard offset + 30 <= data.count else {
            throw ModelError.extractionFailed("Invalid ZIP header")
        }

        let compressionMethod = readUInt16(from: data, at: offset + 8)
        let compressedSize = readUInt32(from: data, at: offset + 18)
        let uncompressedSize = readUInt32(from: data, at: offset + 22)
        let fileNameLength = readUInt16(from: data, at: offset + 26)
        let extraFieldLength = readUInt16(from: data, at: offset + 28)

        let fileNameStart = offset + 30
        let fileNameEnd = fileNameStart + Int(fileNameLength)

        guard fileNameEnd <= data.count else {
            throw ModelError.extractionFailed("Invalid file name in ZIP")
        }

        let fileNameData = data.subdata(in: fileNameStart ..< fileNameEnd)
        guard let fileName = String(data: fileNameData, encoding: .utf8) else {
            throw ModelError.extractionFailed("Invalid file name encoding")
        }

        return ZipEntry(
            compressionMethod: compressionMethod,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            fileNameLength: fileNameLength,
            extraFieldLength: extraFieldLength,
            fileName: fileName
        )
    }

    func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                uncompressedSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw ModelError.extractionFailed("Decompression failed")
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    func compileModel() async throws {
        guard FileManager.default.fileExists(atPath: mlpackagePath.path) else {
            throw ModelError.modelNotFound
        }

        try await Task.detached(priority: .userInitiated) { [self] in
            let compiledURL = try MLModel.compileModel(at: mlpackagePath)
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: compiledModelPath)
            try fileManager.moveItem(at: compiledURL, to: compiledModelPath)
        }.value
    }
}
