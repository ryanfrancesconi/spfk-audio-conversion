import OTCore
import SimplyCoreAudio

public extension AudioDevice {
    struct NamedChannel: CustomStringConvertible, Equatable {
        public var description: String {
            var value = "\(scope.title) \(channel)"

            // MacBook air speakers Left channel is named "1". That's dumb.
            if let name, name != "", name != channel.string {
                value = "\(channel) - " + name
            }

            return value
        }

        var channel: UInt32
        var name: String?
        var scope: Scope
    }

    /// - Returns: A collection of named channels
    func namedChannels(scope: Scope) -> [NamedChannel] {
        var out = [NamedChannel]()

        let channelCount = channels(scope: scope)
        
        guard channelCount > 0 else { return [] }

        for i in 1 ... channelCount {
            let string = name(channel: i, scope: scope)?.trimmed

            let deviceChannel = NamedChannel(
                channel: i,
                name: string,
                scope: scope
            )

            out.append(deviceChannel)
        }
        return out
    }

    func preferredChannelsDescription(scope: Scope) -> String? {
        guard let preferredChannelsForStereo = preferredChannelsForStereo(scope: scope) else { return nil }

        var namedChannels = self.namedChannels(scope: .output).filter {
            $0.channel == preferredChannelsForStereo.left || $0.channel == preferredChannelsForStereo.right
        }

        namedChannels = namedChannels.sorted(by: { lhs, rhs -> Bool in
            lhs.channel < rhs.channel
        })

        let stringValues = namedChannels.map {
            $0.description
        }

        return stringValues.joined(separator: " + ")
    }
}

public extension Scope {
    var title: String {
        switch self {
        case .input:
            return "Input"
        case .output:
            return "Output"
        case .global:
            return "Global"
        case .playthrough:
            return "Playthrough"
        case .main, .master:
            return "Master"
        case .wildcard:
            return "Wildcard"
        }
    }
}
