// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation

public enum AudioExportOptions {
    public static let sampleRatesPCM: [String] = [
        "44100",
        "48000",
        "88200",
        "96000",
        "192000",
    ]

    public static let sampleRatesCompressed: [String] = [
        "44100",
        "48000",
    ]

    public static let bitRates: [String] = [
        "64", "80", "96", "128", "160",
        "192", "224", "256", "288", "320",
    ]

    public static let bitDepths: [String] = [
        "16", "24", "32",
    ]
}

public enum AudioExportMenuOptions {
    public static let sameAsSource = "Same as source"

    public static let outputFormats = [sameAsSource] + AudioFormatConverter.outputPathExtensions

    public static let sampleRatesPCM: [String] = [sameAsSource] +
        AudioExportOptions.sampleRatesPCM

    public static let sampleRatesCompressed: [String] = [sameAsSource] +
        AudioExportOptions.sampleRatesCompressed

    public static let bitRates: [String] = [sameAsSource] +
        AudioExportOptions.bitRates

    public static let bitDepths: [String] = [sameAsSource] +
        AudioExportOptions.bitDepths
}
