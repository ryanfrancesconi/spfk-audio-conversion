import Foundation
import SPFKUtils

public enum WaveformDataLoadEvent {
    case loading(url: URL, progress: UnitInterval)
    case loaded(url: URL, waveformData: WaveformData)
}
