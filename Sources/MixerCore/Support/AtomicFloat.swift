import RealtimeAtomics

/// A lock-free float cell that can be read and written from any thread, including the
/// Core Audio IO thread. Realtime code should capture `rawPointer` and call the C functions
/// directly so that no reference counting happens during rendering.
public final class AtomicFloat: @unchecked Sendable {
    public let rawPointer: OpaquePointer

    public init(_ initialValue: Float = 0) {
        rawPointer = rt_atomic_float_create(initialValue)
    }

    deinit {
        rt_atomic_float_destroy(rawPointer)
    }

    public func load() -> Float { rt_atomic_float_load(rawPointer) }
    public func store(_ value: Float) { rt_atomic_float_store(rawPointer, value) }
    public func exchange(_ value: Float) -> Float { rt_atomic_float_exchange(rawPointer, value) }
    public func storeMax(_ value: Float) { rt_atomic_float_store_max(rawPointer, value) }
}
