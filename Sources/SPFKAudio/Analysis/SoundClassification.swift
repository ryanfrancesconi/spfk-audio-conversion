
import Foundation
import SoundAnalysis

public enum SoundClassification {
    public static let defaultOverlap: Double = 0.5
    public static let defaultConfidence: Double = 0.3

    public static func knownClassificationsForVersion1() throws -> [String] {
        try SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications
    }

    public static func analyze(
        using mlModel: MLModel? = nil,
        url: URL,
        overlapFactor: Double = defaultOverlap,
        minimumConfidence: Double = defaultConfidence
    ) async throws -> [SNClassification]? {
        guard let mlModel else {
            return try await processDefault(url: url, overlapFactor: overlapFactor, minimumConfidence: minimumConfidence)
        }

        let request = try SNClassifySoundRequest(mlModel: mlModel)
        return try await process(request: request, url: url, overlapFactor: overlapFactor, minimumConfidence: minimumConfidence)
    }

    /// process audio using Apple's default `.version1` classifier
    private static func processDefault(
        url: URL,
        overlapFactor: Double = defaultOverlap,
        minimumConfidence: Double = defaultConfidence
    ) async throws -> [SNClassification]? {
        //
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        return try await process(request: request, url: url, overlapFactor: overlapFactor, minimumConfidence: minimumConfidence)
    }

    private static func process(
        request: SNClassifySoundRequest,
        url: URL,
        overlapFactor: Double = defaultOverlap,
        minimumConfidence: Double = defaultConfidence
    ) async throws -> [SNClassification]? {
        request.overlapFactor = overlapFactor

        let analyzer = try SNAudioFileAnalyzer(url: url)
        let observer = SoundClassificationResultObserver(minimumConfidence: minimumConfidence)
        try analyzer.add(request, withObserver: observer)
        await analyzer.analyze()
        return observer.classifications
    }
}
