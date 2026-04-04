#if !canImport(Combine)
// Legacy fallback for macOS 10.13 builds where Combine is unavailable.
public protocol ObservableObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif
