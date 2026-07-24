import AVFoundation
import CoreAudio
import Foundation

/// Records the Mac's system audio output — what DingTalk / Zoom / Tencent
/// Meeting play — via a Core Audio process tap. The tap sits on the mixed
/// output of every other process, so the far side of a call is captured
/// even when it only reaches headphones and never touches the microphone.
///
/// First use triggers the "System Audio Recording" privacy prompt
/// (NSAudioCaptureUsageDescription); if the user declines, `start` throws
/// and the caller falls back to microphone-only recording.
@available(macOS 15.0, *)
final class SystemAudioRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "com.shiftly.system-audio")

    struct TapError: LocalizedError {
        let stage: String
        let status: OSStatus
        var errorDescription: String? { "\(stage) (OSStatus \(status))" }
    }

    /// Side-track written next to the mic recording while both run;
    /// hidden so a crash never leaves a visible stray, and `MeetingStore`
    /// skips dotfiles when picking a meeting's audio.
    static func systemTrackURL(forMic url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(
            "." + url.deletingPathExtension().lastPathComponent + ".system.m4a"
        )
    }

    func start(writingTo url: URL) throws {
        // Global stereo mixdown of every process except Shiftly itself
        // (excluding ourselves avoids feeding notification sounds back in).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            throw TapError(stage: "create tap", status: status)
        }
        tapID = newTapID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            stop()
            throw TapError(stage: "read tap format", status: status)
        }

        // A private aggregate device whose only member is the tap gives us
        // a normal IOProc callback carrying the tapped buffers.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Shiftly System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else {
            stop()
            throw TapError(stage: "create aggregate device", status: status)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: asbd.mSampleRate,
                AVNumberOfChannelsKey: asbd.mChannelsPerFrame,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ],
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        self.file = file
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) {
            _, inInputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil
            ) else { return }
            try? file.write(from: buffer)
        }
        guard status == noErr, ioProcID != nil else {
            stop()
            throw TapError(stage: "create IO proc", status: status)
        }
        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            stop()
            throw TapError(stage: "start device", status: status)
        }
    }

    /// Stops and tears down; safe to call at any point, including from a
    /// failed `start`.
    func stop() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        file = nil
    }

    /// Mixes the hidden system track into the mic recording (one m4a under
    /// the mic file's name) and removes the side-track. Returns false when
    /// there was nothing usable to mix — the mic file stays as recorded.
    static func mix(mic: URL, system: URL) async -> Bool {
        defer { try? FileManager.default.removeItem(at: system) }
        guard FileManager.default.fileExists(atPath: system.path) else { return false }
        let composition = AVMutableComposition()
        var added = 0
        for url in [mic, system] {
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration),
                  duration > .zero,
                  let target = composition.addMutableTrack(
                      withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                  ),
                  (try? target.insertTimeRange(
                      CMTimeRange(start: .zero, duration: duration), of: track, at: .zero
                  )) != nil
            else { continue }
            added += 1
        }
        guard added == 2,
              let session = AVAssetExportSession(
                  asset: composition, presetName: AVAssetExportPresetAppleM4A
              )
        else { return false }
        let scratch = mic.deletingLastPathComponent().appendingPathComponent(".mixing.m4a")
        try? FileManager.default.removeItem(at: scratch)
        do {
            try await session.export(to: scratch, as: .m4a)
            _ = try FileManager.default.replaceItemAt(mic, withItemAt: scratch)
            return true
        } catch {
            try? FileManager.default.removeItem(at: scratch)
            return false
        }
    }
}
