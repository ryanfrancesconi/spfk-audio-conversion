// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Accelerate
import Foundation
import SPFKBase

/// Data needed for drawing waveforms
public struct WaveformData: Hashable, Codable, Sendable {
    public let floatChannelData: FloatChannelData
    public let audioDuration: TimeInterval
    public let sampleRate: Double
    public let samplesPerPoint: Int

    // MARK: Derived values

    public let samplesPerSecond: Double
    public let resolution: WaveformDrawingResolution

    public var channelCount: Int {
        floatChannelData.count
    }

    public init(
        floatChannelData: FloatChannelData = .init(),
        samplesPerPoint: Int = 0,
        audioDuration: TimeInterval = 0,
        sampleRate: Double = 0
    ) {
        self.floatChannelData = floatChannelData
        self.samplesPerPoint = samplesPerPoint
        self.audioDuration = audioDuration
        self.sampleRate = sampleRate

        samplesPerSecond = sampleRate / samplesPerPoint.double
        resolution = WaveformDrawingResolution(samplesPerPoint: samplesPerPoint)
    }

    /// Extract a time range of audio data or the entire data if it matches
    /// 0 ... audioDuration
    ///
    /// - Parameter timeRange: time range to extract
    /// - Returns: FloatChannelData suitable for drawing
    public func subdata(in timeRange: ClosedRange<TimeInterval>) throws -> FloatChannelData {
        let timeRange = timeRange.clamped(to: 0 ... audioDuration)

        guard timeRange != 0 ... audioDuration else {
            return floatChannelData
        }

        let startTime = timeRange.lowerBound.clamped(
            to: 0 ... audioDuration - 0.01
        )

        let endTime = timeRange.upperBound.clamped(
            to: startTime + 0.01 ... audioDuration
        )

        guard startTime < endTime else {
            throw NSError(description: "audioDuration: \(audioDuration), invalid edit times \(startTime)...\(endTime)")
        }

        let startIndex = Int(startTime * samplesPerSecond)
        let endIndex = Int(endTime * samplesPerSecond)
        let frameCount = endIndex - startIndex

        return try edit(startIndex: startIndex, endIndex: endIndex, frameCount: frameCount)
    }

    func edit(startIndex: Int, endIndex: Int, frameCount: Int) throws -> FloatChannelData {
        var subdata: FloatChannelData = allocateFloatChannelData(length: frameCount, channelCount: channelCount)

        for n in 0 ..< floatChannelData.count {
            subdata[n] = [Float](floatChannelData[n][startIndex ..< endIndex])
            try Task.checkCancellation()
        }

        // Log.debug("updated data \(startIndex)..<\(endIndex)")

        return subdata
    }
}

// These aren't faster, will delete

// swiftformat:disable consecutiveSpaces
extension WaveformData {
    func copy_cblas(source: [Float], destination: inout [Float], sourceStartIndex: Int, destinationStartIndex: Int, count: Int) {
        // Ensure the Accelerate framework is imported

        // Use withUnsafeBufferPointer and withUnsafeMutableBufferPointer
        // to safely access the raw pointers of the Swift arrays
        source[sourceStartIndex ..< (sourceStartIndex + count)].withUnsafeBufferPointer { sourcePtr in
            destination[destinationStartIndex ..< (destinationStartIndex + count)].withUnsafeMutableBufferPointer { destPtr in
                // Get the base addresses and calculate the correct offset pointers
                let srcBaseAddress = sourcePtr.baseAddress!
                let destBaseAddress = destPtr.baseAddress!

                // Parameters: n (count), X (source pointer), incX (source increment), Y (destination pointer), incY (destination increment)
                cblas_scopy(Int32(count), srcBaseAddress, 1, destBaseAddress, 1)
            }
        }
    }

    func copy_memcpy(source: [Float], destination: inout [Float], sourceStartIndex: Int, destinationStartIndex: Int, count: Int) {
        source[sourceStartIndex ..< (sourceStartIndex + count)].withUnsafeBufferPointer { sourcePtr in
            destination[destinationStartIndex ..< (destinationStartIndex + count)].withUnsafeMutableBufferPointer { destPtr in
                let byteCount = count * MemoryLayout<Float>.stride
                memcpy(destPtr.baseAddress, sourcePtr.baseAddress, byteCount)
            }
        }
    }

    func copy(source: [Float], destination: inout [Float], sourceRange: Range<Int>, destinationIndex: Int) {
        let count = Int32(sourceRange.count)

        // Ensure destination array has enough capacity
        guard destinationIndex + sourceRange.count <= destination.count else {
            fatalError("Destination array is too small for the operation.")
        }

        cblas_scopy(
            count,                          // N: The number of elements to copy
            source,
            1,                              // incX: The stride for the source array (1 for contiguous elements)
            &destination[destinationIndex], // Y: Pointer to the start of the destination range
            1                               // incY: The stride for the destination array
        )
    }
}

// swiftformat:enable consecutiveSpaces
