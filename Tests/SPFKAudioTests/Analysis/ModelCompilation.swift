import SoundAnalysis
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

// MARK: - example of how to compile a MLModel

@Suite(.tags(.development))
struct ModelCompilation {
    @Test func compileCustomModel() async throws {
        let modelURL = URL(fileURLWithPath: "/Volumes/ADD2/CreateML/SoundDesign101 1.mlpackage")

        guard modelURL.exists else {
            return
        }

        let model = try await compile(modelAt: modelURL)

        // test it

        let audioURL = URL(fileURLWithPath: "/Volumes/ADD2/CreateML/Hits/Boom/Boom 06_Hits_Boom.wav")
        let result = try await SoundClassification.analyze(using: model, url: audioURL, overlapFactor: 0.5, minimumConfidence: 0.1)

        Log.debug(result)
    }

    func compile(modelAt modelURL: URL) async throws -> MLModel {
        let compiledModelURL = try await MLModel.compileModel(at: modelURL)

        Log.debug(compiledModelURL)

        let model = try await MLModel.load(contentsOf: compiledModelURL)
        let destination = modelURL.deletingLastPathComponent().appendingPathComponent(compiledModelURL.lastPathComponent)

        try FileManager.default.copyItem(
            at: compiledModelURL,
            to: destination
        )

        return model
    }
}
