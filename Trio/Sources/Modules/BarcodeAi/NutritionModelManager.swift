import Compression
import CoreML
import Foundation
import Observation

// MARK: - Nutrition Model Manager

extension BarcodeScanner {
    /// Manages the download, storage, and loading of the nutrition extraction CoreML model.
    @Observable final class NutritionModelManager {
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

        // MARK: - Initialization

        init() {
            checkModelStatus()
        }

        // MARK: - Public Methods

        /// Checks if the model is already downloaded and compiled
        func checkModelStatus() {
            // Don't reset state if model is already loaded
            if case .ready = state {
                print("🔍 Model already ready, skipping status check")
                return
            }
            if case .loading = state {
                print("🔍 Model is loading, skipping status check")
                return
            }

            let fileManager = FileManager.default

            print("🔍 Checking model status...")
            print("📁 Model directory: \(modelDirectory.path)")
            print("📁 Compiled model path: \(compiledModelPath.path)")
            print("📁 MLPackage path: \(mlpackagePath.path)")

            if fileManager.fileExists(atPath: compiledModelPath.path) {
                print("✅ Compiled model found at: \(compiledModelPath.path)")
                state = .downloaded
            } else if fileManager.fileExists(atPath: mlpackagePath.path) {
                print("✅ MLPackage found at: \(mlpackagePath.path)")
                state = .downloaded
            } else {
                print("❌ No model found")
                state = .notDownloaded
            }

            // List directory contents for debugging
            if let contents = try? fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil) {
                print("📂 Model directory contents: \(contents.map(\.lastPathComponent))")
            } else {
                print("📂 Model directory does not exist or is empty")
            }
        }

        /// Downloads the model from the given URL
        /// - Parameter urlString: URL string pointing to the ZIP file containing the mlpackage
        func downloadModel(from urlString: String) async {
            guard let url = URL(string: urlString) else {
                state = .error(ModelError.invalidURL.localizedDescription)
                return
            }

            state = .downloading(progress: 0)
            downloadProgress = 0

            do {
                // Create model directory if needed
                try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

                // Download the ZIP file
                let zipPath = try await downloadFile(from: url)

                // Extract the ZIP file
                state = .downloading(progress: 0.8)
                try await extractZipFile(at: zipPath)

                // Clean up ZIP file
                try? FileManager.default.removeItem(at: zipPath)

                // Compile the model
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
            print("🚀 Starting model load...")
            print("📊 Current state: \(String(describing: state))")

            guard state == .downloaded || state == .ready else {
                print("❌ Cannot load model - invalid state: \(String(describing: state))")
                throw ModelError.modelNotFound
            }

            state = .loading
            print("⏳ State changed to loading")

            do {
                let config = MLModelConfiguration()
                // Use CPU only for maximum compatibility across devices
                config.computeUnits = .cpuOnly
                print("⚙️ Using CPU-only compute units for compatibility")

                // Try to load compiled model first
                if FileManager.default.fileExists(atPath: compiledModelPath.path) {
                    print("📦 Loading compiled model from: \(compiledModelPath.path)")

                    // Log file size
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: compiledModelPath.path) {
                        let size = attrs[.size] as? Int64 ?? 0
                        print("📏 Model file size: \(size) bytes")
                    }

                    model = try MLModel(contentsOf: compiledModelPath, configuration: config)
                    print("✅ Model loaded successfully from compiled model")

                } else if FileManager.default.fileExists(atPath: mlpackagePath.path) {
                    print("📦 MLPackage found, need to compile first")
                    // Compile and load
                    try await compileModel()
                    print("📦 Loading freshly compiled model")
                    model = try MLModel(contentsOf: compiledModelPath, configuration: config)
                    print("✅ Model loaded successfully after compilation")
                } else {
                    print("❌ No model file found at expected paths")
                    throw ModelError.modelNotFound
                }

                // Log model details
                if let loadedModel = model {
                    print("📋 Model description: \(loadedModel.modelDescription.description)")
                    print(
                        "📥 Model inputs: \(loadedModel.modelDescription.inputDescriptionsByName.keys.joined(separator: ", "))"
                    )
                    print(
                        "📤 Model outputs: \(loadedModel.modelDescription.outputDescriptionsByName.keys.joined(separator: ", "))"
                    )

                    // Log input details
                    for (name, desc) in loadedModel.modelDescription.inputDescriptionsByName {
                        print("  📥 Input '\(name)': type=\(desc.type.rawValue), \(desc.description)")
                    }

                    // Log output details
                    for (name, desc) in loadedModel.modelDescription.outputDescriptionsByName {
                        print("  📤 Output '\(name)': type=\(desc.type.rawValue), \(desc.description)")
                    }
                }

                state = .ready
                print("✅ Model is ready for inference")
            } catch {
                print("❌ Failed to load model: \(error.localizedDescription)")
                print("❌ Error details: \(String(describing: error))")
                state = .error(ModelError.loadingFailed(error.localizedDescription).localizedDescription)
                throw ModelError.loadingFailed(error.localizedDescription)
            }
        }

        /// Runs inference on the model with the given inputs
        func predict(with featureProvider: MLFeatureProvider) async throws -> MLFeatureProvider {
            print("🔮 Starting prediction...")

            guard let model else {
                print("❌ No model loaded for prediction")
                throw ModelError.modelNotFound
            }

            print("📥 Input features: \(featureProvider.featureNames.joined(separator: ", "))")

            // Log input feature details
            for name in featureProvider.featureNames {
                if let value = featureProvider.featureValue(for: name) {
                    print("  📥 '\(name)': type=\(value.type.rawValue)")
                    if let multiArray = value.multiArrayValue {
                        print("    Shape: \(multiArray.shape), DataType: \(multiArray.dataType.rawValue)")
                    }
                }
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try model.prediction(from: featureProvider)
                }.value

                print("✅ Prediction completed successfully")
                print("📤 Output features: \(result.featureNames.joined(separator: ", "))")

                // Log output details
                for name in result.featureNames {
                    if let value = result.featureValue(for: name) {
                        print("  📤 '\(name)': type=\(value.type.rawValue)")
                        if let multiArray = value.multiArrayValue {
                            print("    Shape: \(multiArray.shape), DataType: \(multiArray.dataType.rawValue)")
                        } else if value.type == .dictionary {
                            print("    Dictionary with \(value.dictionaryValue.count) entries")
                        }
                    }
                }

                return result
            } catch {
                print("❌ Prediction failed: \(error.localizedDescription)")
                print("❌ Error details: \(String(describing: error))")
                throw error
            }
        }

        /// Deletes the downloaded model
        func deleteModel() {
            print("🗑️ Deleting model...")
            try? FileManager.default.removeItem(at: modelDirectory)
            model = nil
            state = .notDownloaded
            downloadProgress = 0
            print("✅ Model deleted")
        }

        /// Cancels ongoing download
        func cancelDownload() {
            print("❌ Cancelling download")
            downloadTask?.cancel()
            downloadTask = nil
            state = .notDownloaded
            downloadProgress = 0
        }

        /// Imports a model from a file URL (selected via document picker)
        /// - Parameter fileURL: URL to the .mlpackage, .mlmodel, .mlmodelc, or .zip file
        func importModel(from fileURL: URL) async {
            print("📥 Importing model from: \(fileURL.path)")
            print("📄 File extension: \(fileURL.pathExtension)")

            state = .downloading(progress: 0.1)
            downloadProgress = 0.1

            do {
                // Start accessing security-scoped resource
                let accessing = fileURL.startAccessingSecurityScopedResource()
                print("🔐 Security scoped access: \(accessing)")
                defer {
                    if accessing {
                        fileURL.stopAccessingSecurityScopedResource()
                        print("🔐 Released security scoped access")
                    }
                }

                // Check if file exists
                let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
                print("📄 File exists: \(fileExists)")

                if !fileExists {
                    print("❌ File does not exist at path: \(fileURL.path)")
                    throw ModelError.extractionFailed("File does not exist")
                }

                // Get file attributes
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                    let size = attrs[.size] as? Int64 ?? 0
                    let type = attrs[.type] as? FileAttributeType
                    print("📏 File size: \(size) bytes, type: \(String(describing: type))")
                }

                // Create model directory if needed
                try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
                print("📁 Created model directory: \(modelDirectory.path)")

                let fileExtension = fileURL.pathExtension.lowercased()

                switch fileExtension {
                case "zip":
                    print("📦 Processing ZIP file")
                    // Copy ZIP to local directory and extract
                    let localZipPath = modelDirectory.appendingPathComponent("model.zip")
                    try? FileManager.default.removeItem(at: localZipPath)
                    try FileManager.default.copyItem(at: fileURL, to: localZipPath)
                    print("📋 Copied ZIP to: \(localZipPath.path)")

                    state = .downloading(progress: 0.4)
                    try await extractZipFile(at: localZipPath)
                    print("✅ ZIP extracted")

                    // Clean up ZIP
                    try? FileManager.default.removeItem(at: localZipPath)

                case "mlpackage":
                    print("📦 Processing mlpackage directory")
                    // Copy mlpackage directory
                    try? FileManager.default.removeItem(at: mlpackagePath)
                    try FileManager.default.copyItem(at: fileURL, to: mlpackagePath)
                    print("✅ Copied mlpackage to: \(mlpackagePath.path)")

                case "mlmodelc":
                    print("📦 Processing pre-compiled mlmodelc")
                    // Already compiled, copy directly
                    try? FileManager.default.removeItem(at: compiledModelPath)
                    try FileManager.default.copyItem(at: fileURL, to: compiledModelPath)
                    print("✅ Copied compiled model to: \(compiledModelPath.path)")
                    state = .downloaded
                    downloadProgress = 1.0
                    return

                case "mlmodel":
                    print("📦 Processing legacy mlmodel file")
                    // Legacy format, copy and compile
                    let mlmodelPath = modelDirectory.appendingPathComponent("nutrition_extractor.mlmodel")
                    try? FileManager.default.removeItem(at: mlmodelPath)
                    try FileManager.default.copyItem(at: fileURL, to: mlmodelPath)
                    print("📋 Copied mlmodel to: \(mlmodelPath.path)")

                    // Compile the mlmodel
                    print("⚙️ Compiling mlmodel...")
                    state = .downloading(progress: 0.7)
                    let compiledURL = try await Task.detached(priority: .userInitiated) {
                        try MLModel.compileModel(at: mlmodelPath)
                    }.value
                    print("✅ Compilation successful, output at: \(compiledURL.path)")

                    try? FileManager.default.removeItem(at: compiledModelPath)
                    try FileManager.default.moveItem(at: compiledURL, to: compiledModelPath)
                    print("✅ Moved compiled model to: \(compiledModelPath.path)")

                    // Clean up mlmodel
                    try? FileManager.default.removeItem(at: mlmodelPath)

                    state = .downloaded
                    downloadProgress = 1.0
                    return

                default:
                    print("❌ Unsupported file type: \(fileExtension)")
                    throw ModelError.extractionFailed("Unsupported file type: .\(fileExtension)")
                }

                // Compile the model if we have mlpackage
                print("⚙️ Compiling mlpackage...")
                state = .downloading(progress: 0.8)
                try await compileModel()

                state = .downloaded
                downloadProgress = 1.0
                print("✅ Model import completed successfully")
            } catch {
                print("❌ Import failed: \(error.localizedDescription)")
                print("❌ Error details: \(String(describing: error))")
                state = .error(error.localizedDescription)
            }
        }

        // MARK: - Private Methods

        private func downloadFile(from url: URL) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
                let destinationURL = modelDirectory.appendingPathComponent("model.zip")

                let task = session.downloadTask(with: url) { tempURL, _, error in
                    if let error {
                        continuation.resume(throwing: ModelError.downloadFailed(error.localizedDescription))
                        return
                    }

                    guard let tempURL else {
                        continuation.resume(throwing: ModelError.downloadFailed("No file received"))
                        return
                    }

                    do {
                        // Remove existing file if present
                        try? FileManager.default.removeItem(at: destinationURL)
                        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                        continuation.resume(returning: destinationURL)
                    } catch {
                        continuation.resume(throwing: ModelError.downloadFailed(error.localizedDescription))
                    }
                }

                // Observe progress
                let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    Task { @MainActor in
                        self?.downloadProgress = progress.fractionCompleted * 0.7 // 70% for download
                        self?.state = .downloading(progress: self?.downloadProgress ?? 0)
                    }
                }

                self.downloadTask = task
                task.resume()

                // Store observation to keep it alive
                _ = observation
            }
        }

        private func extractZipFile(at zipURL: URL) async throws {
            try await Task.detached(priority: .userInitiated) { [self] in
                let fileManager = FileManager.default
                let destinationURL = modelDirectory

                do {
                    // Use native unzip via FileManager
                    try self.unzipFile(at: zipURL, to: destinationURL)

                    // Find the mlpackage in extracted contents
                    let contents = try fileManager.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil)
                    var foundMLPackage = false

                    for item in contents {
                        if item.pathExtension == "mlpackage" {
                            // Rename to expected name if different
                            if item.lastPathComponent != mlpackageName {
                                let targetPath = mlpackagePath
                                try? fileManager.removeItem(at: targetPath)
                                try fileManager.moveItem(at: item, to: targetPath)
                            }
                            foundMLPackage = true
                            break
                        }

                        // Check subdirectories
                        if item.hasDirectoryPath {
                            let subContents = try fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                            for subItem in subContents {
                                if subItem.pathExtension == "mlpackage" {
                                    let targetPath = mlpackagePath
                                    try? fileManager.removeItem(at: targetPath)
                                    try fileManager.moveItem(at: subItem, to: targetPath)
                                    foundMLPackage = true
                                    break
                                }
                            }
                        }
                    }

                    if !foundMLPackage {
                        throw ModelError.extractionFailed("No .mlpackage found in ZIP")
                    }
                } catch let error as ModelError {
                    throw error
                } catch {
                    throw ModelError.extractionFailed(error.localizedDescription)
                }
            }.value
        }

        /// Unzips a file using native methods
        private func unzipFile(at sourceURL: URL, to destinationURL: URL) throws {
            print("📦 Unzipping file: \(sourceURL.path)")
            print("📁 Destination: \(destinationURL.path)")

            let fileManager = FileManager.default

            // Read the ZIP file
            let zipData = try Data(contentsOf: sourceURL)
            print("📏 ZIP file size: \(zipData.count) bytes")

            // Parse ZIP file structure and extract
            try extractZipData(zipData, to: destinationURL, fileManager: fileManager)
            print("✅ ZIP extraction completed")
        }

        /// Extracts ZIP data to the destination directory
        private func extractZipData(_ data: Data, to destinationURL: URL, fileManager: FileManager) throws {
            // ZIP file structure constants
            let localFileHeaderSignature: UInt32 = 0x0403_4B50
            let centralDirectorySignature: UInt32 = 0x0201_4B50

            var offset = 0

            while offset < data.count - 4 {
                let signature = readUInt32(from: data, at: offset)

                if signature == localFileHeaderSignature {
                    // Parse local file header
                    let entry = try parseLocalFileHeader(data: data, offset: offset)

                    // Calculate where file data starts
                    let dataStart = offset + 30 + Int(entry.fileNameLength) + Int(entry.extraFieldLength)
                    let dataEnd = dataStart + Int(entry.compressedSize)

                    guard dataEnd <= data.count else {
                        throw ModelError.extractionFailed("Invalid ZIP structure")
                    }

                    // Get file data
                    let fileData = data.subdata(in: dataStart ..< dataEnd)

                    // Decompress if needed
                    let decompressedData: Data
                    if entry.compressionMethod == 0 {
                        // Stored (no compression)
                        decompressedData = fileData
                    } else if entry.compressionMethod == 8 {
                        // Deflate compression
                        decompressedData = try decompressDeflate(fileData, uncompressedSize: Int(entry.uncompressedSize))
                    } else {
                        throw ModelError.extractionFailed("Unsupported compression method: \(entry.compressionMethod)")
                    }

                    // Create file path
                    let filePath = destinationURL.appendingPathComponent(entry.fileName)

                    // Create directory if needed
                    if entry.fileName.hasSuffix("/") {
                        try fileManager.createDirectory(at: filePath, withIntermediateDirectories: true)
                    } else {
                        // Create parent directory
                        try fileManager.createDirectory(
                            at: filePath.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        // Write file
                        try decompressedData.write(to: filePath)
                    }

                    offset = dataEnd
                } else if signature == centralDirectorySignature {
                    // Reached central directory, we're done with file entries
                    break
                } else {
                    offset += 1
                }
            }
        }

        private struct ZipEntry {
            let compressionMethod: UInt16
            let compressedSize: UInt32
            let uncompressedSize: UInt32
            let fileNameLength: UInt16
            let extraFieldLength: UInt16
            let fileName: String
        }

        private func parseLocalFileHeader(data: Data, offset: Int) throws -> ZipEntry {
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

        // MARK: - Safe Byte Reading (handles unaligned memory)

        private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
            guard offset + 2 <= data.count else { return 0 }
            return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }

        private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
            guard offset + 4 <= data.count else { return 0 }
            return UInt32(data[offset]) |
                (UInt32(data[offset + 1]) << 8) |
                (UInt32(data[offset + 2]) << 16) |
                (UInt32(data[offset + 3]) << 24)
        }

        private func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
            // Use Compression framework for deflate decompression
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

        private func compileModel() async throws {
            print("⚙️ Starting model compilation...")
            print("📁 Source: \(mlpackagePath.path)")

            // Check if mlpackage exists
            guard FileManager.default.fileExists(atPath: mlpackagePath.path) else {
                print("❌ MLPackage not found at: \(mlpackagePath.path)")
                throw ModelError.modelNotFound
            }

            // List mlpackage contents
            if let contents = try? FileManager.default.contentsOfDirectory(at: mlpackagePath, includingPropertiesForKeys: nil) {
                print("📂 MLPackage contents: \(contents.map(\.lastPathComponent))")
            }

            try await Task.detached(priority: .userInitiated) { [self] in
                do {
                    print("⚙️ Calling MLModel.compileModel...")
                    let compiledURL = try MLModel.compileModel(at: mlpackagePath)
                    print("✅ Compilation output at: \(compiledURL.path)")

                    // Move compiled model to our directory
                    let fileManager = FileManager.default
                    try? fileManager.removeItem(at: compiledModelPath)
                    try fileManager.moveItem(at: compiledURL, to: compiledModelPath)
                    print("✅ Moved compiled model to: \(self.compiledModelPath.path)")
                } catch {
                    print("❌ Compilation failed: \(error.localizedDescription)")
                    print("❌ Error details: \(String(describing: error))")
                    throw ModelError.compilationFailed(error.localizedDescription)
                }
            }.value
        }

        /// Gets the loaded model for direct access if needed
        var loadedModel: MLModel? {
            model
        }

        /// Whether the model is ready for inference
        var isReady: Bool {
            state == .ready && model != nil
        }
    }
}
