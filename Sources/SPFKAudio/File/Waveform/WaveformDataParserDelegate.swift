import Foundation

public protocol WaveformDataParserDelegate: AnyObject {
    func waveformDataParser(event: WaveformDataLoadEvent) async
}
