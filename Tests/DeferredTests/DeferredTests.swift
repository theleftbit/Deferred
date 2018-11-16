//
//  DeferredTests.swift
//  DeferredTests
//
//  Created by John Gallagher on 7/19/14.
//  Copyright © 2014-2018 Big Nerd Ranch. Licensed under MIT.
//

import XCTest
import Dispatch
import Deferred

// swiftlint:disable file_length
// swiftlint:disable type_body_length

class DeferredTests: XCTestCase {
    static let universalTests: [(String, (DeferredTests) -> () throws -> Void)] = [
        ("testPeekWhenUnfilled", testPeekWhenUnfilled),
        ("testPeekWhenFilled", testPeekWhenFilled),
        ("testWaitWithTimeout", testWaitWithTimeout),
        ("testValueOnFilled", testValueOnFilled),
        ("testValueBlocksWhileUnfilled", testValueBlocksWhileUnfilled),
        ("testValueUnblocksWhenUnfilledIsFilled", testValueUnblocksWhenUnfilledIsFilled),
        ("testFill", testFill),
        ("testCannotFillMultipleTimes", testCannotFillMultipleTimes),
        ("testIsFilled", testIsFilled),
        ("testUponCalledWhenFilled", testUponCalledWhenFilled),
        ("testUponCalledIfAlreadyFilled", testUponCalledIfAlreadyFilled),
        ("testUponNotCalledWhileUnfilled", testUponNotCalledWhileUnfilled),
        ("testUponMainQueueCalledWhenFilled", testUponMainQueueCalledWhenFilled),
        ("testConcurrentUpon", testConcurrentUpon),
        ("testAllCopiesOfADeferredValueRepresentTheSameDeferredValue", testAllCopiesOfADeferredValueRepresentTheSameDeferredValue),
        ("testDeferredOptionalBehavesCorrectly", testDeferredOptionalBehavesCorrectly),
        ("testIsFilledCanBeCalledMultipleTimesNotFilled", testIsFilledCanBeCalledMultipleTimesNotFilled),
        ("testIsFilledCanBeCalledMultipleTimesWhenFilled", testIsFilledCanBeCalledMultipleTimesWhenFilled),
        ("testSimultaneousFill", testSimultaneousFill),
        ("testDebugDescriptionUnfilled", testDebugDescriptionUnfilled),
        ("testDebugDescriptionFilled", testDebugDescriptionFilled),
        ("testDebugDescriptionFilledWhenValueIsVoid", testDebugDescriptionFilledWhenValueIsVoid),
        ("testReflectionUnfilled", testReflectionUnfilled),
        ("testReflectionFilled", testReflectionFilled),
        ("testReflectionFilledWhenValueIsVoid", testReflectionFilledWhenValueIsVoid)
    ]

    #if canImport(Darwin) && !targetEnvironment(simulator)
    static let darwinDeviceTests: [(String, (DeferredTests) -> () throws -> Void)] = [
        ("testThatMainThreadPostsUponWithUserInitiatedQoSClass", testThatMainThreadPostsUponWithUserInitiatedQoSClass),
        ("testThatLowerQoSPostsUponWithSameQoSClass", testThatLowerQoSPostsUponWithSameQoSClass)
    ]

    static var allTests: [(String, (DeferredTests) -> () throws -> Void)] {
        return universalTests + darwinDeviceTests
    }
    #else
    static var allTests: [(String, (DeferredTests) -> () throws -> Void)] {
        return universalTests
    }
    #endif

    func testPeekWhenUnfilled() {
        let unfilled = Deferred<Int>()
        XCTAssertNil(unfilled.peek())
    }

    func testPeekWhenFilled() {
        let toBeFilled = Deferred<Int>()
        toBeFilled.fill(with: 1)
        XCTAssertEqual(toBeFilled.peek(), 1)
    }

    func testWaitWithTimeout() {
        let deferred = Deferred<Int>()

        let expect = expectation(description: "value blocks while unfilled")
        afterShortDelay {
            deferred.fill(with: 42)
            expect.fulfill()
        }

        XCTAssertNil(deferred.shortWait())

        shortWait(for: [ expect ])
    }

    func testValueOnFilled() {
        let toBeFilled = Deferred<Int>()
        toBeFilled.fill(with: 2)
        XCTAssertEqual(toBeFilled.value, 2)
    }

    func testValueBlocksWhileUnfilled() {
        let unfilled = Deferred<Int>()
        let expect = expectation(description: "value blocks while unfilled")

        DispatchQueue.global().async {
            XCTAssertNil(unfilled.wait(until: .now() + 2))
        }

        afterShortDelay {
            expect.fulfill()
        }

        shortWait(for: [ expect ])
    }

    func testValueUnblocksWhenUnfilledIsFilled() {
        let deferred = Deferred<Int>()
        let expect = expectation(description: "value blocks until filled")

        DispatchQueue.global().async {
            XCTAssertEqual(deferred.value, 3)
            expect.fulfill()
        }

        afterShortDelay {
            deferred.fill(with: 3)
        }

        shortWait(for: [ expect ])
    }

    func testFill() {
        let toBeFilled = Deferred<Int>()
        toBeFilled.fill(with: 1)
        XCTAssertEqual(toBeFilled.value, 1)
    }

    func testCannotFillMultipleTimes() {
        let toBeFilledRepeatedly = Deferred<Int>()

        toBeFilledRepeatedly.fill(with: 1)
        XCTAssertEqual(toBeFilledRepeatedly.value, 1)

        XCTAssertFalse(toBeFilledRepeatedly.fill(with: 2))

        XCTAssertEqual(toBeFilledRepeatedly.value, 1)
    }

    func testIsFilled() {
        let toBeFilled = Deferred<Int>()
        XCTAssertFalse(toBeFilled.isFilled)

        let expect = expectation(description: "isFilled is true when filled")
        toBeFilled.upon { _ in
            XCTAssertTrue(toBeFilled.isFilled)
            expect.fulfill()
        }
        toBeFilled.fill(with: 1)
        shortWait(for: [ expect ])
    }

    func testUponCalledWhenFilled() {
        let toBeFilled = Deferred<Int>()
        let allExpectations = (0 ..< 10).map { (iteration) -> XCTestExpectation in
            let expect = expectation(description: "upon block #\(iteration) called with correct value")
            toBeFilled.upon { value in
                XCTAssertEqual(value, 1)
                expect.fulfill()
            }
            return expect
        }
        toBeFilled.fill(with: 1)
        shortWait(for: allExpectations)
    }

    func testUponCalledIfAlreadyFilled() {
        let toBeFilled = Deferred<Int>()
        toBeFilled.fill(with: 1)

        let allExpectations = (0 ..< 10).map { (iteration) -> XCTestExpectation in
            let expect = expectation(description: "upon block #\(iteration) not called while deferred is unfilled")
            toBeFilled.upon { value in
                XCTAssertEqual(value, 1)
                expect.fulfill()
            }
            return expect
        }

        shortWait(for: allExpectations)
    }

    func testUponNotCalledWhileUnfilled() {
        let expect: XCTestExpectation
        do {
            let object = NSObject()
            let deferred = Deferred<Int>()
            for _ in 0 ..< 5 {
                 deferred.upon { (value) in
                    XCTFail("Unexpected upon handler call with \(value) with capture \(object)")
                }
            }
            expect = expectation(deallocationOf: object)
        }
        shortWait(for: [ expect ])
    }

    func testUponMainQueueCalledWhenFilled() {
        let deferred = Deferred<Int>()

        let expect = expectation(description: "upon block called on main queue")
        deferred.upon(.main) { value in
            XCTAssert(Thread.isMainThread)
            XCTAssertEqual(value, 1)
            expect.fulfill()
        }

        deferred.fill(with: 1)
        shortWait(for: [ expect ])
    }

    func testConcurrentUpon() {
        let deferred = Deferred<Int>()
        let queue = DispatchQueue.global()

        // spin up a bunch of these in parallel...
        let allExpectations = (0 ..< 32).map { (iteration) -> XCTestExpectation in
            let expect = expectation(description: "upon block \(iteration)")
            queue.async {
                deferred.upon { _ in
                    expect.fulfill()
                }
            }
            return expect
        }

        // ...then fill it (also in parallel)
        queue.async {
            deferred.fill(with: 1)
        }

        // ... and make sure all our upon blocks were called (i.e., the write lock protected access)
        shortWait(for: allExpectations)
    }

    /// Deferred values behave as values: All copies reflect the same value.
    /// The wrinkle of course is that the value might not be observable till a later
    /// date.
    func testAllCopiesOfADeferredValueRepresentTheSameDeferredValue() {
        let parent = Deferred<Int>()
        let child1 = parent
        let child2 = parent
        let allDeferreds = [parent, child1, child2]

        let anyValue = 42
        let expectedValues = [Int](repeating: anyValue, count: allDeferreds.count)

        let expect = expectation(description: "filling any copy fulfills all")
        allDeferreds.allFilled().upon { (allValues) in
            XCTAssertEqual(allValues, expectedValues, "all deferreds are the same value")
            expect.fulfill()
        }

        allDeferreds.randomElement()?.fill(with: anyValue)

        shortWait(for: [ expect ])
    }

    func testDeferredOptionalBehavesCorrectly() {
        let toBeFilled = Deferred<Int?>()
        toBeFilled.fill(with: nil)

        let beforeExpect = expectation(description: "already filled with nil optional")
        toBeFilled.upon { (value) in
            XCTAssertNil(value)
            beforeExpect.fulfill()
        }

        XCTAssertFalse(toBeFilled.fill(with: 42))

        let afterExpect = expectation(description: "stays filled with same optional")
        toBeFilled.upon { (value) in
            XCTAssertNil(value)
            afterExpect.fulfill()
        }

        shortWait(for: [ beforeExpect, afterExpect ])
    }

    func testIsFilledCanBeCalledMultipleTimesNotFilled() {
        let unfilled = Deferred<Int>()

        for _ in 0 ..< 5 {
            XCTAssertFalse(unfilled.isFilled)
        }
    }

    func testIsFilledCanBeCalledMultipleTimesWhenFilled() {
        let toBeFilled = Deferred<Int>()
        toBeFilled.fill(with: 42)

        for _ in 0 ..< 5 {
            XCTAssertTrue(toBeFilled.isFilled)
        }
    }

    // The QoS APIs do not behave as expected on the iOS Simulator, so we only
    // run these tests on real devices.
    #if canImport(Darwin) && !targetEnvironment(simulator)
    func testThatMainThreadPostsUponWithUserInitiatedQoSClass() {
        let deferred = Deferred<Int>()

        let expectedQoS = DispatchQoS.QoSClass(rawValue: qos_class_main())
        var uponQoS: DispatchQoS.QoSClass?
        let expect = expectation(description: "deferred upon blocks get called")

        deferred.upon { _ in
            uponQoS = DispatchQoS.QoSClass(rawValue: qos_class_self())
            expect.fulfill()
        }

        deferred.fill(with: 42)

        shortWait(for: [ expect ])
        XCTAssertEqual(uponQoS, expectedQoS)
    }

    func testThatLowerQoSPostsUponWithSameQoSClass() {
        let expectedQoS = DispatchQoS.QoSClass.utility

        let deferred = Deferred<Int>()
        let queue = DispatchQueue.global(qos: expectedQoS)

        var uponQoS: DispatchQoS.QoSClass?
        let expect = expectation(description: "deferred upon blocks get called")

        deferred.upon(queue) { _ in
            uponQoS = DispatchQoS.QoSClass(rawValue: qos_class_self())
            expect.fulfill()
        }

        deferred.fill(with: 42)

        shortWait(for: [ expect ])
        XCTAssertEqual(uponQoS, expectedQoS)
    }
    #endif // end QoS tests that require a real device

    func testSimultaneousFill() {
        let deferred = Deferred<Int>()
        let startGroup = DispatchGroup()
        startGroup.enter()
        let finishGroup = DispatchGroup()

        let expect = expectation(description: "isFilled is true when filled")
        deferred.upon { _ in
            expect.fulfill()
        }

        for randomValue in 0 ..< 10 {
            DispatchQueue.global().async(group: finishGroup) {
                XCTAssertEqual(startGroup.wait(timeout: .distantFuture), .success)
                deferred.fill(with: randomValue)
            }
        }

        startGroup.leave()
        XCTAssertEqual(finishGroup.wait(timeout: .distantFuture), .success)
        shortWait(for: [ expect ])
    }

    func testDebugDescriptionUnfilled() {
        let unfilled = Deferred<Int>()
        XCTAssertEqual("\(unfilled)", "Deferred(not filled)")
    }

    func testDebugDescriptionFilled() {
        let toBeFilled = Deferred<Int>(filledWith: 42)
        toBeFilled.fill(with: 42)

        XCTAssertEqual("\(toBeFilled)", "Deferred(42)")
    }

    func testDebugDescriptionFilledWhenValueIsVoid() {
        let toBeFilled = Deferred<Void>()
        toBeFilled.fill(with: ())

        XCTAssertEqual("\(toBeFilled)", "Deferred(filled)")
    }

    func testReflectionUnfilled() {
        let unfilled = Deferred<Int>()

        let magicMirror = Mirror(reflecting: unfilled)
        XCTAssertEqual(magicMirror.displayStyle, .optional)
        XCTAssertNil(magicMirror.superclassMirror)
        XCTAssertEqual(magicMirror.descendant("isFilled") as? Bool, false)
    }

    func testReflectionFilled() {
        let toBeFilled = Deferred<Int>()
        toBeFilled.fill(with: 42)

        let magicMirror = Mirror(reflecting: toBeFilled)
        XCTAssertEqual(magicMirror.displayStyle, .optional)
        XCTAssertNil(magicMirror.superclassMirror)
        XCTAssertEqual(magicMirror.descendant(0) as? Int, 42)
    }

    func testReflectionFilledWhenValueIsVoid() {
        let toBeFilled = Deferred<Void>()
        toBeFilled.fill(with: ())

        let magicMirror = Mirror(reflecting: toBeFilled)
        XCTAssertEqual(magicMirror.displayStyle, .optional)
        XCTAssertNil(magicMirror.superclassMirror)
        XCTAssertEqual(magicMirror.descendant("isFilled") as? Bool, true)
    }
}
