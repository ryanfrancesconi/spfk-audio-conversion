// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

/// Wraps NodeParameter so we can easily assign values to it.
///
/// Instead of`osc.frequency.value = 440`, we have `osc.frequency = 440`
///
/// Use the $ operator to access the underlying NodeParameter. For example:
/// `osc.$frequency.maxValue`
///
/// When writing a Node, use:
/// ```
/// @Parameter(myParameterDef) var myParameterName: AUValue
/// ```
/// This syntax gives us additional flexibility for how parameters are implemented internally.
///
/// Note that we don't allow initialization of Parameters to values
/// because we don't yet have an underlying AUParameter.
@propertyWrapper
public struct Parameter<Value: NodeParameterType>: ParameterBase {
    var param: NodeParameter

    /// Create a parameter given a definition
    public init(_ def: NodeParameterDef) {
        param = NodeParameter(def)
    }

    /// Get the wrapped value
    public var wrappedValue: Value {
        get { Value(param.value) }
        set { param.value = newValue.toAUValue() }
    }

    /// Get the projected value
    public var projectedValue: NodeParameter {
        get { param }
        set { param = newValue }
    }
}

/// Used internally so we can iterate over parameters using reflection.
protocol ParameterBase {
    var projectedValue: NodeParameter { get }
}
