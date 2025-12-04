import Foundation

public protocol WaveformDataParserDelegate: AnyObject, Sendable {
    func waveformDataParser(event: WaveformDataLoadEvent) async
}
