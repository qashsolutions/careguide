//
//  AudioManager.swift
//  HealthGuide
//
//  Singleton audio manager for CareMemos
//  Production-ready with memory management and single player constraint
//

import SwiftUI
import AVFoundation
import Combine

@available(iOS 18.0, *)
final class AudioManager: NSObject, ObservableObject, @unchecked Sendable {
    
    // MARK: - Singleton
    static let shared = AudioManager()
    
    // MARK: - Published State (UI updates on MainActor)
    @MainActor @Published private(set) var isRecording = false
    @MainActor @Published private(set) var isPlaying = false
    @MainActor @Published var currentlyPlayingId: UUID?
    @MainActor @Published private(set) var recordingTime: TimeInterval = 0
    @MainActor @Published private(set) var playbackTime: TimeInterval = 0
    @MainActor @Published private(set) var audioLevel: Float = 0 // For visual feedback
    @MainActor @Published var lastRecordingResult: RecordingResult? = nil // For auto-stop notification
    
    // MARK: - Constants
    private let maxRecordingDuration: TimeInterval = 60 // 1 minute
    private let updateInterval: TimeInterval = 0.1 // Update UI every 100ms
    
    // MARK: - Audio Components (accessed only on audioQueue)
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private let audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - File Management
    private var currentRecordingURL: URL?
    private var hasActiveSession = false
    private var recordingStartTime: Date? // Track recording time on audio queue
    
    // MARK: - Dedicated Audio Queue
    private let audioQueue = DispatchQueue(label: "com.healthguide.audio", qos: .userInitiated)
    
    private override init() {
        super.init()
        // Setup audio session on audio queue
        audioQueue.async { [weak self] in
            self?.setupAudioSession()
        }
        
        // Listen for app lifecycle to clean up when backgrounded
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    // MARK: - Setup
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            // Don't activate session here - only configure it
            // Session will be activated when actually needed (recording/playback)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // This method is removed - activation is now done inline on audioQueue
    
    // MARK: - Recording
    func startRecording() async throws -> URL {
        print("🧵 [AudioManager] startRecording called")
        
        // Check microphone permission first (can be done on any thread)
        guard await requestMicrophonePermission() else {
            print("❌ [AudioManager] Microphone permission denied")
            throw AudioError.microphonePermissionDenied
        }
        
        // All audio operations must happen on the audio queue
        return try await withCheckedThrowingContinuation { continuation in
            audioQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: AudioError.recordingFailed)
                    return
                }
                
                do {
                    print("🧵 [AudioManager] On audio queue: \(Thread.current)")
                    
                    // Stop any existing playback (on audio queue)
                    self.stopPlaybackInternal()
                    
                    // Create unique file URL
                    let fileName = "memo_\(Date().timeIntervalSince1970).m4a"
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let memosFolderURL = documentsPath.appendingPathComponent("CareMemos", isDirectory: true)
                    
                    // Create folder if needed
                    try? FileManager.default.createDirectory(at: memosFolderURL, withIntermediateDirectories: true)
                    
                    let fileURL = memosFolderURL.appendingPathComponent(fileName)
                    self.currentRecordingURL = fileURL
                    
                    // Configure audio session (on audio queue)
                    if !self.hasActiveSession {
                        try self.audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                        try self.audioSession.setActive(true)
                        self.hasActiveSession = true
                    }
                    
                    // Configure recording settings
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 22050,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                        AVEncoderBitRateKey: 32000
                    ]
                    
                    // Create and configure recorder (on audio queue)
                    let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
                    recorder.delegate = self
                    recorder.isMeteringEnabled = true
                    recorder.prepareToRecord()
                    
                    // Store and start recording
                    self.audioRecorder = recorder
                    self.recordingStartTime = Date() // Track start time on audio queue
                    recorder.record()
                    
                    // Update UI state on MainActor
                    Task { @MainActor in
                        self.isRecording = true
                        self.recordingTime = 0
                        self.startRecordingTimer()
                    }
                    
                    print("✅ [AudioManager] Recording started successfully")
                    continuation.resume(returning: fileURL)
                    
                } catch {
                    print("❌ [AudioManager] Recording failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func stopRecording() -> RecordingResult {
        print("🧵 [AudioManager] stopRecording called")
        
        // All operations on audio queue
        return audioQueue.sync { [weak self] in
            guard let self = self else {
                return RecordingResult(url: nil, duration: 0)
            }
            
            // Calculate duration from start time (tracked on audio queue)
            let finalDuration: TimeInterval
            if let startTime = self.recordingStartTime {
                finalDuration = min(Date().timeIntervalSince(startTime), self.maxRecordingDuration)
            } else {
                finalDuration = 0
            }
            
            // Stop recorder on audio queue
            self.audioRecorder?.stop()
            let url = self.currentRecordingURL
            self.audioRecorder = nil
            self.recordingStartTime = nil
            
            // Deactivate audio session (check if player exists on audio queue)
            if self.hasActiveSession && self.audioPlayer == nil {
                try? self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                self.hasActiveSession = false
            }
            
            // Update UI state on MainActor
            Task { @MainActor in
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.isRecording = false
                self.recordingTime = 0
                self.audioLevel = 0
            }
            
            return RecordingResult(url: url, duration: finalDuration)
        }
    }
    
    // Internal helper for stopping playback on audio queue
    private func stopPlaybackInternal() {
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        
        Task { @MainActor in
            self.playbackTimer?.invalidate()
            self.playbackTimer = nil
            self.isPlaying = false
            self.currentlyPlayingId = nil
            self.playbackTime = 0
        }
    }
    
    @MainActor
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.recordingTime += self.updateInterval
                
                // Get audio level from recorder on audio queue
                self.audioQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.audioRecorder?.updateMeters()
                    let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                    
                    Task { @MainActor in
                        self.audioLevel = level
                    }
                }
                
                // Auto-stop at max duration
                if self.recordingTime >= self.maxRecordingDuration {
                    let result = self.stopRecording()
                    self.lastRecordingResult = result
                }
            }
        }
    }
    
    // MARK: - Playback
    func play(url: URL, memoId: UUID) throws {
        // Check if this is a remote URL (Firebase Storage)
        if url.scheme == "https" || url.scheme == "http" {
            // Handle remote URL by downloading first
            Task {
                await playRemoteAudio(url: url, memoId: memoId)
            }
        } else {
            // Handle local file URL
            try playLocalAudio(url: url, memoId: memoId)
        }
    }
    
    private func playLocalAudio(url: URL, memoId: UUID) throws {
        // All audio operations on audio queue
        try audioQueue.sync { [weak self] in
            guard let self = self else { throw AudioError.playbackFailed }
            
            // Stop any existing playback
            self.stopPlaybackInternal()
            
            // Configure audio session
            if !self.hasActiveSession {
                try self.audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try self.audioSession.setActive(true)
                self.hasActiveSession = true
            }
            
            // Create and configure player on audio queue
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.audioPlayer = player
            player.play()
            
            // Update UI state on MainActor
            Task { @MainActor in
                self.isPlaying = true
                self.currentlyPlayingId = memoId
                self.playbackTime = 0
                self.startPlaybackTimer()
            }
        }
    }
    
    private func playRemoteAudio(url: URL, memoId: UUID) async {
        do {
            print("📥 Downloading audio from Firebase Storage: \(url)")
            
            // Download the audio data
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Save to temporary file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            
            try data.write(to: tempURL)
            
            // Play the downloaded file
            try playLocalAudio(url: tempURL, memoId: memoId)
            
            print("✅ Successfully playing Firebase audio memo")
            
            // Clean up temp file after playback finishes
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Wait 5 seconds
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("❌ Failed to play remote audio: \(error)")
            Task { @MainActor in
                self.isPlaying = false
                self.currentlyPlayingId = nil
            }
        }
    }
    
    func stopPlayback() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            // Deactivate audio session if not recording
            Task { @MainActor in
                let shouldDeactivate = !self.isRecording
                if shouldDeactivate && self.hasActiveSession {
                    self.audioQueue.async {
                        try? self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                        self.hasActiveSession = false
                    }
                }
            }
            
            Task { @MainActor in
                self.playbackTimer?.invalidate()
                self.playbackTimer = nil
                self.isPlaying = false
                self.currentlyPlayingId = nil
                self.playbackTime = 0
            }
        }
    }
    
    @MainActor
    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.audioQueue.async { [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                let currentTime = player.currentTime
                let duration = player.duration
                
                Task { @MainActor in
                    self.playbackTime = currentTime
                    
                    // Check if playback finished
                    if currentTime >= duration {
                        self.stopPlayback()
                    }
                }
            }
        }
    }
    
    // MARK: - Permissions
    private func requestMicrophonePermission() async -> Bool {
        print("🧵 [AudioManager] requestMicrophonePermission called")
        print("🧵 [AudioManager] Using AVAudioApplication API")
        
        // Use AVAudioApplication's completion handler version for iOS 17+
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - App Lifecycle
    
    @objc private func appDidEnterBackground() {
        print("🔊 AudioManager: App entering background - stopping all audio")
        // Stop any ongoing recording or playback
        _ = stopRecording()
        stopPlayback()
        cleanup()
    }
    
    // MARK: - Cleanup
    func cleanup() {
        // Clean up on audio queue
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Stop any audio operations
            self.audioRecorder?.stop()
            self.audioRecorder = nil
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            // Deactivate session
            if self.hasActiveSession {
                try? self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                self.hasActiveSession = false
            }
            
            Task { @MainActor in
                // Clean up UI state
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.playbackTimer?.invalidate()
                self.playbackTimer = nil
                self.isRecording = false
                self.isPlaying = false
                self.currentlyPlayingId = nil
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate
@available(iOS 18.0, *)
extension AudioManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("🧵 [AudioManager] audioRecorderDidFinishRecording on thread: \(Thread.current)")
        print("🧵 [AudioManager] Is Main Thread: \(Thread.isMainThread)")
        
        Task { @MainActor in
            if !flag {
                print("❌ Recording failed")
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate  
@available(iOS 18.0, *)
extension AudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🧵 [AudioManager] audioPlayerDidFinishPlaying on thread: \(Thread.current)")
        print("🧵 [AudioManager] Is Main Thread: \(Thread.isMainThread)")
        
        Task { @MainActor in
            stopPlayback()
        }
    }
}

// MARK: - Recording Result
@available(iOS 18.0, *)
struct RecordingResult: Equatable {
    let url: URL?
    let duration: TimeInterval
}

// MARK: - Audio Errors
@available(iOS 18.0, *)
enum AudioError: LocalizedError {
    case microphonePermissionDenied
    case recordingFailed
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to record memos"
        case .recordingFailed:
            return "Failed to record audio"
        case .playbackFailed:
            return "Failed to play audio"
        }
    }
}