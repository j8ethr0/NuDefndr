import Foundation
import UIKit
import SensitiveContentAnalysis

/// Wrapper for Apple SensitiveContentAnalysis framework
/// On-device ML only - NO network activity
@available(iOS 17.0, *)
final class ContentAnalyzer {
    
    enum AnalysisResult {
        case sensitive
        case safe
        case unavailable
        case error(Error)
    }
    
    /// Analyze image using Apple's on-device ML
    /// NOTE: Zero network requests - all processing is local
    func analyze(image: UIImage) async -> AnalysisResult {
        guard let analyzer = SCSensitivityAnalyzer() else {
            return .unavailable
        }
        
        do {
            let analysis = try await analyzer.analyzeImage(image)
            return analysis.isSensitive ? .sensitive : .safe
        } catch {
            return .error(error)
        }
    }
}
