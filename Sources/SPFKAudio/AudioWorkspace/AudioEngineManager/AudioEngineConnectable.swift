
// TODO: REFACTOR: this will be removed once the audio system is consolidated into a single place
public protocol AudioEngineConnectable {
    func createAudioNodes(engineManager: any AudioEngineManagerModel) async throws
    func disposeAudioNodes() async throws
}
