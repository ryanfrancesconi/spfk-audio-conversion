import Foundation
import SPFKBase

public enum WaveformDataLoadEvent {
    case loading(url: URL, progress: UnitInterval)
    case loaded(url: URL, waveformData: WaveformData)
}
