import Combine

/// View-local state. Stands in for SwiftUI's `@State`, which in this SDK is a macro whose
/// compiler plugin ships only with Xcode (this project builds with the Command Line Tools).
/// Use as `@StateObject private var x = ViewState(initial)` and read/write `x.value`.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
