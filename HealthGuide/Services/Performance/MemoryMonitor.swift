//
//  MemoryMonitor.swift
//  HealthGuide
//
//  Production-ready memory monitoring and optimization
//

import Foundation
import UIKit
import os.log

@available(iOS 18.0, *)
@MainActor
final class MemoryMonitor: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MemoryMonitor()
    
    // MARK: - Published Properties
    @Published var currentMemoryUsage: Double = 0
    @Published var memoryWarningLevel: MemoryWarningLevel = .normal
    @Published var isLowMemory: Bool = false
    
    // MARK: - Memory Warning Levels
    enum MemoryWarningLevel {
        case normal
        case warning
        case critical
        
        var color: UIColor {
            switch self {
            case .normal: return .systemGreen
            case .warning: return .systemYellow
            case .critical: return .systemRed
            }
        }
        
        var message: String {
            switch self {
            case .normal: return "Memory usage normal"
            case .warning: return "Memory usage high"
            case .critical: return "Critical memory warning"
            }
        }
    }
    
    // MARK: - Private Properties
    private let logger = os.Logger(subsystem: "com.healthguide.app", category: "MemoryMonitor")
    private var memoryTimer: Timer?
    private let memoryThresholdMB: Double = 200 // Alert if app uses more than 200MB
    private let criticalThresholdMB: Double = 300 // Critical if more than 300MB
    
    // MARK: - Initialization
    private init() {
        setupMemoryMonitoring()
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupMemoryMonitoring() {
        // DISABLED - Timer causing high CPU usage
        // Only check memory on app lifecycle events and warnings
        /*
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in
                self.checkMemoryUsage()
            }
        }
        */
        
        // Initial check only
        checkMemoryUsage()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    // MARK: - Memory Monitoring
    
    func checkMemoryUsage() {
        let memoryUsage = getCurrentMemoryUsage()
        currentMemoryUsage = memoryUsage
        
        // Update warning level
        if memoryUsage > criticalThresholdMB {
            memoryWarningLevel = .critical
            isLowMemory = true
            #if DEBUG
            logger.critical("Critical memory usage: \(memoryUsage, format: .fixed(precision: 2))MB")
            #endif
            performEmergencyCleanup()
        } else if memoryUsage > memoryThresholdMB {
            memoryWarningLevel = .warning
            isLowMemory = true
            #if DEBUG
            logger.warning("High memory usage: \(memoryUsage, format: .fixed(precision: 2))MB")
            #endif
            performMemoryCleanup()
        } else {
            memoryWarningLevel = .normal
            isLowMemory = false
        }
        
        // Disabled debug logging to reduce overhead
        // #if DEBUG
        // print("💾 Memory: \(String(format: "%.2f", memoryUsage))MB - \(memoryWarningLevel.message)")
        // #endif
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / 1024.0 / 1024.0
            return usedMemoryMB
        }
        
        return 0
    }
    
    // MARK: - Memory Cleanup
    
    @objc private func handleMemoryWarning() {
        logger.warning("System memory warning received")
        isLowMemory = true
        memoryWarningLevel = .critical
        performEmergencyCleanup()
    }
    
    func performMemoryCleanup() {
        logger.info("Performing memory cleanup...")
        
        // 1. Clear image caches
        URLCache.shared.removeAllCachedResponses()
        
        // 2. Clear temporary files
        clearTemporaryFiles()
        
        // 3. Post notification for other components to clean up
        NotificationCenter.default.post(
            name: Notification.Name("PerformMemoryCleanup"),
            object: nil
        )
        
        // 4. Trim Core Data memory
        PersistenceController.shared.trimMemory()
    }
    
    func performEmergencyCleanup() {
        logger.critical("Performing emergency memory cleanup...")
        
        // Aggressive cleanup
        performMemoryCleanup()
        
        // Clear all caches
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0
        
        // Force garbage collection (if available)
        autoreleasepool {
            // Force autorelease pool drain
        }
        
        // Restore minimal cache after emergency
        URLCache.shared.memoryCapacity = 10 * 1024 * 1024 // 10MB after cleanup
    }
    
    private func clearTemporaryFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDirectory, 
                                                                   includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            logger.info("Cleared \(files.count) temporary files")
        } catch {
            logger.error("Failed to clear temp files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - App Lifecycle
    
    @objc private func appDidEnterBackground() {
        // Reduce memory footprint when backgrounded
        performMemoryCleanup()
        memoryTimer?.invalidate()
    }
    
    @objc private func appWillTerminate() {
        memoryTimer?.invalidate()
    }
    
    // MARK: - Analytics
    
    func getMemoryReport() -> MemoryReport {
        let totalMemory = ProcessInfo.processInfo.physicalMemory / 1024 / 1024 // MB
        let currentUsage = getCurrentMemoryUsage()
        let percentUsed = (currentUsage / Double(totalMemory)) * 100
        
        return MemoryReport(
            currentUsageMB: currentUsage,
            totalDeviceMemoryMB: Double(totalMemory),
            percentageUsed: percentUsed,
            warningLevel: memoryWarningLevel
        )
    }
    
    // MARK: - Cleanup
    
    /// Cleanup resources
    func cleanup() {
        memoryTimer?.invalidate()
        memoryTimer = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Deinit
    
    deinit {
        // Can't access MainActor-isolated properties from deinit
        // Cleanup should be called explicitly when needed
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, *)
struct MemoryReport {
    let currentUsageMB: Double
    let totalDeviceMemoryMB: Double
    let percentageUsed: Double
    let warningLevel: MemoryMonitor.MemoryWarningLevel
    
    var formattedUsage: String {
        String(format: "%.1fMB / %.0fMB (%.1f%%)", 
               currentUsageMB, 
               totalDeviceMemoryMB, 
               percentageUsed)
    }
}

// MARK: - PersistenceController Extension

extension PersistenceController {
    func trimMemory() {
        container.viewContext.refreshAllObjects()
        
        // Reset fetch batch size for better memory management
        container.viewContext.stalenessInterval = 30.0
        
        // Clear undo manager
        container.viewContext.undoManager = nil
    }
}