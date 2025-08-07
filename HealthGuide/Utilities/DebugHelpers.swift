//
//  DebugHelpers.swift
//  HealthGuide
//
//  Debugging utilities to identify threading issues
//

import Foundation

/// Thread safety debugging helpers
struct ThreadChecker {
    
    /// Verify we're on the main thread
    static func assertMainThread(file: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        assert(Thread.isMainThread, "[\(file):\(line)] \(function) must be called on main thread")
        #endif
    }
    
    /// Verify we're NOT on the main thread
    static func assertBackgroundThread(file: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        assert(!Thread.isMainThread, "[\(file):\(line)] \(function) must be called on background thread")
        #endif
    }
    
    /// Log current thread info
    static func logThread(context: String, file: String = #file, line: Int = #line) {
        #if DEBUG
        let threadName = Thread.current.name ?? "unnamed"
        let isMain = Thread.isMainThread ? "MAIN" : "BACKGROUND"
        print("🧵 [\(isMain)] \(context) - Thread: \(threadName) at \(file):\(line)")
        #endif
    }
}

/// Dispatch queue debugging
extension DispatchQueue {
    
    /// Assert we're on the main queue
    static func assertMain(file: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(.main))
        #endif
    }
    
    /// Assert we're NOT on the main queue
    static func assertNotMain(file: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
    }
}