import AudioToolbox

/// straight line
public enum LinearTaper {
    public static var taper = (in: AUValue(1.0), out: AUValue(1.0))
    public static var skew = (in: AUValue(0), out: AUValue(0))
}

/// half pipe
public enum AudioTaper {
    public static var taper = (in: AUValue(3.0), out: AUValue(0.33333))
    public static var skew = (in: AUValue(1), out: AUValue(0.333333))
}

/// inverse half pipe
public enum ReverseAudioTaper {
    public static var taper = (in: AUValue(0.333333), out: AUValue(3.0))
    public static var skew = (in: AUValue(1), out: AUValue(0.33333))
}
