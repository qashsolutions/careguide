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
@MainActor
final class AudioManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = AudioManager()
    
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentlyPlayingId: UUID?
    @Published var recordingTime: TimeInterval = 0
    @Published var playbackTime: TimeInterval = 0
    @Published var audioLevel: Float = 0 // For visual feedback
    @Published var lastRecordingResult: RecordingResult? = nil // For auto-stop notification
    
    // MARK: - Constants
    private let maxRecordingDuration: TimeInterval = 60 // 1 minute
    private let updateInterval: TimeInterval = 0.1 // Update UI every 100ms
    
    // MARK: - Audio Components
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - File Management
    private var currentRecordingURL: URL?
    private var hasActiveSession = false
    
    private override init() {
        super.init()
        setupAudioSession()
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
    
    private func activateSessionIfNeeded() throws {
        guard !hasActiveSession else { return }
        try audioSession.setActive(true)
        hasActiveSession = true
    }
    
    // MARK: - Recording
    func startRecording() async throws -> URL {
        print("🧵 [AudioManager] startRecording called")
        print("🧵 [AudioManager] Actor context: @MainActor")
        
        print("🧵 [AudioManager] Step 1: Stopping playback")
        // Stop any existing playback
        stopPlayback()
        
        print("🧵 [AudioManager] Step 2: Requesting microphone permission")
        // Check microphone permission
        guard await requestMicrophonePermission() else {
            print("❌ [AudioManager] Microphone permission denied")
            throw AudioError.microphonePermissionDenied
        }
        print("✅ [AudioManager] Microphone permission granted")
        
        print("🧵 [AudioManager] Step 3: Creating file URL")
        // Create unique file URL
        let fileName = "memo_\(Date().timeIntervalSince1970).m4a"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let memosFolderURL = documentsPath.appendingPathComponent("CareMemos", isDirectory: true)
        
        print("🧵 [AudioManager] Step 4: Creating folder if needed")
        // Create folder if needed
        try? FileManager.default.createDirectory(at: memosFolderURL, withIntermediateDirectories: true)
        
        let fileURL = memosFolderURL.appendingPathComponent(fileName)
        currentRecordingURL = fileURL
        print("✅ [AudioManager] File URL created: \(fileURL.lastPathComponent)")
        
        print("🧵 [AudioManager] Step 5: Activating audio session")
        // Activate audio session only when needed
        try activateSessionIfNeeded()
        print("✅ [AudioManager] Audio session activated")
        
        print("🧵 [AudioManager] Step 6: Configuring recording settings")
        // Configure recording settings (optimized for voice)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050, // Lower sample rate for voice
            AVNumberOfChannelsKey: 1, // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32000 // 32kbps
        ]
        
        print("🧵 [AudioManager] Step 7: Creating AVAudioRecorder")
        // Create and start recorder
        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        print("✅ [AudioManager] AVAudioRecorder created")
        
        print("🧵 [AudioManager] Step 8: Setting up recorder")
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        print("🧵 [AudioManager] Step 9: Starting recording")
        audioRecorder?.record()
        print("✅ [AudioManager] Recording started")
        
        print("🧵 [AudioManager] Step 10: Updating state")
        isRecording = true
        recordingTime = 0
        
        print("🧵 [AudioManager] Step 11: Starting timer")
        // Start update timer
        startRecordingTimer()
        print("✅ [AudioManager] Timer started")
        
        print("✅ [AudioManager] startRecording completed successfully")
        return fileURL
    }
    
    func stopRecording() -> RecordingResult {
        print("🧵 [AudioManager] stopRecording called on thread: \(Thread.current)")
        print("🧵 [AudioManager] Is Main Thread: \(Thread.isMainThread)")
        
        // Capture duration BEFORE resetting
        let finalDuration = min(recordingTime, maxRecordingDuration)
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        audioRecorder = nil
        
        isRecording = false
        recordingTime = 0
        audioLevel = 0
        
        // Deactivate audio session if not playing
        if !isPlaying && hasActiveSession {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            hasActiveSession = false
        }
        
        return RecordingResult(url: currentRecordingURL, duration: finalDuration)
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.recordingTime += self.updateInterval
                
                // Update audio level for visual feedback
                self.audioRecorder?.updateMeters()
                self.audioLevel = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                
                // Auto-stop at max duration
                if self.recordingTime >= self.maxRecordingDuration {
                    let result = self.stopRecording()
                    // Publish the result so CareMemosView knows auto-stop happened
                    self.lastRecordingResult = result
                }
            }
        }
    }
    
    // MARK: - Playback
    func play(url: URL, memoId: UUID) throws {
        // Stop any existing playback
        stopPlayback()
        
        // Activate audio session only when needed
        try activateSessionIfNeeded()
        
        // Create player
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
        
        isPlaying = true
        currentlyPlayingId = memoId
        playbackTime = 0
        
        // Start update timer
        startPlaybackTimer()
    }
    
    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        isPlaying = false
        currentlyPlayingId = nil
        playbackTime = 0
        
        // Deactivate audio session if not recording
        if !isRecording && hasActiveSession {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            hasActiveSession = false
        }
    }
    
    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if let player = self.audioPlayer {
                    self.playbackTime = player.currentTime
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
    
    // MARK: - Cleanup
    func cleanup() {
        // Don't call stopRecording here - the view handles it before cleanup
        // This prevents recursive calls and duplicate operations
        
        // Stop any timers if still running
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop playback
        stopPlayback()
        
        // Only deactivate if we have an active session
        if hasActiveSession {
            // Use .notifyOthersOnDeactivation to notify other apps that audio is available
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            hasActiveSession = false
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