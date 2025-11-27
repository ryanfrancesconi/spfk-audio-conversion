import Foundation

public protocol WaveformDataParserDelegate {
    func waveformDataParser(event: WaveformDataLoadEvent) async
}
