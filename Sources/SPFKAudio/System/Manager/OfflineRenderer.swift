// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import OTAtomics
import SPFKUtils

/// Wrapper on top of engine renderer with some event handlers
public class OfflineRenderer {
    public enum Event {
        case renderCancelled
        case renderStarted
        case renderProgress(event: AsyncProgressEvent)
        case renderComplete
        case renderError(Error)
    }

    public var eventHandler: ((Event) -> Void)?
    public private(set) weak var engineManager: AudioEngineManagerModel?

    // MARK: -

    @OTAtomicsThreadSafe public private(set) var abortFlag: Bool = false

    // BAD, this is being used as the array of files to be converted
    // TimelineRenderer adds directly to it as it bounces tracks
    public var bouncedURLs: [URL] = []

    @OTAtomicsThreadSafe private var convertedFiles: [URL] = []

    public var currentSettings = AudioFormatConverterOptions()
    public private(set) var isRunning: Bool = false
    fileprivate var savedCurrentTime: DispatchTime?
    public var exportAudio: Bool = true
    public var overwriteExistingFiles: Bool = true
    private var tempMixURL: URL?
    public private(set) var convertedMixURL: URL?
    public private(set) var filenameNoExtension: String = ""
    public private(set) var directoryURL: URL?
    public private(set) var tempString: String = ""

    /// unique string added to temp files to identify them as such
    private func updateTempID() {
        tempString = "_" + Entropy.uniqueId + "_temp"
    }

    /// intermediate file type for rendering at 32bit float
    public let renderFileType: AudioFileType = .caf

    /// render at 32bit then convert after
    public var renderFormat: AVAudioFormat? { engineManager?.renderFormat }

    public init() {}

    public func render(
        engineManager: AudioEngineManagerModel,
        to url: URL,
        duration: Double,
        renderUntilSilent: Bool,
        audioSettings: AudioFormatConverterOptions,
        prerender: @escaping () -> Void,
        postrender: (() -> Void)? = nil
    ) {
        self.engineManager = engineManager

        bouncedURLs.removeAll()
        abortFlag = false
        updateTempID()
        currentSettings = audioSettings

        filenameNoExtension = url.deletingPathExtension().lastPathComponent
        directoryURL = url.deletingLastPathComponent()

        send(event: .renderStarted)

        // main mix
        let mixPath = url.deletingPathExtension().path + tempString + "." + renderFileType.pathExtension
        let timelineURL = URL(fileURLWithPath: mixPath)

        Task(priority: .high) {
            self.processBounceAsync(timelineURL: timelineURL,
                                    duration: duration,
                                    renderUntilSilent: renderUntilSilent,
                                    prerender: prerender,
                                    postrender: postrender
            )
        }
    }

    private func processBounceAsync(
        timelineURL: URL,
        duration: Double,
        renderUntilSilent: Bool,
        prerender: @escaping () -> Void,
        postrender: (() -> Void)? = nil
    ) {
        guard let engineManager else {
            assertionFailure("engineManager is nil")
            return
        }

        guard let renderFormat = renderFormat?.settings else {
            send(event: .renderError(NSError(description: "Error: couldn't read internal output format.")))
            return
        }

        bouncedURLs.append(timelineURL)

        do {
            let file = try AVAudioFile(forWriting: timelineURL, settings: renderFormat)

            try engineManager.render(
                to: file,
                duration: duration,
                renderUntilSilent: renderUntilSilent,
                prerender: prerender,
                postrender: postrender,
                progress: { value in

                    self.send(event:
                        .renderProgress(
                            event: (string: "Rendering to \(self.filenameNoExtension)...", progress: value * 100)
                        )
                    )
                }
            )

            if abortFlag {
                Log.debug("🛑 User cancelled rendering")
                return
            }

        } catch {
            Log.error("ERROR:", error)

            Task { @MainActor in
                send(event: .renderError(error))
                self.cancel()
            }
            return
        }

        tempMixURL = timelineURL

        send(event: .renderComplete)
    }

    // TODO: REFACTOR: these class var references are bad
    public func convertAudio() async {
        guard !abortFlag else { return }

        var exported = [URL]()

        for url in bouncedURLs {
            let output = await convertAudio(url: url)

            guard !abortFlag else {
                try? output?.delete()
                return
            }

            if let output {
                exported.append(output)

                if url == tempMixURL {
                    convertedMixURL = output
                }
            }
        }

        convertedFiles += exported
    }

    private func convertAudio(url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            convertAudio(url: url) { output in
                continuation.resume(returning: output)
            }
        }
    }

    private func convertAudio(url: URL, completionHandler: ((URL?) -> Void)?) {
        var outputName = url.deletingPathExtension().lastPathComponent

        outputName = outputName.replacingOccurrences(of: tempString, with: "")

        let inputURL = url
        let format = currentSettings.format ?? .wav

        var outputURL = URL(fileURLWithPath: inputURL.deletingLastPathComponent().path +
            "/\(outputName).\(format)")

        if outputURL.exists, overwriteExistingFiles {
            try? outputURL.delete()
        }

        outputURL = FileSystem.nextAvailableURL(outputURL)

        Log.debug("* Converting", inputURL.path, "to", outputURL.path)

        let converter = AudioFormatConverter(inputURL: inputURL,
                                             outputURL: outputURL,
                                             options: currentSettings)

        converter.start { error in
            if let error {
                Log.error(error)
                completionHandler?(nil)

            } else {
                completionHandler?(outputURL)
            }
        }
    }

    public func cleanup() {
        Log.debug("Cleaning up...")

        isRunning = false

        // user chose not to save the main mix, so remove now
        if !exportAudio,
           let convertedMixURL, convertedMixURL.exists {
            do {
                Log.debug("Removing mix:", convertedMixURL)
                try convertedMixURL.delete()
            } catch {
                Log.error(error)
            }
        }

        // raw caf renders
        let tempfiles = bouncedURLs.filter { $0.lastPathComponent.contains(tempString) }

        for url in tempfiles {
            do {
                Log.debug("* Deleting \(url.path)")

                try url.delete()

            } catch {
                Log.error("ERROR:", error)
            }
        }

        bouncedURLs.removeAll()
        convertedFiles.removeAll()
    }

    // not a stub
    public func cancel() {
        guard !abortFlag else {
            return
        }

        abortFlag = true
        engineManager?.cancelRender()

        for url in convertedFiles {
            Log.debug("* Deleting \(url.path)")
            try? url.delete()
        }

        cleanup()

        send(event: .renderCancelled)
    }

    // isolate eventHandler? here
    func send(event: Event) {
        eventHandler?(event)
    }
}
