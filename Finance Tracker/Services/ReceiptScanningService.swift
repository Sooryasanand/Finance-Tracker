import Foundation
import Vision
import UIKit
import os.log

class ReceiptScanningService: ObservableObject {
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let logger = Logger(subsystem: "FinanceTracker", category: "ReceiptScanning")
    
    struct ReceiptData {
        let merchantName: String?
        let amount: Decimal?
        let date: Date?
        let rawText: String
        let confidence: Float
    }
    
    enum ScanError: LocalizedError {
        case imageProcessingFailed
        case textRecognitionFailed
        case noTextFound
        case amountParsingFailed
        case dateParsingFailed
        case lowConfidence
        
        var errorDescription: String? {
            switch self {
            case .imageProcessingFailed:
                return "Failed to process the image"
            case .textRecognitionFailed:
                return "Failed to recognize text in the image"
            case .noTextFound:
                return "No text found in the image"
            case .amountParsingFailed:
                return "Could not find amount in receipt"
            case .dateParsingFailed:
                return "Could not find date in receipt"
            case .lowConfidence:
                return "Text recognition confidence is too low"
            }
        }
    }
    
    func scanReceipt(image: UIImage) async throws -> ReceiptData {
        logger.info("Starting receipt scan")
        
        await MainActor.run {
            isScanning = true
            scanProgress = 0.0
            errorMessage = nil
        }
        
        guard let cgImage = image.cgImage else {
            throw ScanError.imageProcessingFailed
        }
        
        // Perform text recognition
        await MainActor.run { scanProgress = 0.3 }
        let recognizedText = try await performTextRecognition(on: cgImage)
        
        // Parse receipt data
        await MainActor.run { scanProgress = 0.7 }
        let receiptData = try parseReceiptData(from: recognizedText)
        
        await MainActor.run {
            scanProgress = 1.0
            isScanning = false
        }
        
        logger.info("Receipt scan completed successfully")
        return receiptData
    }
    
    private func performTextRecognition(on cgImage: CGImage) async throws -> VNRecognizeTextObservation {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizeTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: ScanError.noTextFound)
                    return
                }
                
                // Combine all observations into one for processing
                let combinedObservation = observations.reduce(VNRecognizeTextObservation()) { result, observation in
                    // This is a simplified combination - in practice, you'd want to preserve spatial relationships
                    return observation
                }
                
                continuation.resume(returning: combinedObservation)
            }
            
            // Configure the request for better receipt recognition
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.revision = VNRecognizeTextRequestRevision3
            
            // Set recognition languages (English primarily for receipts)
            if #available(iOS 16.0, *) {
                request.recognitionLanguages = ["en-US"]
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ScanError.textRecognitionFailed)
            }
        }
    }
    
    private func parseReceiptData(from observation: VNRecognizeTextObservation) throws -> ReceiptData {
        guard let recognizedText = try? observation.topCandidates(1).first?.string else {
            throw ScanError.textRecognitionFailed
        }
        
        let confidence = observation.topCandidates(1).first?.confidence ?? 0.0
        
        // Require minimum confidence threshold
        guard confidence > 0.6 else {
            throw ScanError.lowConfidence
        }
        
        logger.debug("Recognized text: \(recognizedText)")
        logger.debug("Confidence: \(confidence)")
        
        let lines = recognizedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Parse merchant name (usually in the first few lines)
        let merchantName = extractMerchantName(from: lines)
        
        // Parse amount
        let amount = extractAmount(from: lines)
        
        // Parse date
        let date = extractDate(from: lines)
        
        return ReceiptData(
            merchantName: merchantName,
            amount: amount,
            date: date,
            rawText: recognizedText,
            confidence: confidence
        )
    }
    
    private func extractMerchantName(from lines: [String]) -> String? {
        // Look for merchant name in the first 5 lines
        let candidateLines = Array(lines.prefix(5))
        
        for line in candidateLines {
            // Skip lines that look like addresses, phone numbers, or common receipt headers
            let lowercased = line.lowercased()
            
            // Skip common non-merchant patterns
            if lowercased.contains("receipt") ||
               lowercased.contains("store #") ||
               lowercased.contains("tel:") ||
               lowercased.contains("phone:") ||
               lowercased.contains("address") ||
               lowercased.contains("thank you") ||
               line.count < 3 ||
               line.count > 50 {
                continue
            }
            
            // Check if line contains mostly letters (merchant names are usually text)
            let letterCount = line.filter { $0.isLetter }.count
            let totalCount = line.count
            
            if Double(letterCount) / Double(totalCount) > 0.7 {
                return line
            }
        }
        
        return candidateLines.first
    }
    
    private func extractAmount(from lines: [String]) -> Decimal? {
        let amountPatterns = [
            // $XX.XX format
            #"\$\s*(\d+(?:\.\d{2})?)"#,
            // XX.XX format
            #"(\d+\.\d{2})\s*$"#,
            // TOTAL: XX.XX format
            #"(?:total|amount|subtotal|grand total)[:]*\s*\$?(\d+\.\d{2})"#,
            // Look for monetary amounts
            #"(\d+\.\d{2})"#
        ]
        
        var potentialAmounts: [(Decimal, String)] = []
        
        for line in lines {
            let lowercased = line.lowercased()
            
            for pattern in amountPatterns {
                do {
                    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                    let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: line.count))
                    
                    for match in matches {
                        if let range = Range(match.range(at: 1), in: line) {
                            let amountString = String(line[range])
                            
                            if let amount = Decimal(string: amountString) {
                                // Prioritize amounts that appear near "total" keywords
                                let priority = lowercased.contains("total") ? 3 :
                                             lowercased.contains("subtotal") ? 2 :
                                             lowercased.contains("amount") ? 2 : 1
                                
                                potentialAmounts.append((amount, line))
                            }
                        }
                    }
                } catch {
                    continue
                }
            }
        }
        
        // Sort by likely relevance (amounts near "total" get priority)
        potentialAmounts.sort { first, second in
            let firstLine = first.1.lowercased()
            let secondLine = second.1.lowercased()
            
            let firstScore = (firstLine.contains("total") ? 3 : 0) +
                           (firstLine.contains("subtotal") ? 2 : 0) +
                           (firstLine.contains("amount") ? 1 : 0)
            
            let secondScore = (secondLine.contains("total") ? 3 : 0) +
                            (secondLine.contains("subtotal") ? 2 : 0) +
                            (secondLine.contains("amount") ? 1 : 0)
            
            return firstScore > secondScore
        }
        
        // Return the most likely amount
        return potentialAmounts.first?.0
    }
    
    private func extractDate(from lines: [String]) -> Date? {
        let datePatterns = [
            // MM/DD/YYYY
            #"(\d{1,2})/(\d{1,2})/(\d{4})"#,
            // MM-DD-YYYY
            #"(\d{1,2})-(\d{1,2})-(\d{4})"#,
            // MM.DD.YYYY
            #"(\d{1,2})\.(\d{1,2})\.(\d{4})"#,
            // YYYY-MM-DD
            #"(\d{4})-(\d{1,2})-(\d{1,2})"#
        ]
        
        let dateFormatter = DateFormatter()
        
        for line in lines {
            for pattern in datePatterns {
                do {
                    let regex = try NSRegularExpression(pattern: pattern, options: [])
                    let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: line.count))
                    
                    for match in matches {
                        if match.numberOfRanges >= 4 {
                            let fullMatch = String(line[Range(match.range(at: 0), in: line)!])
                            
                            // Try different date formats
                            let formats = ["MM/dd/yyyy", "MM-dd-yyyy", "MM.dd.yyyy", "yyyy-MM-dd"]
                            
                            for format in formats {
                                dateFormatter.dateFormat = format
                                if let date = dateFormatter.date(from: fullMatch) {
                                    // Validate that the date is reasonable (not too far in the future or past)
                                    let now = Date()
                                    let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!
                                    let oneMonthFromNow = Calendar.current.date(byAdding: .month, value: 1, to: now)!
                                    
                                    if date >= oneYearAgo && date <= oneMonthFromNow {
                                        return date
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    func reset() {
        isScanning = false
        scanProgress = 0.0
        errorMessage = nil
    }
}