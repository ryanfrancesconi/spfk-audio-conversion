import AudioToolbox

/// Straight line
public enum LinearTaper {
    public static let taper = (in: AUValue(1.0), out: AUValue(1.0))
    public static let skew = (in: AUValue(0), out: AUValue(0))
}

/// Half pipe
public enum AudioTaper {
    public static let taper = (in: AUValue(3.0), out: AUValue(0.333))
    public static let skew = (in: AUValue(0.333), out: AUValue(1))
}

/// Inverse half pipe
public enum ReverseAudioTaper {
    public static let taper = (in: AUValue(0.333), out: AUValue(3.0))
    public static let skew = (in: AUValue(1), out: AUValue(0.333))
}
