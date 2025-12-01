import Foundation

public protocol WaveformDataParserDelegate: Sendable {
    func waveformDataParser(event: WaveformDataLoadEvent) async
}
