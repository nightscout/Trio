import CoreML
import Foundation
import UIKit
import Vision

// MARK: - Nutrition Label Scanner

extension BarcodeScanner {
    /// Scans nutrition labels from images using Apple's Vision framework for OCR
    final class NutritionLabelScanner {
        // MARK: - Types

        /// A recognized text element with its bounding box
        struct TextElement {
            let text: String
            let boundingBox: CGRect
            let confidence: Float
        }

        // MARK: - Public Methods

        /// Performs OCR on an image and extracts nutrition information using regex patterns
        func scanNutritionLabel(from image: UIImage) async throws -> NutritionData {
            let textElements = try await performOCR(on: image)
            return parseNutritionData(from: textElements)
        }

        /// Scans nutrition label using the AI model for improved extraction
        func scanWithAIModel(from image: UIImage, modelManager: NutritionModelManager) async throws -> NutritionData {
            let textElements = try await performOCR(on: image)

            guard !textElements.isEmpty else {
                throw NutritionScannerError.noTextFound
            }

            let (tokens, boxes) = prepareModelInputs(image: image, observations: textElements)

            if modelManager.isReady {
                do {
                    let aiData = try await runModelInference(
                        tokens: tokens,
                        boxes: boxes,
                        image: image,
                        modelManager: modelManager
                    )

                    if aiData.hasAnyData {
                        return aiData
                    }
                } catch {
                    // Fall through to regex extraction
                }
            }

            return parseNutritionData(from: textElements)
        }

        // MARK: - OCR

        private func performOCR(on image: UIImage) async throws -> [TextElement] {
            guard let cgImage = image.cgImage else {
                throw NutritionScannerError.invalidImage
            }

            return try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
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

                    // Log recognized text
                    let fullText = elements.map(\.text).joined(separator: "\n")
                    print("----- Recognized Text Content START -----")
                    print(fullText)
                    print("----- Recognized Text Content END -----")

                    continuation.resume(returning: elements)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true

                // Use all supported languages for the current revision to mimic "Photos app" behavior
                do {
                    let allLanguages = try VNRecognizeTextRequest.supportedRecognitionLanguages(
                        for: .accurate,
                        revision: request.revision
                    )
                    request.recognitionLanguages = allLanguages
                } catch {
                    // Fallback to major languages if dynamic retrieval fails
                    request.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "es-ES", "it-IT", "zh-Hans", "ja-JP"]
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // MARK: - Model Input Preparation

        private func prepareModelInputs(
            image: UIImage,
            observations: [TextElement]
        ) -> (tokens: [String], boxes: [[Float]]) {
            var tokens: [String] = []
            var boxes: [[Float]] = []

            let imageWidth = Float(image.size.width)
            let imageHeight = Float(image.size.height)

            for observation in observations {
                tokens.append(observation.text)

                let box = observation.boundingBox
                let x0 = Float(box.minX) * imageWidth
                let y0 = Float(1 - box.maxY) * imageHeight
                let x1 = Float(box.maxX) * imageWidth
                let y1 = Float(1 - box.minY) * imageHeight

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
            guard let model = modelManager.loadedModel else {
                throw NutritionScannerError.parsingFailed
            }

            guard let cgImage = image.cgImage else {
                throw NutritionScannerError.invalidImage
            }

            let inputDescription = model.modelDescription.inputDescriptionsByName
            var featureDict: [String: MLFeatureValue] = [:]

            let maxSeqLength = 512
            let imageSize = 224

            // Prepare pixel_values
            if inputDescription["pixel_values"] != nil {
                let pixelArray = try preparePixelValues(from: cgImage, targetSize: imageSize)
                featureDict["pixel_values"] = MLFeatureValue(multiArray: pixelArray)
            }

            // Prepare input_ids
            if inputDescription["input_ids"] != nil {
                let inputIds = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLength)], dataType: .int32)

                for i in 0 ..< maxSeqLength {
                    inputIds[[0, i] as [NSNumber]] = 0
                }

                inputIds[[0, 0] as [NSNumber]] = 101 // [CLS]

                let tokensToUse = min(tokens.count, maxSeqLength - 2)
                for i in 0 ..< tokensToUse {
                    inputIds[[0, NSNumber(value: i + 1)] as [NSNumber]] = NSNumber(value: 1000 + i)
                }

                inputIds[[0, NSNumber(value: tokensToUse + 1)] as [NSNumber]] = 102 // [SEP]

                featureDict["input_ids"] = MLFeatureValue(multiArray: inputIds)
            }

            // Prepare attention_mask
            if inputDescription["attention_mask"] != nil {
                let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLength)], dataType: .int32)

                let tokensToUse = min(tokens.count, maxSeqLength - 2)
                for i in 0 ..< maxSeqLength {
                    attentionMask[[0, i] as [NSNumber]] = i <= tokensToUse + 1 ? 1 : 0
                }

                featureDict["attention_mask"] = MLFeatureValue(multiArray: attentionMask)
            }

            // Prepare bbox
            if inputDescription["bbox"] != nil {
                let bboxArray = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLength), 4], dataType: .int32)

                for i in 0 ..< maxSeqLength {
                    for j in 0 ..< 4 {
                        bboxArray[[0, i, j] as [NSNumber]] = 0
                    }
                }

                let boxesToUse = min(boxes.count, maxSeqLength - 2)
                for i in 0 ..< boxesToUse {
                    let box = boxes[i]
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
            }

            let featureProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let output = try await modelManager.predict(with: featureProvider)

            return parseModelOutput(output, tokens: tokens)
        }

        private func preparePixelValues(from cgImage: CGImage, targetSize: Int) throws -> MLMultiArray {
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

            let pixelArray = try MLMultiArray(
                shape: [1, 3, NSNumber(value: targetSize), NSNumber(value: targetSize)],
                dataType: .float32
            )

            let mean: [Float] = [0.485, 0.456, 0.406]
            let std: [Float] = [0.229, 0.224, 0.225]

            for y in 0 ..< targetSize {
                for x in 0 ..< targetSize {
                    let pixelIndex = (y * targetSize + x) * 4

                    let r = Float(data[pixelIndex]) / 255.0
                    let g = Float(data[pixelIndex + 1]) / 255.0
                    let b = Float(data[pixelIndex + 2]) / 255.0

                    pixelArray[[0, 0, y, x] as [NSNumber]] = NSNumber(value: (r - mean[0]) / std[0])
                    pixelArray[[0, 1, y, x] as [NSNumber]] = NSNumber(value: (g - mean[1]) / std[1])
                    pixelArray[[0, 2, y, x] as [NSNumber]] = NSNumber(value: (b - mean[2]) / std[2])
                }
            }

            return pixelArray
        }

        // MARK: - Output Parsing

        private func parseModelOutput(_ output: MLFeatureProvider, tokens: [String]) -> NutritionData {
            var data = NutritionData()

            for outputName in output.featureNames {
                guard let featureValue = output.featureValue(for: outputName) else { continue }

                if let multiArray = featureValue.multiArrayValue {
                    data = parseMultiArrayOutput(multiArray, tokens: tokens)
                } else if featureValue.type == .dictionary {
                    let dict = featureValue.dictionaryValue
                    data = parseDictionaryOutput(dict)
                }
            }

            return data
        }

        private func parseMultiArrayOutput(_ multiArray: MLMultiArray, tokens: [String]) -> NutritionData {
            var data = NutritionData()

            let labelMap: [Int: String] = [
                0: "O",
                1: "B-energy-kcal_100g", 2: "I-energy-kcal_100g",
                3: "B-fat_100g", 4: "I-fat_100g",
                5: "B-saturated-fat_100g", 6: "I-saturated-fat_100g",
                7: "B-carbohydrates_100g", 8: "I-carbohydrates_100g",
                9: "B-sugars_100g", 10: "I-sugars_100g",
                11: "B-fiber_100g", 12: "I-fiber_100g",
                13: "B-proteins_100g", 14: "I-proteins_100g",
                15: "B-salt_100g", 16: "I-salt_100g",
                17: "B-sodium_100g", 18: "I-sodium_100g"
            ]

            let shape = multiArray.shape.map(\.intValue)
            guard shape.count >= 2 else { return data }

            let numTokens: Int
            let numClasses: Int

            if shape.count == 3 {
                numTokens = shape[1]
                numClasses = shape[2]
            } else {
                numTokens = shape[0]
                numClasses = shape[1]
            }

            let tokensToProcess = min(numTokens, tokens.count)
            var extractedValues: [String: String] = [:]
            var currentEntity: String?
            var currentValue: String = ""

            for i in 0 ..< tokensToProcess {
                var maxLogit: Float = -Float.infinity
                var maxClass = 0

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

                let label = labelMap[maxClass] ?? "unknown"
                let tokenText = tokens[i]

                if label.hasPrefix("B-") {
                    if let entity = currentEntity, !currentValue.isEmpty {
                        let entityName = String(entity.dropFirst(2))
                        extractedValues[entityName] = currentValue.trimmingCharacters(in: .whitespaces)
                    }
                    currentEntity = label
                    currentValue = tokenText
                } else if label.hasPrefix("I-"), let entity = currentEntity {
                    let expectedPrefix = "I-" + String(entity.dropFirst(2))
                    if label == expectedPrefix {
                        currentValue += " " + tokenText
                    }
                } else if maxClass == 0 {
                    if let entity = currentEntity, !currentValue.isEmpty {
                        let entityName = String(entity.dropFirst(2))
                        extractedValues[entityName] = currentValue.trimmingCharacters(in: .whitespaces)
                    }
                    currentEntity = nil
                    currentValue = ""
                }
            }

            if let entity = currentEntity, !currentValue.isEmpty {
                let entityName = String(entity.dropFirst(2))
                extractedValues[entityName] = currentValue.trimmingCharacters(in: .whitespaces)
            }

            for (label, valueStr) in extractedValues {
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
                    break
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
                  let matchRange = Range(match.range(at: 1), in: text)
            else { return nil }

            let numberStr = String(text[matchRange]).replacingOccurrences(of: ",", with: ".")
            return Double(numberStr)
        }

        // MARK: - Regex-Based Parsing

        private func parseNutritionData(from elements: [TextElement]) -> NutritionData {
            let allText = elements.map(\.text).joined(separator: "\n")
            let lines = allText.components(separatedBy: .newlines)
            let combinedText = elements.map(\.text).joined(separator: " ")
            let sortedElements = elements.sorted { $0.boundingBox.minY > $1.boundingBox.minY }

            var data = NutritionData()

            data.servingSize = extractServingSize(from: lines)
            data.servingSizeGrams = extractServingSizeGrams(from: lines)

            data.calories = extractValue(for: NutrientPatterns.calories, from: lines)
            data.carbohydrates = extractValue(for: NutrientPatterns.carbohydrates, from: lines)
            data.sugars = extractValue(for: NutrientPatterns.sugars, from: lines)
            data.fat = extractValue(for: NutrientPatterns.fat, from: lines)
            data.saturatedFat = extractValue(for: NutrientPatterns.saturatedFat, from: lines)
            data.protein = extractValue(for: NutrientPatterns.protein, from: lines)
            data.fiber = extractValue(for: NutrientPatterns.fiber, from: lines)
            data.sodium = extractValue(for: NutrientPatterns.sodium, from: lines)

            if data.carbohydrates == nil || data.protein == nil || data.fat == nil {
                let tableData = extractFromTableFormat(elements: sortedElements, combinedText: combinedText)

                if data.calories == nil { data.calories = tableData.calories }
                if data.carbohydrates == nil { data.carbohydrates = tableData.carbohydrates }
                if data.sugars == nil { data.sugars = tableData.sugars }
                if data.fat == nil { data.fat = tableData.fat }
                if data.saturatedFat == nil { data.saturatedFat = tableData.saturatedFat }
                if data.protein == nil { data.protein = tableData.protein }
                if data.fiber == nil { data.fiber = tableData.fiber }
                if data.sodium == nil { data.sodium = tableData.sodium }
            }

            return data
        }

        private func extractFromTableFormat(elements: [TextElement], combinedText: String) -> NutritionData {
            var data = NutritionData()

            let nutrientKeywords: [(keywords: [String], setter: (Double) -> Void)] = [
                (
                    [
                        "kohlenhydrate",
                        "carbohydrate",
                        "carbs",
                        "glucide",
                        "carboidrati",
                        "hidratos de carbono",
                        "carboidratos",
                        "koolhydraten",
                        "углеводы",
                        "碳水化合物",
                        "炭水化物",
                        "karbonhidrat"
                    ],
                    { data.carbohydrates = $0 }
                ),
                (
                    [
                        "davon zucker",
                        "zucker",
                        "sugar",
                        "sucre",
                        "zuccheri",
                        "azúcares",
                        "açúcares",
                        "suikers",
                        "сахар",
                        "糖",
                        "糖類",
                        "şeker"
                    ],
                    { data.sugars = $0 }
                ),
                (
                    [
                        "eiweiß",
                        "eiweiss",
                        "protein",
                        "proteine",
                        "protéine",
                        "proteínas",
                        "eiwitten",
                        "белки",
                        "蛋白质",
                        "たんぱく質",
                        "タンパク質"
                    ],
                    { data.protein = $0 }
                ),
                (
                    [
                        "fett",
                        "fat",
                        "lipide",
                        "grassi",
                        "matières grasses",
                        "grasas",
                        "gorduras",
                        "vetten",
                        "vet",
                        "жиры",
                        "脂肪",
                        "脂質",
                        "yağ"
                    ],
                    { data.fat = $0 }
                ),
                (
                    ["gesättigte", "saturated", "saturi", "saturadas", "saturados", "verzadigd", "насыщенные", "饱和", "飽和"],
                    { data.saturatedFat = $0 }
                ),
                (
                    ["ballaststoffe", "fiber", "fibre", "fibra", "vezels", "волокна", "клетчатка", "膳食纤维", "食物繊維", "lif"],
                    { data.fiber = $0 }
                ),
                (
                    [
                        "salz",
                        "salt",
                        "sel",
                        "sodium",
                        "natrium",
                        "sal",
                        "sodio",
                        "sódio",
                        "zout",
                        "соль",
                        "натрий",
                        "钠",
                        "ナトリウム",
                        "食塩相当量",
                        "tuz"
                    ],
                    { data.sodium = $0 }
                ),
                (
                    [
                        "energie",
                        "energy",
                        "brennwert",
                        "kcal",
                        "kj",
                        "energía",
                        "energia",
                        "энергетическая ценность",
                        "калорийность",
                        "能量",
                        "热量",
                        "熱量",
                        "エネルギー"
                    ],
                    { data.calories = $0 }
                )
            ]

            for (keywords, setter) in nutrientKeywords {
                for keyword in keywords {
                    let patterns = [
                        "\(keyword)[^\\d]*(\\d+[,.]?\\d*)\\s*(?:g|mg|kcal|kj)?",
                        "\(keyword)\\s+(\\d+[,.]?\\d*)\\s*(?:g|mg|kcal|kj)?"
                    ]

                    for pattern in patterns {
                        if let value = extractNumber(matching: pattern, in: combinedText.lowercased()) {
                            setter(value)
                            break
                        }
                    }
                }
            }

            // Group elements by vertical position
            let rowTolerance: CGFloat = 0.02
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

            for row in rows {
                let rowText = row.map(\.text).joined(separator: " ").lowercased()

                for (keywords, setter) in nutrientKeywords {
                    for keyword in keywords {
                        if rowText.contains(keyword) {
                            if let value = findNumericValue(in: rowText) {
                                setter(value)
                                break
                            }
                        }
                    }
                }
            }

            return data
        }

        private func findNumericValue(in text: String) -> Double? {
            let pattern = "(\\d+[,.]?\\d*)\\s*(?:g|mg|kcal)?(?!\\s*(?:kj|nrv|%))"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let matchedText = String(text[matchRange])

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

            return nil
        }

        private func extractServingSize(from lines: [String]) -> String? {
            let patterns = [
                "serving size[:\\s]*(.+)",
                "portion[:\\s]*(.+)",
                "portionsgröße[:\\s]*(.+)",
                "porzione[:\\s]*(.+)",
                "tamaño por ración[:\\s]*(.+)",
                "tamanho da porção[:\\s]*(.+)",
                "portiegrootte[:\\s]*(.+)",
                "размер порции[:\\s]*(.+)",
                "食用份量[:\\s]*(.+)",
                "1食分[:\\s]*(.+)"
            ]

            for line in lines {
                let lowercased = line.lowercased()
                for pattern in patterns {
                    if let match = lowercased.range(of: pattern, options: .regularExpression) {
                        let result = String(line[match])
                        if let colonIndex = result.firstIndex(of: ":") {
                            return String(result[result.index(after: colonIndex)...])
                                .trimmingCharacters(in: .whitespaces)
                        }
                        return result
                    }
                }
            }
            return nil
        }

        private func extractServingSizeGrams(from lines: [String]) -> Double? {
            let pattern = "(\\d+(?:[.,]\\d+)?)\\s*(?:g|grams?|gramm|gramos|grammes|г|克)"

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

        private func extractNumber(matching pattern: String, in text: String) -> Double? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }

            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                return nil
            }

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
        "energía[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kj)",
        "energia[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kj)",
        "энергетическая ценность[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:ккал|кдж)?",
        "калорийность[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:ккал)?",
        "能量[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kJ|千焦)?",
        "热量[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kJ|千焦)?",
        "エネルギー[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kJ)?",
        "熱量[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|kJ)?",
        "(\\d+(?:[.,]\\d+)?)\\s*(?:kcal|cal)\\b"
    ]

    static let carbohydrates: [String] = [
        "(?:total\\s+)?carbohydrates?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "carbs?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "kohlenhydrate[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "glucides?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "carboidrati[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "hidratos de carbono[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "carboidratos[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "koolhydraten[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "углеводы[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*г?",
        "碳水化合物[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*克?",
        "炭水化物[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let sugars: [String] = [
        "(?:total\\s+)?sugars?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "zucker[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "sucres?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "zuccheri[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "davon\\s+zucker[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "azúcares[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "açúcares[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "suikers[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "сахар[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*г?",
        "糖[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*克?",
        "糖類[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let fat: [String] = [
        "(?:total\\s+)?fat[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fett[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "lipides?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "grassi[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "matières\\s+grasses[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "grasas?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "gorduras?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "vetten[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "жиры[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*г?",
        "脂肪[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*克?",
        "脂質[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let saturatedFat: [String] = [
        "saturated\\s+fat[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "gesättigte\\s+(?:fett)?säuren?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "acides\\s+gras\\s+saturés[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "grassi\\s+saturi[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "grasas\\s+saturadas[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "gorduras\\s+saturadas[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "verzadigde\\s+vetten[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "насыщенные\\s+жиры[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*г?",
        "饱和脂肪[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*克?",
        "飽和脂肪酸[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let protein: [String] = [
        "proteins?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "eiweiß[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "protéines?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "proteine[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "proteínas[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "eiwitten[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "белки[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*г?",
        "蛋白质[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*克?",
        "たんぱく質[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "タンパク質[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let fiber: [String] = [
        "(?:dietary\\s+)?fiber[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fibre[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "ballaststoffe[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fibres?\\s+alimentaires?[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "fibra[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "vezels[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?",
        "пищевые\\s+волокна[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*г?",
        "膳食纤维[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*克?",
        "食物繊維[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*g?"
    ]

    static let sodium: [String] = [
        "sodium[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "natrium[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "salt[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "salz[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "sel[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "sal[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "sodio[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "sódio[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "zout[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "соль[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:мг|г)?",
        "натрий[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:мг|г)?",
        "钠[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:毫克|克)?",
        "ナトリウム[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?",
        "食塩相当量[:\\s]*(\\d+(?:[.,]\\d+)?)\\s*(?:mg|g)?"
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
                String(localized: "The image could not be processed.")
            case .noTextFound:
                String(localized: "No text was found in the image.")
            case .parsingFailed:
                String(localized: "Could not extract nutrition information from the image.")
            }
        }
    }
}
