// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AEXML
import AVFoundation
import Foundation
import SPFKAudioC
import SPFKUtils

// TODO: review apis added after this class was written for preset management (if os available)

public class AudioUnitState: AudioUnitStateC {
    public enum Locations {
        static var userPresets: URL {
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library")
                .appendingPathComponent("Audio")
                .appendingPathComponent("Presets")
        }

        public static func getPresetsFolders(for audioUnit: AVAudioUnit) -> [URL]? {
            let url = AudioUnitState.Locations.userPresets

            guard let audioUnitName = audioUnit.auAudioUnit.audioUnitName else {
                Log.debug("Couldn't get name of Audio Unit.")
                return nil
            }

            guard let manufacturer = audioUnit.auAudioUnit.manufacturerName else {
                Log.debug("Couldn't get name of Audio Unit manufacturer.")
                return nil
            }

            let primaryURL = url.appendingPathComponent(manufacturer).appendingPathComponent(audioUnitName)

            var urls = [primaryURL]

            // FCP is saving presets under the fourcc rather than the manufacturer string. this is probably a bug
            if let fourCC = audioUnit.auAudioUnit.componentDescription.componentManufacturer.fourCharCodeToString() {
                urls.append(
                    url.appendingPathComponent(fourCC).appendingPathComponent(audioUnitName)
                )
            }

            if !FileManager.default.fileExists(atPath: primaryURL.path) {
                guard (try? FileManager.default.createDirectory(at: primaryURL, withIntermediateDirectories: true, attributes: nil)) != nil else {
                    Log.debug("Unable to create preset folder for \(url.path)")
                    return nil
                }
            }

            return urls
        }

        public static func getUserPresets(for audioUnit: AVAudioUnit) -> [URL]? {
            guard let presetsFolders = getPresetsFolders(for: audioUnit) else {
                Log.error("Failed to get presets folder for", audioUnit.auAudioUnit.audioUnitName)
                return nil
            }
            var out = [URL]()

            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

            for folder in presetsFolders {
                if let enumerator = FileManager().enumerator(
                    at: folder,
                    includingPropertiesForKeys: [],
                    options: options,
                    errorHandler: nil
                ) {
                    while let url = enumerator.nextObject() as? URL {
                        if url.pathExtension == "aupreset" {
                            out.append(url)
                        }
                    }
                }
            }

            return out
        }
    }

    // MARK: Create Preset XML

    /// convenience used by for embedding full state in project XML
    public static func fullStateDocument(for avAudioUnit: AVAudioUnit) -> AEXMLDocument? {
        guard let state = avAudioUnit.auAudioUnit.fullState else { return nil }
        return try? PlistUtilities.dictionaryToPlist(dictionary: state)
    }

    @discardableResult
    public static func loadPreset(for avAudioUnit: AVAudioUnit, element: AEXMLElement) -> [String: Any]? {
        guard let fullState = try? PlistUtilities.plistToDictionary(element: element) else {
            return nil
        }

        loadPreset(for: avAudioUnit, fullState: fullState)

        return fullState
    }

    public static func loadPreset(for avAudioUnit: AVAudioUnit, fullState: [String: Any]) {
        avAudioUnit.auAudioUnit.fullState = fullState

        let status = notifyAudioUnitListener(avAudioUnit.audioUnit)

        guard noErr == status else {
            Log.error("notifyAudioUnitListener returned error:", status.fourCharCodeToString())
            return
        }
    }
}
