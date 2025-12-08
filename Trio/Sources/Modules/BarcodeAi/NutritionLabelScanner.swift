import CoreML
import Foundation
import UIKit
import Vision

// MARK: - Nutrition Label Scanner

extension BarcodeScanner {
    /// Scans nutrition labels from images using Apple's Vision framework for OCR.
    /// Extracts nutritional values like carbohydrates, fat, protein, calories, etc.
    /// Can optionally use a CoreML model for improved extraction.
    final class NutritionLabelScanner {
        // MARK: - Types

        /// Represents extracted nutrition data from a label
        struct NutritionData: Equatable {
            var calories: Double?
            var carbohydrates: Double?
            var sugars: Double?
            var fat: Double?
            var saturatedFat: Double?
            var protein: Double?
            var fiber: Double?
            var sodium: Double?
            var servingSize: String?
            var servingSizeGrams: Double?

            var hasAnyData: Bool {
                calories != nil || carbohydrates != nil || fat != nil || protein != nil
            }
        }

        /// A recognized text element with its bounding box
        struct TextElement {
            let text: String
            let boundingBox: CGRect
            let confidence: Float
        }

        /// Token with bounding box for model input
        struct TokenWithBox {
            let text: String
            let box: [Float] // [x0, y0, x1, y1] normalized coordinates
        }

        // MARK: - Public Methods

        /// Performs OCR on an image and extracts nutrition information using regex patterns
        /// - Parameter image: The image containing a nutrition label
        /// - Returns: Extracted nutrition data
        func scanNutritionLabel(from image: UIImage) async throws -> NutritionData {
            let textElements = try await performOCR(on: image)
            return parseNutritionData(from: textElements)
        }

        /// Scans nutrition label using the AI model for improved extraction
        /// - Parameters:
        ///   - image: The image containing a nutrition label
        ///   - modelManager: The model manager with a loaded CoreML model
        /// - Returns: Extracted nutrition data
        func scanWithAIModel(from image: UIImage, modelManager: NutritionModelManager) async throws -> NutritionData {
            print("🔍 [NutritionScanner] Starting AI-based nutrition scan...")
            print("🔍 [NutritionScanner] Image size: \(image.size)")

            // First perform OCR to get text and bounding boxes
            let textElements = try await performOCR(on: image)
            print("📝 [NutritionScanner] OCR found \(textElements.count) text elements")

            guard !textElements.isEmpty else {
                print("❌ [NutritionScanner] No text found in image")
                throw NutritionScannerError.noTextFound
            }

            // Log some OCR results
            for (index, element) in textElements.prefix(10).enumerated() {
                print("  📝 [\(index)]: '\(element.text)' at \(element.boundingBox)")
            }
            if textElements.count > 10 {
                print("  ... and \(textElements.count - 10) more")
            }

            // Prepare inputs for the model
            let (tokens, boxes) = prepareModelInputs(image: image, observations: textElements)
            print("🔢 [NutritionScanner] Prepared \(tokens.count) tokens with boxes")

            // If model is ready, use it for extraction
            if modelManager.isReady {
                print("🤖 [NutritionScanner] Model is ready, running inference...")
                do {
                    let aiData = try await runModelInference(
                        tokens: tokens,
                        boxes: boxes,
                        image: image,
                        modelManager: modelManager
                    )

                    print("📊 [NutritionScanner] AI extraction result - hasData: \(aiData.hasAnyData)")
                    if aiData.hasAnyData {
                        print("✅ [NutritionScanner] Using AI extraction result")
                        print("  Calories: \(String(describing: aiData.calories))")
                        print("  Carbs: \(String(describing: aiData.carbohydrates))")
                        print("  Protein: \(String(describing: aiData.protein))")
                        print("  Fat: \(String(describing: aiData.fat))")
                        return aiData
                    } else {
                        print("⚠️ [NutritionScanner] AI extraction found no data, falling back to regex")
                    }
                } catch {
                    print("❌ [NutritionScanner] AI model inference failed: \(error.localizedDescription)")
                    print("⚠️ [NutritionScanner] Falling back to regex-based extraction")
                }
            } else {
                print("⚠️ [NutritionScanner] Model not ready, using regex-based extraction")
            }

            // Fall back to regex-based extraction
            print("🔄 [NutritionScanner] Using regex-based extraction")
            print("📝 [NutritionScanner] All OCR text:")
            for element in textElements {
                print("  '\(element.text)'")
            }
            let regexData = parseNutritionData(from: textElements)
            print("📊 [NutritionScanner] Regex extraction result - hasData: \(regexData.hasAnyData)")
            return regexData
        }

        // MARK: - Model Input Preparation

        private func prepareModelInputs(image: UIImage, observations: [TextElement]) -> (tokens: [String], boxes: [[Float]]) {
            var tokens: [String] = []
            var boxes: [[Float]] = []

            let imageWidth = Float(image.size.width)
            let imageHeight = Float(image.size.height)

            for observation in observations {
                tokens.append(observation.text)

                // Convert Vision's normalized coordinates (bottom-left origin) to model format
                let box = observation.boundingBox
                let x0 = Float(box.minX) * imageWidth
                let y0 = Float(1 - box.maxY) * imageHeight // Vision uses bottom-left origin
                let x1 = Float(box.maxX) * imageWidth
                let y1 = Float(1 - box.minY) * imageHeight

                // Normalize to 0-1000 range as typically expected by LayoutLM models
                let normalizedBox: [Float] = [
                    (x0 / imageWidth) * 1000,
                    (y0 / imageHeight) * 1000,
                    (x1 / imageWidth) * 1000,
                    (y1 / imageHeight) * 1000
                ]

                boxes.append(normalizedBox)
            }

            return (tokens, boxes)
        }

        // MARK: - Model Inference

        private func runModelInference(
            tokens: [String],
            boxes: [[Float]],
            image: UIImage,
            modelManager: NutritionModelManager
        ) async throws -> NutritionData {
            print("🔮 [NutritionScanner] Starting model inference...")
            print("🔮 [NutritionScanner] Tokens count: \(tokens.count)")
            print("🔮 [NutritionScanner] Boxes count: \(boxes.count)")

            guard let model = modelManager.loadedModel else {
                print("❌ [NutritionScanner] Model not loaded")
                throw NutritionScannerError.parsingFailed
            }

            do {
                guard let cgImage = image.cgImage else {
                    print("❌ [NutritionScanner] Failed to get CGImage")
                    throw NutritionScannerError.invalidImage
                }

                print("📐 [NutritionScanner] Image size: \(image.size.width) x \(image.size.height)")

                // Get model input description
                let inputDescription = model.modelDescription.inputDescriptionsByName
                print("📋 [NutritionScanner] Model expects inputs: \(inputDescription.keys.joined(separator: ", "))")

                var featureDict: [String: MLFeatureValue] = [:]

                // Constants for LayoutLMv3
                let maxSeqLength = 512
                let imageSize = 224

                // 1. Prepare pixel_values (1 × 3 × 224 × 224)
                if inputDescription["pixel_values"] != nil {
                    print("🖼️ [NutritionScanner] Preparing pixel_values...")
                    let pixelArray = try preparePixelValues(from: cgImage, targetSize: imageSize)
                    featureDict["pixel_values"] = MLFeatureValue(multiArray: pixelArray)
                    print("✅ [NutritionScanner] pixel_values prepared, shape: \(pixelArray.shape)")
                }

                // 2. Prepare input_ids (1 × 512) - simple tokenization
                if inputDescription["input_ids"] != nil {
                    print("🔢 [NutritionScanner] Preparing input_ids...")
                    let inputIds = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLength)], dataType: .int32)

                    // Fill with padding token (0) first
                    for i in 0 ..< maxSeqLength {
                        inputIds[[0, i] as [NSNumber]] = 0
                    }

                    // Set CLS token at position 0
                    inputIds[[0, 0] as [NSNumber]] = 101 // [CLS] token

                    // Set simple token IDs for each word (this is a simplification)
                    let tokensToUse = min(tokens.count, maxSeqLength - 2)
                    for i in 0 ..< tokensToUse {
                        inputIds[[0, NSNumber(value: i + 1)] as [NSNumber]] = NSNumber(value: 1000 + i) // Placeholder IDs
                    }

                    // Set SEP token at end
                    inputIds[[0, NSNumber(value: tokensToUse + 1)] as [NSNumber]] = 102 // [SEP] token

                    featureDict["input_ids"] = MLFeatureValue(multiArray: inputIds)
                    print("✅ [NutritionScanner] input_ids prepared")
                }

                // 3. Prepare attention_mask (1 × 512)
                if inputDescription["attention_mask"] != nil {
                    print("🎭 [NutritionScanner] Preparing attention_mask...")
                    let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLength)], dataType: .int32)

                    // Set attention for actual tokens
                    let tokensToUse = min(tokens.count, maxSeqLength - 2)
                    for i in 0 ..< maxSeqLength {
                        // 1 for real tokens (CLS + tokens + SEP), 0 for padding
                        attentionMask[[0, i] as [NSNumber]] = i <= tokensToUse + 1 ? 1 : 0
                    }

                    featureDict["attention_mask"] = MLFeatureValue(multiArray: attentionMask)
                    print("✅ [NutritionScanner] attention_mask prepared")
                }

                // 4. Prepare bbox (1 × 512 × 4)
                if inputDescription["bbox"] != nil {
                    print("📦 [NutritionScanner] Preparing bbox...")
                    let bboxArray = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLength), 4], dataType: .int32)

                    // Initialize all to 0
                    for i in 0 ..< maxSeqLength {
                        for j in 0 ..< 4 {
                            bboxArray[[0, i, j] as [NSNumber]] = 0
                        }
                    }

                    // Fill with actual bounding boxes
                    let boxesToUse = min(boxes.count, maxSeqLength - 2)
                    for i in 0 ..< boxesToUse {
                        let box = boxes[i]
                        // Ensure values are within 0-1000 range
                        bboxArray[[0, NSNumber(value: i + 1), 0] as [NSNumber]] =
                            NSNumber(value: Int32(max(0, min(1000, box[0]))))
                        bboxArray[[0, NSNumber(value: i + 1), 1] as [NSNumber]] =
                            NSNumber(value: Int32(max(0, min(1000, box[1]))))
                        bboxArray[[0, NSNumber(value: i + 1), 2] as [NSNumber]] =
                            NSNumber(value: Int32(max(0, min(1000, box[2]))))
                        bboxArray[[0, NSNumber(value: i + 1), 3] as [NSNumber]] =
                            NSNumber(value: Int32(max(0, min(1000, box[3]))))
                    }

                    featureDict["bbox"] = MLFeatureValue(multiArray: bboxArray)
                    print("✅ [NutritionScanner] bbox prepared")
                }

                print("📊 [NutritionScanner] Total features prepared: \(featureDict.count)")

                // Check if all required inputs are prepared
                for (inputName, _) in inputDescription {
                    if featureDict[inputName] == nil {
                        print("⚠️ [NutritionScanner] Missing input: \(inputName)")
                    }
                }

                // Create feature provider
                let featureProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)
                print("🚀 [NutritionScanner] Running prediction...")

                // Run prediction
                let output = try await modelManager.predict(with: featureProvider)
                print("✅ [NutritionScanner] Prediction completed")

                // Parse model output
                return parseModelOutput(output, tokens: tokens)

            } catch {
                print("❌ [NutritionScanner] Model inference error: \(error)")
                print("❌ [NutritionScanner] Error details: \(String(describing: error))")
                throw NutritionScannerError.parsingFailed
            }
        }

        /// Prepares pixel values for LayoutLMv3 model
        private func preparePixelValues(from cgImage: CGImage, targetSize: Int) throws -> MLMultiArray {
            // Create a resized image
            let context = CGContext(
                data: nil,
                width: targetSize,
                height: targetSize,
                bitsPerComponent: 8,
                bytesPerRow: targetSize * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )

            guard let ctx = context else {
                throw NutritionScannerError.invalidImage
            }

            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

            guard let resizedImage = ctx.makeImage(),
                  let dataProvider = resizedImage.dataProvider,
                  let pixelData = dataProvider.data
            else {
                throw NutritionScannerError.invalidImage
            }

            let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)

            // Create MLMultiArray with shape [1, 3, 224, 224]
            let pixelArray = try MLMultiArray(
                shape: [1, 3, NSNumber(value: targetSize), NSNumber(value: targetSize)],
                dataType: .float32
            )

            // ImageNet normalization values
            let mean: [Float] = [0.485, 0.456, 0.406]
            let std: [Float] = [0.229, 0.224, 0.225]

            // Fill array with normalized pixel values (RGB channels)
            for y in 0 ..< targetSize {
                for x in 0 ..< targetSize {
                    let pixelIndex = (y * targetSize + x) * 4

                    // RGBA format
                    let r = Float(data[pixelIndex]) / 255.0
                    let g = Float(data[pixelIndex + 1]) / 255.0
                    let b = Float(data[pixelIndex + 2]) / 255.0

                    // Normalize with ImageNet stats
                    pixelArray[[0, 0, y, x] as [NSNumber]] = NSNumber(value: (r - mean[0]) / std[0])
                    pixelArray[[0, 1, y, x] as [NSNumber]] = NSNumber(value: (g - mean[1]) / std[1])
                    pixelArray[[0, 2, y, x] as [NSNumber]] = NSNumber(value: (b - mean[2]) / std[2])
                }
            }

            return pixelArray
        }

        private func parseModelOutput(_ output: MLFeatureProvider, tokens: [String]) -> NutritionData {
            var data = NutritionData()

            print("📊 [NutritionScanner] Parsing model output...")
            print("📊 [NutritionScanner] Available output features: \(output.featureNames)")
            print("📊 [NutritionScanner] Number of tokens: \(tokens.count)")

            let outputNames = output.featureNames

            for outputName in outputNames {
                guard let featureValue = output.featureValue(for: outputName) else {
                    print("⚠️ [NutritionScanner] No feature value for: \(outputName)")
                    continue
                }

                print("📊 [NutritionScanner] Processing output '\(outputName)', type: \(featureValue.type.rawValue)")

                // Handle different output types
                if let multiArray = featureValue.multiArrayValue {
                    print("📊 [NutritionScanner] MultiArray shape: \(multiArray.shape)")
                    // Model outputs predictions as multi-array (e.g., class logits per token)
                    data = parseMultiArrayOutput(multiArray, tokens: tokens)
                } else if featureValue.type == .dictionary {
                    print("📊 [NutritionScanner] Dictionary output detected")
                    // Model outputs as dictionary with nutrient names/values
                    let dict = featureValue.dictionaryValue
                    data = parseDictionaryOutput(dict)
                } else {
                    print("⚠️ [NutritionScanner] Unknown output type: \(featureValue.type)")
                }
            }

            print("📊 [NutritionScanner] Parsed data: calories=\(data.calories ?? -1), carbs=\(data.carbohydrates ?? -1)")
            return data
        }

        private func parseMultiArrayOutput(_ multiArray: MLMultiArray, tokens: [String]) -> NutritionData {
            var data = NutritionData()

            // LayoutLMv3 nutrition-extractor label indices
            // Based on openfoodfacts/nutrition-extractor model
            // These are BIO tags: B-label (begin), I-label (inside)
            let labelMap: [Int: String] = [
                0: "O", // Outside (not a nutrition entity)
                1: "B-energy-kcal_100g",
                2: "I-energy-kcal_100g",
                3: "B-fat_100g",
                4: "I-fat_100g",
                5: "B-saturated-fat_100g",
                6: "I-saturated-fat_100g",
                7: "B-carbohydrates_100g",
                8: "I-carbohydrates_100g",
                9: "B-sugars_100g",
                10: "I-sugars_100g",
                11: "B-fiber_100g",
                12: "I-fiber_100g",
                13: "B-proteins_100g",
                14: "I-proteins_100g",
                15: "B-salt_100g",
                16: "I-salt_100g",
                17: "B-sodium_100g",
                18: "I-sodium_100g"
                // Additional labels may exist up to 71 classes
            ]

            // Parse predictions - shape is [1, 512, 71] (batch, tokens, classes)
            let shape = multiArray.shape.map(\.intValue)
            print("📊 [NutritionScanner] MultiArray shape: \(shape)")

            guard shape.count >= 2 else {
                print("⚠️ [NutritionScanner] Unexpected shape dimensions: \(shape.count)")
                return data
            }

            // Handle both [tokens, classes] and [1, tokens, classes] shapes
            let numTokens: Int
            let numClasses: Int
            let batchOffset: Int

            if shape.count == 3 {
                // Shape [1, 512, 71]
                numTokens = shape[1]
                numClasses = shape[2]
                batchOffset = 0
                print("📊 [NutritionScanner] 3D shape: batch=\(shape[0]), tokens=\(numTokens), classes=\(numClasses)")
            } else {
                // Shape [512, 71]
                numTokens = shape[0]
                numClasses = shape[1]
                batchOffset = 0
                print("📊 [NutritionScanner] 2D shape: tokens=\(numTokens), classes=\(numClasses)")
            }

            let tokensToProcess = min(numTokens, tokens.count)
            print("📊 [NutritionScanner] Processing \(tokensToProcess) tokens")

            var extractedValues: [String: (String, Float)] = [:] // label -> (value_text, confidence)
            var currentEntity: String?
            var currentValue: String = ""

            for i in 0 ..< tokensToProcess {
                var maxLogit: Float = -Float.infinity
                var maxClass = 0

                // Find the class with highest logit
                for j in 0 ..< numClasses {
                    let index: [NSNumber]
                    if shape.count == 3 {
                        index = [0, NSNumber(value: i), NSNumber(value: j)]
                    } else {
                        index = [NSNumber(value: i), NSNumber(value: j)]
                    }
                    let logit = multiArray[index].floatValue
                    if logit > maxLogit {
                        maxLogit = logit
                        maxClass = j
                    }
                }

                // Apply softmax to get probability
                let expSum: Float = {
                    var sum: Float = 0
                    for j in 0 ..< numClasses {
                        let index: [NSNumber]
                        if shape.count == 3 {
                            index = [0, NSNumber(value: i), NSNumber(value: j)]
                        } else {
                            index = [NSNumber(value: i), NSNumber(value: j)]
                        }
                        sum += exp(multiArray[index].floatValue - maxLogit)
                    }
                    return sum
                }()
                let maxProb = 1.0 / expSum

                let label = labelMap[maxClass] ?? "unknown-\(maxClass)"
                let tokenText = tokens[i]

                // Log first few predictions
                if i < 10 || maxClass != 0 {
                    print(
                        "📊 [NutritionScanner] Token \(i): '\(tokenText)' -> class \(maxClass) (\(label)) prob=\(String(format: "%.3f", maxProb))"
                    )
                }

                // Handle BIO tagging
                if label.hasPrefix("B-") {
                    // Begin new entity - save previous if exists
                    if let entity = currentEntity, !currentValue.isEmpty {
                        let entityName = String(entity.dropFirst(2)) // Remove "B-" prefix
                        extractedValues[entityName] = (currentValue.trimmingCharacters(in: .whitespaces), maxProb)
                        print("✅ [NutritionScanner] Extracted: \(entityName) = \(currentValue)")
                    }
                    currentEntity = label
                    currentValue = tokenText
                } else if label.hasPrefix("I-"), let entity = currentEntity {
                    // Continue current entity
                    let expectedPrefix = "I-" + String(entity.dropFirst(2))
                    if label == expectedPrefix {
                        currentValue += " " + tokenText
                    }
                } else if maxClass == 0 {
                    // Outside token - save current entity if exists
                    if let entity = currentEntity, !currentValue.isEmpty {
                        let entityName = String(entity.dropFirst(2))
                        extractedValues[entityName] = (currentValue.trimmingCharacters(in: .whitespaces), maxProb)
                        print("✅ [NutritionScanner] Extracted: \(entityName) = \(currentValue)")
                    }
                    currentEntity = nil
                    currentValue = ""
                }
            }

            // Don't forget last entity
            if let entity = currentEntity, !currentValue.isEmpty {
                let entityName = String(entity.dropFirst(2))
                extractedValues[entityName] = (currentValue.trimmingCharacters(in: .whitespaces), 1.0)
                print("✅ [NutritionScanner] Extracted (final): \(entityName) = \(currentValue)")
            }

            print("📊 [NutritionScanner] Total extracted values: \(extractedValues.count)")
            for (key, value) in extractedValues {
                print("📊 [NutritionScanner]   - \(key): \(value.0)")
            }

            // Map extracted values to NutritionData
            for (label, (valueStr, _)) in extractedValues {
                // Extract numeric value from the string
                let numericValue = extractNumericValue(from: valueStr)

                switch label {
                case "energy-kcal_100g":
                    data.calories = numericValue
                case "carbohydrates_100g":
                    data.carbohydrates = numericValue
                case "sugars_100g":
                    data.sugars = numericValue
                case "fat_100g":
                    data.fat = numericValue
                case "saturated-fat_100g":
                    data.saturatedFat = numericValue
                case "proteins_100g":
                    data.protein = numericValue
                case "fiber_100g":
                    data.fiber = numericValue
                case "salt_100g",
                     "sodium_100g":
                    data.sodium = numericValue
                default:
                    print("⚠️ [NutritionScanner] Unknown label: \(label)")
                }
            }

            return data
        }

        private func parseDictionaryOutput(_ dict: [AnyHashable: NSNumber]) -> NutritionData {
            var data = NutritionData()

            for (key, value) in dict {
                guard let keyStr = key as? String else { continue }
                let doubleValue = value.doubleValue

                let lowercaseKey = keyStr.lowercased()
                if lowercaseKey.contains("calorie") || lowercaseKey.contains("energy") {
                    data.calories = doubleValue
                } else if lowercaseKey.contains("carb") {
                    data.carbohydrates = doubleValue
                } else if lowercaseKey.contains("sugar") {
                    data.sugars = doubleValue
                } else if lowercaseKey.contains("saturated") {
                    data.saturatedFat = doubleValue
                } else if lowercaseKey.contains("fat") {
                    data.fat = doubleValue
                } else if lowercaseKey.contains("protein") {
                    data.protein = doubleValue
                } else if lowercaseKey.contains("fiber") || lowercaseKey.contains("fibre") {
                    data.fiber = doubleValue
                } else if lowercaseKey.contains("sodium") || lowercaseKey.contains("salt") {
                    data.sodium = doubleValue
                }
            }

            return data
        }

        private func extractNumericValue(from text: String) -> Double? {
            let pattern = "([\\d]+[.,]?[\\d]*)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let matchRange = Range(match.range(at: 1), in: text) else { return nil }

            let numberStr = String(text[matchRange]).replacingOccurrences(of: ",", with: ".")
            return Double(numberStr)
        }

        // MARK: - OCR

        /// Performs OCR using Vision framework
        private func performOCR(on image: UIImage) async throws -> [TextElement] {
            guard let cgImage = image.cgImage else {
                throw NutritionScannerError.invalidImage
            }

            return try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: [])
                        return
                    }

                    let elements = observations.compactMap { observation -> TextElement? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return TextElement(
                            text: candidate.string,
                            boundingBox: observation.boundingBox,
                            confidence: candidate.confidence
                        )
                    }

                    continuation.resume(returning: elements)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "es-ES", "it-IT"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // MARK: - Parsing

        /// Parses nutrition data from OCR text elements
        private func parseNutritionData(from elements: [TextElement]) -> NutritionData {
            // Combine all text for easier pattern matching
            let allText = elements.map(\.text).joined(separator: "\n")
            let lines = allText.components(separatedBy: .newlines)

            // Also create a combined text with spaces for patterns that span multiple OCR elements
            let combinedText = elements.map(\.text).joined(separator: " ")

            // Sort elements by vertical position (top to bottom) for table-like parsing
            let sortedElements = elements.sorted { $0.boundingBox.minY > $1.boundingBox.minY }

            var data = NutritionData()

            // Parse serving size
            data.servingSize = extractServingSize(from: lines)
            data.servingSizeGrams = extractServingSizeGrams(from: lines)

            // First try standard line-based extraction
            data.calories = extractValue(for: NutrientPatterns.calories, from: lines)
            data.carbohydrates = extractValue(for: NutrientPatterns.carbohydrates, from: lines)
            data.sugars = extractValue(for: NutrientPatterns.sugars, from: lines)
            data.fat = extractValue(for: NutrientPatterns.fat, from: lines)
            data.saturatedFat = extractValue(for: NutrientPatterns.saturatedFat, from: lines)
            data.protein = extractValue(for: NutrientPatterns.protein, from: lines)
            data.fiber = extractValue(for: NutrientPatterns.fiber, from: lines)
            data.sodium = extractValue(for: NutrientPatterns.sodium, from: lines)

            // If standard extraction failed for key nutrients, try table-based extraction
            if data.carbohydrates == nil || data.protein == nil || data.fat == nil {
                print("🔄 [NutritionScanner] Trying table-based extraction...")
                let tableData = extractFromTableFormat(elements: sortedElements, combinedText: combinedText)

                // Fill in missing values
                if data.calories == nil { data.calories = tableData.calories }
                if data.carbohydrates == nil { data.carbohydrates = tableData.carbohydrates }
                if data.sugars == nil { data.sugars = tableData.sugars }
                if data.fat == nil { data.fat = tableData.fat }
                if data.saturatedFat == nil { data.saturatedFat = tableData.saturatedFat }
                if data.protein == nil { data.protein = tableData.protein }
                if data.fiber == nil { data.fiber = tableData.fiber }
                if data.sodium == nil { data.sodium = tableData.sodium }
            }

            print(
                "📊 [NutritionScanner] Final extraction: calories=\(String(describing: data.calories)), carbs=\(String(describing: data.carbohydrates)), protein=\(String(describing: data.protein)), fat=\(String(describing: data.fat))"
            )

            return data
        }

        /// Extracts nutrition values from table format where label and value may be separate OCR elements
        private func extractFromTableFormat(elements: [TextElement], combinedText: String) -> NutritionData {
            var data = NutritionData()

            // German nutrition label keywords and their variations
            let nutrientKeywords: [(keywords: [String], setter: (Double) -> Void)] = [
                (["kohlenhydrate", "carbohydrate", "carbs", "glucide"], { data.carbohydrates = $0 }),
                (["davon zucker", "zucker", "sugar", "sucre", "zuccheri"], { data.sugars = $0 }),
                (["eiweiß", "eiweiss", "protein", "proteine", "protéine"], { data.protein = $0 }),
                (["fett", "fat", "lipide", "grassi", "matières grasses"], { data.fat = $0 }),
                (["gesättigte", "saturated", "saturi"], { data.saturatedFat = $0 }),
                (["ballaststoffe", "fiber", "fibre"], { data.fiber = $0 }),
                (["salz", "salt", "sel", "sodium", "natrium"], { data.sodium = $0 }),
                (["energie", "energy", "brennwert", "kcal", "kj"], { data.calories = $0 })
            ]

            // Method 1: Look for value patterns in combined text near keywords
            for (keywords, setter) in nutrientKeywords {
                for keyword in keywords {
                    // Pattern: keyword followed by a number with optional unit
                    let patterns = [
                        "\(keyword)[^\\d]*(\\d+[,.]?\\d*)\\s*(?:g|mg|kcal|kj)?",
                        "\(keyword)\\s+(\\d+[,.]?\\d*)\\s*(?:g|mg|kcal|kj)?"
                    ]

                    for pattern in patterns {
                        if let value = extractNumber(matching: pattern, in: combinedText.lowercased()) {
                            print("  ✅ Found \(keyword): \(value)")
                            setter(value)
                            break
                        }
                    }
                }
            }

            // Method 2: Group elements by vertical position (same row)
            let rowTolerance: CGFloat = 0.02 // Elements within 2% vertical distance are considered same row

            var rows: [[TextElement]] = []
            var currentRow: [TextElement] = []
            var lastY: CGFloat = -1

            for element in elements {
                let y = element.boundingBox.midY
                if lastY < 0 || abs(y - lastY) < rowTolerance {
                    currentRow.append(element)
                } else {
                    if !currentRow.isEmpty {
                        rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
                    }
                    currentRow = [element]
                }
                lastY = y
            }
            if !currentRow.isEmpty {
                rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
            }

            // Process each row
            for row in rows {
                let rowText = row.map(\.text).joined(separator: " ").lowercased()

                for (keywords, setter) in nutrientKeywords {
                    for keyword in keywords {
                        if rowText.contains(keyword) {
                            // Find numeric value in this row
                            if let value = findNumericValue(in: rowText, excludeUnits: ["kj", "nrv", "%"]) {
                                print("  ✅ Row match for \(keyword): \(value)")
                                setter(value)
                                break
                            }
                        }
                    }
                }
            }

            return data
        }

        /// Finds a numeric value in text, optionally excluding certain unit contexts
        private func findNumericValue(in text: String, excludeUnits: [String] = []) -> Double? {
            // Pattern for numbers with optional decimal (both . and ,)
            let pattern = "(\\d+[,.]?\\d*)\\s*(?:g|mg|kcal)?(?!\\s*(?:kj|nrv|%))"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let matchedText = String(text[matchRange])

                // Skip if it's followed by excluded units
                var shouldSkip = false
                for unit in excludeUnits {
                    if matchedText.lowercased().contains(unit) {
                        shouldSkip = true
                        break
                    }
                }

                if !shouldSkip {
                    // Extract just the number
                    let numberPattern = "(\\d+[,.]?\\d*)"
                    if let numRegex = try? NSRegularExpression(pattern: numberPattern, options: []),
                       let numMatch = numRegex.firstMatch(
                           in: matchedText,
                           options: [],
                           range: NSRange(matchedText.startIndex..., in: matchedText)
                       ),
                       let numRange = Range(numMatch.range(at: 1), in: matchedText)
                    {
                        let numStr = String(matchedText[numRange]).replacingOccurrences(of: ",", with: ".")
                        if let value = Double(numStr), value > 0 {
                            return value
                        }
                    }
                }
            }

            return nil
        }

        /// Extracts serving size text
        private func extractServingSize(from lines: [String]) -> String? {
            let patterns = [
                "serving size[:\\s]*(.+)",
                "portion[:\\s]*(.+)",
                "portionsgröße[:\\s]*(.+)",
                "porzione[:\\s]*(.+)"
            ]

            for line in lines {
                let lowercased = line.lowercased()
                for pattern in patterns {
                    if let match = lowercased.range(of: pattern, options: .regularExpression) {
                        let result = String(line[match])
                        // Extract the value part after the colon or label
                        if let colonIndex = result.firstIndex(of: ":") {
                            return String(result[result.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                        }
                        return result
                    }
                }
            }
            return nil
        }

        /// Extracts serving size in grams
        private func extractServingSizeGrams(from lines: [String]) -> Double? {
            let pattern = "(\\d+(?:[.,]\\d+)?)\\s*(?:g|grams?|gramm)"

            for line in lines {
                let lowercased = line.lowercased()
                if lowercased.contains("serving") || lowercased.contains("portion") {
                    if let value = extractNumber(matching: pattern, in: line) {
                        return value
                    }
                }
            }
            return nil
        }

        /// Extracts a nutrient value using regex patterns
        private func extractValue(for patterns: [String], from lines: [String]) -> Double? {
            for line in lines {
                for pattern in patterns {
                    if let value = extractNumber(matching: pattern, in: line) {
                        return value
                    }
                }
            }
            return nil
        }

        /// Extracts a number from text using a regex pattern
        private func extractNumber(matching pattern: String, in text: String) -> Double? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }

            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                return nil
            }

            // Look for a number in the match
            let matchedString = String(text[Range(match.range, in: text)!])
            let numberPattern = "(\\d+(?:[.,]\\d+)?)"

            guard let numberRegex = try? NSRegularExpression(pattern: numberPattern, options: []) else {
                return nil
            }

            let numberRange = NSRange(matchedString.startIndex..., in: matchedString)
            guard let numberMatch = numberRegex.firstMatch(in: matchedString, options: [], range: numberRange),
                  let numberRange = Range(numberMatch.range(at: 1), in: matchedString)
            else {
                return nil
            }

            let numberString = String(matchedString[numberRange])
                .replacingOccurrences(of: ",", with: ".")

            return Double(numberString)
        }
    }
}

// MARK: - Nutrient Patterns

private enum NutrientPatterns {
    static let calories: [String] = [
        "calories?[:\\s]*(\\d+(?:[.,]\\d+)?)",
        "energy[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|cal)",
        "kcal[:\\s]*(\\d+(?:[.,]\\d+)?)",
        "brennwert[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kj)",
        "energie[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kj)",
        "(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|cal)\\b"
    ]

    static let carbohydrates: [String] = [
        "(?:total\\s+)?carbohydrates?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "carbs?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "kohlenhydrate[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "glucides?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "carboidrati[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let sugars: [String] = [
        "(?:total\\s+)?sugars?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "zucker[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "sucres?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "zuccheri[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "davon\\s+zucker[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let fat: [String] = [
        "(?:total\\s+)?fat[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fett[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "lipides?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "grassi[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "matières\\s+grasses[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let saturatedFat: [String] = [
        "saturated\\s+fat[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "gesättigte\\s+(?:fett)?säuren?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "acides\\s+gras\\s+saturés[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "grassi\\s+saturi[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let protein: [String] = [
        "proteins?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "eiweiß[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "protéines?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "proteine[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let fiber: [String] = [
        "(?:dietary\\s+)?fiber[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fibre[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "ballaststoffe[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fibres?\\s+alimentaires?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let sodium: [String] = [
        "sodium[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "natrium[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "salt[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "salz[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "sel[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?"
    ]
}

// MARK: - Errors

extension BarcodeScanner {
    enum NutritionScannerError: LocalizedError {
        case invalidImage
        case noTextFound
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return String(localized: "The image could not be processed.")
            case .noTextFound:
                return String(localized: "No text was found in the image.")
            case .parsingFailed:
                return String(localized: "Could not extract nutrition information from the image.")
            }
        }
    }
}

// MARK: - Extension to convert NutritionData to ScannedProductItem

extension BarcodeScanner.NutritionLabelScanner.NutritionData {
    /// Converts scanned nutrition data to an OpenFoodFactsProduct for consistency
    func toProduct(name: String = "Scanned Label") -> BarcodeScanner.OpenFoodFactsProduct {
        BarcodeScanner.OpenFoodFactsProduct(
            barcode: "manual-\(UUID().uuidString)",
            name: name,
            brand: nil,
            quantity: servingSize,
            servingSize: servingSize,
            ingredients: nil,
            imageURL: nil,
            defaultPortionIsMl: false,
            servingQuantity: servingSizeGrams,
            servingQuantityUnit: "g",
            nutriments: .init(
                basis: .per100g,
                energyKcalPer100g: calories,
                carbohydratesPer100g: carbohydrates,
                sugarsPer100g: sugars,
                fatPer100g: fat,
                proteinPer100g: protein,
                fiberPer100g: fiber
            )
        )
    }
}
