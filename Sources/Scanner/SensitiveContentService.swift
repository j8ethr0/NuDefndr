// NudeFndr - nudefndr.com
// Transparency Repository - On-device sensitive content analysis (v2.6.1)

// Copyright (c) 2025 dro1d.org - All rights reserved.
//
// Released under the MIT License.
// See LICENSE file for details.
// NuDefndr App - Core Privacy Component

import Foundation
import SensitiveContentAnalysis
import UIKit
import CoreGraphics
import os

class SensitiveContentService {
    private let analyzer = SCSensitivityAnalyzer()
    private let logger = Logger(subsystem: "com.dro1d.PicDefndr", category: "SensitiveContent")
    
    private var cachedPolicy: SCSensitivityAnalysisPolicy?
    private var lastPolicyCheck: Date?
    private let policyCacheInterval: TimeInterval = 5.0
    
    // MARK: - Sensitive Content Warning Status
    
    /// Check if Sensitive Content Warning is enabled in system settings
    var isSensitiveContentWarningEnabled: Bool {
        let now = Date()
        
        if let lastCheck = lastPolicyCheck,
           let cached = cachedPolicy,
           now.timeIntervalSince(lastCheck) < policyCacheInterval {
            return cached != .disabled
        }
        
        let policy = analyzer.analysisPolicy
        cachedPolicy = policy
        lastPolicyCheck = now
        
        return policy != .disabled
    }
    
    /// Get the current analysis policy details
    var sensitiveContentWarningStatus: String {
        let policy = cachedPolicy ?? analyzer.analysisPolicy
        switch policy {
        case .disabled:
            return "Disabled"
        case .simpleInterventions:
            return "Enabled (Simple)"
        case .descriptiveInterventions:
            return "Enabled (Detailed)"
        @unknown default:
            return "Unknown"
        }
    }
    
    func analyzeImage(imageData: Data, assetIdentifier: String) async -> Bool {
        guard let uiImage = UIImage(data: imageData) else {
            return false
        }
        
        guard let cgImage = uiImage.cgImage else {
            return false
        }
        
        do {
            let result = try await analyzer.analyzeImage(cgImage)
            if result.isSensitive {
                return true
            }
            
            let scale: CGFloat = 1.25
            if let scaledImage = scaleImage(cgImage, by: scale) {
                let scaledResult = try await analyzer.analyzeImage(scaledImage)
                if scaledResult.isSensitive {
                    return true
                }
            }
            
            return false
            
        } catch {
            return false
        }
    }

    func analyzeImage(at imageURL: URL) async -> Bool {
        var shouldStopAccessing = false
        if imageURL.isFileURL {
             shouldStopAccessing = imageURL.startAccessingSecurityScopedResource()
             if !shouldStopAccessing {
                  logger.error("Warning: Could not gain security-scoped access for URL: \(imageURL). Attempting direct read.")
             }
        }

        defer {
            if shouldStopAccessing {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let imageData = try Data(contentsOf: imageURL)
            let identifier = imageURL.absoluteString
            return await analyzeImage(imageData: imageData, assetIdentifier: identifier)
        } catch {
            logger.error("Error loading image data from URL \(imageURL): \(error)")
            return false
        }
    }
    
    // Helper function to scale images
    private func scaleImage(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)
        
        guard let colorSpace = image.colorSpace else { return nil }
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: image.bitsPerComponent,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: image.bitmapInfo.rawValue) else { return nil }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
}

// MARK: - Timeout Helper

private struct TimeoutError: Error {}

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
