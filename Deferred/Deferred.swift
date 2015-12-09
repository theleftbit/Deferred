//
//  Deferred.swift
//  Deferred
//
//  Created by John Gallagher on 7/19/14.
//  Copyright © 2014-2015 Big Nerd Ranch. Licensed under MIT.
//

import Dispatch

// Atomic compare-and-swap, but safe for an initialize-once, owning pointer:
//  - ObjC: "MyObject *__strong *"
//  - Swift: "UnsafeMutablePointer<MyObject!>"
// If the assignment is made, the new value is retained by its owning pointer.
// If the assignment is not made, the new value is not retained.
private func atomicInitialize<T: AnyObject>(target: UnsafeMutablePointer<T?>, to desired: T) -> Bool {
    let newPtr = Unmanaged.passRetained(desired).toOpaque()
    let wonRace = OSAtomicCompareAndSwapPtr(nil, UnsafeMutablePointer(newPtr), UnsafeMutablePointer(target))
    if !wonRace {
        Unmanaged.passUnretained(desired).release()
    }
    return wonRace
}

// In order to assign the value of a scalar in a Deferred using atomics, we must
// box it up into something word-sized. See `atomicInitialize` above.
private final class Box<T> {

    let contents: T

    init(_ contents: T) {
        self.contents = contents
    }

}

// A dispatch block (which is different from a plain closure!) constitutes the
// second half of Deferred. The `dispatch_block_notify` API defines the notifier
// list used by `Deferred.upon(queue:body:)`.
private typealias OnFillMarker = dispatch_block_t

// Raw Deferred storage. Using `ManagedBuffer` has advantages over a custom class:
//  - The side-table data is efficiently stored in tail-allocated buffer space.
//  - The Element buffer has a stable pointer when locked to a single element.
//  - Better holdsUniqueReference support allows for future optimization.
private final class DeferredBuffer<Value>: ManagedBuffer<OnFillMarker, Box<Value>?> {
    
    static func create() -> DeferredBuffer<Value> {
        return create(1, initialValue: { _ in
            dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, {
                fatalError("This code should never be executed")
            })
        }) as! DeferredBuffer<Value>
    }
    
    deinit {
        // super's deinit automatically destroys the Value
        withUnsafeMutablePointerToElements { boxPtr in
            // UnsafeMutablePointer.destroy() is faster than destroy(_:)
            boxPtr.destroy()
        }
    }
    
    func initializeWith(value: Value?) {
        let box = value.map(Box.init)
        withUnsafeMutablePointerToElements { boxPtr in
            boxPtr.initialize(box)
        }
    }
    
    func withValue(body: Value -> Void) {
        withUnsafeMutablePointerToElements { boxPtr in
            guard let box = boxPtr.memory else { return }
            body(box.contents)
        }
    }
    
    func fill(value: Value, onFill: OnFillMarker -> Void) -> Bool {
        let box = Box(value)
        return withUnsafeMutablePointers { (onFillPtr, boxPtr) in
            guard atomicInitialize(boxPtr, to: box) else { return false }
            onFill(onFillPtr.memory)
            return true
        }
    }
    
    // The side-table data (our `dispatch_block_t`) is ManagedBuffer.value.
    var onFilled: OnFillMarker {
        return value
    }
    
}

// MARK: -

/// A deferred is a value that may become determined (or "filled") at some point
/// in the future. Once a deferred value is determined, it cannot change.
public struct Deferred<Value>: FutureType, PromiseType {
    private var storage = DeferredBuffer<Value>.create()
    
    /// Initialize an unfilled Deferred.
    public init() {
        storage.initializeWith(nil)
    }
    
    /// Initialize a filled Deferred with the given value.
    public init(value: Value) {
        storage.initializeWith(value)
        markFilled(storage.onFilled)
    }

    // MARK: FutureType

    private func upon(queue: dispatch_queue_t, var options: dispatch_block_flags_t, body: Value -> Void) -> dispatch_block_t {
        options.rawValue |= DISPATCH_BLOCK_ASSIGN_CURRENT.rawValue
        let block = dispatch_block_create(options) {
            self.storage.withValue(body)
        }
        dispatch_block_notify(storage.onFilled, queue, block)
        return block
    }

    /// Check whether or not the receiver is filled.
    public var isFilled: Bool {
        return dispatch_block_testcancel(storage.onFilled) != 0
    }
    
    /**
    Call some function once the value is determined.
    
    If the value is already determined, the function will be submitted to the
    queue immediately. An `upon` call is always executed asynchronously.
    
    :param: queue A dispatch queue for executing the given function on.
    :param: body A function that uses the determined value.
    */
    public func upon(queue: dispatch_queue_t, body: Value -> ()) {
        _ = upon(queue, options: DISPATCH_BLOCK_INHERIT_QOS_CLASS, body: body)
    }

    /**
    Waits synchronously for the value to become determined.

    If the value is already determined, the call returns immediately with the
    value.

    :param: time A length of time to wait for the value to be determined.
    :returns: The determined value, if filled within the timeout, or `nil`.
    */
    public func wait(time: Timeout) -> Value? {
        let queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)
        var value: Value?
        let handler = upon(queue, options: DISPATCH_BLOCK_ENFORCE_QOS_CLASS) {
            value = $0
        }

        guard dispatch_block_wait(handler, time.rawValue) == 0 else {
            dispatch_block_cancel(handler)
            return nil
        }

        return value
    }

    // MARK: PromiseType

    private func markFilled(marker: OnFillMarker) {
        // Cancel it so we can use `dispatch_block_testcancel` to mean "filled"
        dispatch_block_cancel(marker)
        // Executing the block "unblocks" it, calling all the `_notify` blocks
        marker()
    }
    
    /// Determines the deferred value with a given result.
    ///
    /// Filling a deferred value should usually be attempted only once.
    ///
    /// - parameter value: The resolved value for the instance.
    /// - returns: Whether the promise was fulfilled with `value`.
    public func fill(value: Value) -> Bool {
        return storage.fill(value, onFill: markFilled)
    }
}
