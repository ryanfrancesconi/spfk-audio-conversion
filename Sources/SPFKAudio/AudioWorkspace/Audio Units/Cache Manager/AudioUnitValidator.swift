
import AudioToolbox
import AVFoundation
import SPFKUtils

public class AudioUnitValidator {
    public struct ValidationResult: Sendable {
        public var result: AudioComponentValidationResult
        public var output: String?
    }

    private static var validateParams: CFDictionary {
        [
            kAudioComponentValidationParameter_LoadOutOfProcess: 1, // requires that the AU be able to load out of process
            kAudioComponentValidationParameter_TimeOut: 15, // this seems to work
            // kAudioComponentValidationParameter_ForceValidation: 1
        ] as CFDictionary
    }

    public static var auval: URL? {
        let cmd1 = URL(fileURLWithPath: "/usr/bin/auvaltool")

        if cmd1.exists {
            return cmd1
        }

        let cmd2 = URL(fileURLWithPath: "/usr/bin/auval")

        if cmd2.exists {
            return cmd2
        }

        // neither tool found
        return nil
    }

    public static func validate(component: AVAudioUnitComponent) -> ValidationResult {
        // note component.passesAUVal causes some AUs to hang indefinitely here

        var result: ValidationResult

        if #available(macOS 13.0, *) {
            result = validateWithResults(component: component)

        } else {
            result = validateLegacy(component: component)
        }

        if result.result == .passed {
            return ValidationResult(result: .passed)
        }

        return validateExternal(component: component)
    }

    // AudioComponentValidate
    static func validateLegacy(component: AVAudioUnitComponent) -> ValidationResult {
        var result: AudioComponentValidationResult = .unknown

        let status = AudioComponentValidate(component.audioComponent, validateParams, &result)

        guard status == noErr else {
            Log.error("*AU AudioComponentValidate error", status.fourCC)
            return ValidationResult(result: .failed, output: nil)
        }

        Log.default("*AU validateSync", component.name, "result:", result.description)

        return ValidationResult(result: result)
    }

    @available(macOS 13.0, *)
    static func validateWithResults(component: AVAudioUnitComponent) -> ValidationResult {
        let semaphore = DispatchSemaphore(value: 0)

        var out = ValidationResult(result: .unknown)

        AudioComponentValidateWithResults(component.audioComponent, validateParams) { result, _ in
            out = ValidationResult(result: result)
            semaphore.signal()
        }

        _ = semaphore.wait(wallTimeout: .now() + .seconds(15))

        Log.default("*AU validateWithResults", component.name, "result:", out.result.description)

        return out
    }

    static func validateExternal(component: AVAudioUnitComponent) -> ValidationResult {
        guard let cmd = auval else {
            // the auval tool is missing on this computer
            return ValidationResult(result: .unknown)
        }

        let desc = component.audioComponentDescription

        let args = [
            "-v",
            desc.componentType.fourCC,
            desc.componentSubType.fourCC,
            desc.componentManufacturer.fourCC,
        ].compactMap { $0 }

        Log.default("*AU validateExternal \(component.name):", cmd.lastPathComponent + " " + args.joined(separator: " "))

        let process = ProcessHandler(url: cmd, args: args, qos: .default)

        do {
            let out = try process.run()

            let result = parse(result: out)

            if result != .passed {
                Log.error("*AU validateExternal", component.name, "result:", result.description)

            } else {
                Log.default("*AU validateExternal", component.name, "result:", result.description)
            }

            return ValidationResult(
                result: result,
                output: out
            )

        } catch {
            return ValidationResult(result: .failed, output: error.localizedDescription)
        }
    }

    private static func parse(result: String) -> AudioComponentValidationResult {
        if result.contains("AU VALIDATION SUCCEEDED") {
            return .passed

        } else if result.contains("FATAL ERROR: OpenAComponent") {
            return .unauthorizedError_Open

        } else if result.contains("FATAL ERROR: Initialize") {
            return .unauthorizedError_Init

        } else {
            return .failed
        }
    }
}

extension AudioComponentValidationResult {
    /**
     case unknown = 0
     case passed = 1
     case failed = 2
     case timedOut = 3
     case unauthorizedError_Open = 4
     case unauthorizedError_Init = 5
     */
    public var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .passed:
            return "Passed"
        case .failed:
            return "Failed"
        case .timedOut:
            return "Timed out"
        case .unauthorizedError_Open:
            return "Unable to open"
        case .unauthorizedError_Init:
            return "Unable to initialize"
        @unknown default:
            return "Unknown"
        }
    }

    public init?(description: String) {
        switch description {
        case "Unknown":
            self = .unknown
        case "Passed":
            self = .passed
        case "Failed":
            self = .failed
        case "Timed out":
            self = .timedOut
        case "Unable to open":
            self = .unauthorizedError_Open
        case "Unable to initialize":
            self = .unauthorizedError_Init
        default:
            return nil
        }
    }
}
