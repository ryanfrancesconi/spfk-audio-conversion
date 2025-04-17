import AVFoundation
import Foundation
import SPFKUtils

public enum AudioTools {
    // NOTE: this is here until a more suitable place is found for it
    public static func createLoopedAudio(input: URL, output: URL, minimumDuration: TimeInterval) async throws -> URL {
        guard input != output else {
            throw NSError(description: "Input shoud be different than the output")
        }

        let avFile = try AVAudioFile(forReading: input)
        var tmpfile: URL?
        let duration = avFile.duration

        guard duration * 2 < minimumDuration else {
            throw NSError(description: "input duration is too long (\(duration)) sec and doesn't make sense to loop. VS minimumDuration \(minimumDuration) sec")
        }

        guard let buffer = try AVAudioPCMBuffer(url: input) else {
            throw NSError(description: "Failed to read audio data into buffer")
        }

        let numberOfDuplicates = (minimumDuration / duration).int

        let duplicatedBuffer = try buffer.loop(numberOfDuplicates: numberOfDuplicates)

        Log.debug("Duplicating data \(numberOfDuplicates) times to new file at ", output.path)

        try duplicatedBuffer.write(to: output)
        tmpfile = output

        guard let tmpfile, tmpfile.exists else {
            throw NSError(description: "Failed to create temp file")
        }

        return tmpfile
    }
}
