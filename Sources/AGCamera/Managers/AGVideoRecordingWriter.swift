import AVFoundation
import CoreImage

// The recording queue owns writer state; the video queue owns frame conversion.
// Remove unchecked sendability when AVFoundation provides Sendable output and writer types.
final class AGVideoRecordingWriter: NSObject, @unchecked Sendable {
    let videoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()

    private let queue = DispatchQueue(label: "com.agcamera.recordingQueue", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.agcamera.videoProcessingQueue", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.agcamera.audioCaptureQueue", qos: .userInitiated)
    private let log: AGCameraLog
    private let context = CIContext()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstVideoSample: CMSampleBuffer?
    private var firstAudioSample: CMSampleBuffer?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var stopContinuation: CheckedContinuation<URL, Error>?
    private var outputURL: URL?
    private var requestedCodec: AVVideoCodecType?
    private var lastVideoTime: CMTime = .invalid
    private var lastAudioTime: CMTime = .invalid
    private var lastAudioEndTime: CMTime = .invalid
    private var lastCapturedAudioTime: CMTime = .invalid
    private var firstVideoTime: CMTime = .invalid
    private var firstAudioTime: CMTime = .invalid
    private var droppedAudioBuffers = 0
    private var pendingAudioSamples: [CMSampleBuffer] = []
    private var audioRetryScheduled = false
    private var videoWidth = 0
    private var videoHeight = 0
    private var isVideoPaused = false
    private var isFinishing = false
    private var isAwaitingAudioTail = false
    private var audioTailID: UUID?
    private var audioTailStartedAt = 0.0
    private var audioTailLastProgressAt = 0.0
    private var insertedSilenceFrames = 0
    private var startID: UUID?

    init(log: AGCameraLog) {
        self.log = log
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
    }

    func start(codec: AVVideoCodecType?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.startContinuation == nil, self.writer == nil, !self.isFinishing else {
                    continuation.resume(throwing: CameraError.recordingFailed)
                    return
                }
                self.outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                self.requestedCodec = codec
                self.startContinuation = continuation
                let startID = UUID()
                self.startID = startID
                self.queue.asyncAfter(deadline: .now() + 10) {
                    guard self.startID == startID, self.startContinuation != nil else { return }
                    self.failStart(CameraError.recordingFailed)
                }
            }
        }
    }

    func setVideoPaused(_ paused: Bool) async {
        await withCheckedContinuation { continuation in
            if paused {
                queue.async {
                    self.isVideoPaused = true
                    continuation.resume()
                }
            } else {
                videoQueue.async {
                    self.queue.async {
                        self.isVideoPaused = false
                        continuation.resume()
                    }
                }
            }
        }
    }

    func stop() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let writer = self.writer, !self.isFinishing, self.stopContinuation == nil else {
                    continuation.resume(throwing: CameraError.recordingFailed)
                    return
                }
                guard writer.status == .writing else {
                    let error = writer.error ?? CameraError.recordingFailed
                    self.discardOutput()
                    self.reset()
                    continuation.resume(throwing: error)
                    return
                }
                self.isFinishing = true
                self.stopContinuation = continuation
                self.videoInput?.markAsFinished()
                if self.lastVideoTime.isValid,
                   !self.pendingAudioSamples.isEmpty || !self.lastAudioTime.isValid || self.lastAudioTime < self.lastVideoTime {
                    self.isAwaitingAudioTail = true
                    self.audioTailStartedAt = ProcessInfo.processInfo.systemUptime
                    self.audioTailLastProgressAt = self.audioTailStartedAt
                    let tailID = UUID()
                    self.audioTailID = tailID
                    self.checkAudioTail(id: tailID)
                } else {
                    self.finishWriting()
                }
            }
        }
    }

    private func checkAudioTail(id: UUID) {
        guard audioTailID == id, isAwaitingAudioTail else { return }
        drainAudio()
        guard audioTailID == id, isAwaitingAudioTail else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - audioTailStartedAt >= 6 || now - audioTailLastProgressAt >= 2 {
            let remaining = lastVideoTime.isValid && lastAudioTime.isValid
                ? (lastVideoTime - lastAudioTime).seconds : .nan
            log.warning(
                "Recording audio tail stopped with \(String(format: "%.3f", remaining))s remaining; " +
                "queued buffers: \(pendingAudioSamples.count)",
                category: "VideoWriter"
            )
            finishWriting()
            return
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) {
            self.checkAudioTail(id: id)
        }
    }

    private func finishWriting() {
        guard isAwaitingAudioTail || stopContinuation != nil,
              let writer else { return }
        isAwaitingAudioTail = false
        audioTailID = nil
        if !pendingAudioSamples.isEmpty {
            log.warning("Recording closed with \(pendingAudioSamples.count) queued audio buffers", category: "VideoWriter")
            pendingAudioSamples.removeAll()
        }
        audioInput?.markAsFinished()
        writer.finishWriting {
            self.queue.async {
                self.reportTiming()
                let result: Result<URL, Error>
                if writer.status == .completed, let url = self.outputURL {
                    result = .success(url)
                } else {
                    result = .failure(writer.error ?? CameraError.recordingFailed)
                    self.discardOutput()
                }
                self.stopContinuation?.resume(with: result)
                self.stopContinuation = nil
                self.reset()
            }
        }
    }

    private func beginWriting() {
        guard let videoSample = firstVideoSample,
              let audioSample = firstAudioSample,
              let videoFormat = CMSampleBufferGetFormatDescription(videoSample),
              let audioFormat = CMSampleBufferGetFormatDescription(audioSample),
              let url = outputURL else { return }

        do {
            let dimensions = CMVideoFormatDescriptionGetDimensions(videoFormat)
            guard dimensions.width > 0, dimensions.height > 0,
                  var videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) else {
                throw CameraError.recordingFailed
            }
            videoSettings[AVVideoWidthKey] = Int(dimensions.width)
            videoSettings[AVVideoHeightKey] = Int(dimensions.height)
            if let requestedCodec {
                videoSettings[AVVideoCodecKey] = requestedCodec
            }

            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            guard writer.canApply(outputSettings: videoSettings, forMediaType: .video),
                  writer.canApply(outputSettings: nil, forMediaType: .audio) else {
                throw CameraError.invalidConfiguration
            }
            let videoInput = AVAssetWriterInput(
                mediaType: .video, outputSettings: videoSettings, sourceFormatHint: videoFormat
            )
            let audioInput = AVAssetWriterInput(
                mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat
            )
            videoInput.expectsMediaDataInRealTime = true
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
                throw CameraError.recordingFailed
            }
            writer.add(videoInput)
            writer.add(audioInput)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: Int(dimensions.width),
                    kCVPixelBufferHeightKey as String: Int(dimensions.height)
                ]
            )
            guard writer.startWriting() else {
                throw writer.error ?? CameraError.recordingFailed
            }
            let videoTime = CMSampleBufferGetPresentationTimeStamp(videoSample)
            let audioTime = CMSampleBufferGetPresentationTimeStamp(audioSample)
            guard videoTime.isValid, audioTime.isValid else {
                throw CameraError.recordingFailed
            }
            let startTime = min(videoTime, audioTime)
            writer.startSession(atSourceTime: startTime)
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.pixelBufferAdaptor = adaptor
            videoWidth = Int(dimensions.width)
            videoHeight = Int(dimensions.height)
            guard appendVideo(videoSample) else {
                throw writer.error ?? CameraError.recordingFailed
            }
            appendAudio(audioSample)
            firstVideoSample = nil
            firstAudioSample = nil
            startContinuation?.resume(returning: url)
            startContinuation = nil
            startID = nil
        } catch {
            failStart(error)
        }
    }

    @discardableResult
    private func appendVideo(_ sample: CMSampleBuffer) -> Bool {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return false }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        return appendVideoBuffer(imageBuffer, at: time)
    }

    @discardableResult
    private func appendVideoBuffer(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard let writer, writer.status == .writing,
              !isVideoPaused,
              let videoInput, videoInput.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor,
              time.isValid, !lastVideoTime.isValid || time > lastVideoTime else { return false }
        let didAppend = adaptor.append(buffer, withPresentationTime: time)
        if didAppend {
            if !firstVideoTime.isValid { firstVideoTime = time }
            lastVideoTime = time
        }
        return didAppend
    }

    private func processVideo(_ sample: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let state = queue.sync { () -> (CVPixelBufferPool?, Int, Int, UUID?) in
            let pool = !isFinishing && !isVideoPaused && writer?.status == .writing
                ? pixelBufferAdaptor?.pixelBufferPool : nil
            return (pool, videoWidth, videoHeight, startID)
        }
        let (pool, width, height, pendingStartID) = state
        guard let pool else {
            guard let pendingStartID else { return }
            queue.async {
                guard self.startID == pendingStartID, self.startContinuation != nil else { return }
                self.firstVideoSample = sample
                self.beginWriting()
            }
            return
        }

        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if CVPixelBufferGetWidth(imageBuffer) == width,
           CVPixelBufferGetHeight(imageBuffer) == height {
            queue.async { self.appendVideoBuffer(imageBuffer, at: time) }
            return
        }

        var outputBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
              let outputBuffer else { return }
        let source = CIImage(cvPixelBuffer: imageBuffer)
        guard source.extent.width > 0, source.extent.height > 0 else { return }
        let scale = max(CGFloat(width) / source.extent.width, CGFloat(height) / source.extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(by: CGAffineTransform(
            translationX: (CGFloat(width) - scaled.extent.width) / 2 - scaled.extent.minX,
            y: (CGFloat(height) - scaled.extent.height) / 2 - scaled.extent.minY
        ))
        context.render(centered, to: outputBuffer)
        queue.async { self.appendVideoBuffer(outputBuffer, at: time) }
    }

    private func appendAudio(_ sample: CMSampleBuffer) {
        guard let writer, writer.status == .writing,
              audioInput != nil else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time.isValid,
              (!lastCapturedAudioTime.isValid || time > lastCapturedAudioTime) else {
            droppedAudioBuffers += 1
            return
        }
        lastCapturedAudioTime = time
        if pendingAudioSamples.count >= 32 {
            pendingAudioSamples.removeFirst()
            droppedAudioBuffers += 1
        }
        pendingAudioSamples.append(sample)
        drainAudio()
    }

    private func drainAudio() {
        guard let writer, writer.status == .writing,
              let audioInput else { return }
        while !pendingAudioSamples.isEmpty && audioInput.isReadyForMoreMediaData {
            let sample = pendingAudioSamples[0]
            guard appendSilenceIfNeeded(before: sample, to: audioInput),
                  audioInput.isReadyForMoreMediaData else { break }
            pendingAudioSamples.removeFirst()
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard (!lastAudioTime.isValid || time > lastAudioTime),
                  audioInput.append(sample) else {
                droppedAudioBuffers += 1
                continue
            }
            if !firstAudioTime.isValid { firstAudioTime = time }
            lastAudioTime = time
            if isAwaitingAudioTail {
                audioTailLastProgressAt = ProcessInfo.processInfo.systemUptime
            }
            let duration = CMSampleBufferGetDuration(sample)
            lastAudioEndTime = duration.isValid ? time + duration : time
        }
        if !pendingAudioSamples.isEmpty, !audioRetryScheduled {
            audioRetryScheduled = true
            queue.asyncAfter(deadline: .now() + .milliseconds(20)) {
                self.audioRetryScheduled = false
                self.drainAudio()
            }
        }
        if isAwaitingAudioTail, pendingAudioSamples.isEmpty,
           lastAudioTime.isValid, lastVideoTime.isValid,
           lastAudioTime >= lastVideoTime {
            finishWriting()
        }
    }

    private func appendSilenceIfNeeded(
        before sample: CMSampleBuffer,
        to audioInput: AVAssetWriterInput
    ) -> Bool {
        guard lastAudioEndTime.isValid,
              let format = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaSubType(format) == kAudioFormatLinearPCM,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mSampleRate > 0,
              description.mBytesPerFrame > 0 else { return true }

        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sample)
        let sampleRate = CMTimeScale(description.mSampleRate.rounded())
        let isNonInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = isNonInterleaved ? Int(description.mChannelsPerFrame) : 1
        let bytesPerFrame = Int(description.mBytesPerFrame)
        guard sampleRate > 0, channels > 0 else { return true }

        while audioInput.isReadyForMoreMediaData {
            let gap = (sampleTime - lastAudioEndTime).seconds
            guard gap > 1 / Double(sampleRate) else { return true }
            let frames = min(Int((gap * Double(sampleRate)).rounded(.down)), Int(sampleRate / 4))
            guard frames > 0 else { return true }
            let byteCount = frames * bytesPerFrame * channels
            var blockBuffer: CMBlockBuffer?
            let blockStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard blockStatus == kCMBlockBufferNoErr, let blockBuffer,
                  CMBlockBufferFillDataBytes(
                    with: 0,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: byteCount
                  ) == kCMBlockBufferNoErr else { return false }

            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: sampleRate),
                presentationTimeStamp: lastAudioEndTime,
                decodeTimeStamp: .invalid
            )
            var sampleSize = bytesPerFrame
            var silence: CMSampleBuffer?
            let sampleStatus = withUnsafePointer(to: &timing) { timingPointer in
                withUnsafePointer(to: &sampleSize) { sizePointer in
                    CMSampleBufferCreateReady(
                        allocator: kCFAllocatorDefault,
                        dataBuffer: blockBuffer,
                        formatDescription: format,
                        sampleCount: frames,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: timingPointer,
                        sampleSizeEntryCount: isNonInterleaved ? 0 : 1,
                        sampleSizeArray: isNonInterleaved ? nil : sizePointer,
                        sampleBufferOut: &silence
                    )
                }
            }
            guard sampleStatus == noErr, let silence, audioInput.append(silence) else {
                return false
            }
            insertedSilenceFrames += frames
            lastAudioTime = lastAudioEndTime
            lastAudioEndTime = lastAudioEndTime + CMTime(value: Int64(frames), timescale: sampleRate)
        }
        return false
    }

    private func reportTiming() {
        if firstVideoTime.isValid, firstAudioTime.isValid {
            let startOffset = (firstAudioTime - firstVideoTime).seconds
            log.info(
                "Recording audio/video start timestamp offset: \(String(format: "%.3f", startOffset))s",
                category: "VideoWriter"
            )
        }
        if lastVideoTime.isValid, lastAudioEndTime.isValid {
            let endOffset = (lastAudioEndTime - lastVideoTime).seconds
            log.info(
                "Recording audio/video end timestamp offset: \(String(format: "%.3f", endOffset))s",
                category: "VideoWriter"
            )
        }
        if lastVideoTime.isValid, lastCapturedAudioTime.isValid {
            let sourceOffset = (lastCapturedAudioTime - lastVideoTime).seconds
            log.info(
                "Recording last captured audio/video timestamp offset: \(String(format: "%.3f", sourceOffset))s",
                category: "VideoWriter"
            )
        }
        if droppedAudioBuffers > 0 {
            log.warning("Recording dropped \(droppedAudioBuffers) audio buffers", category: "VideoWriter")
        }
        if insertedSilenceFrames > 0 {
            log.info("Recording inserted \(insertedSilenceFrames) silent audio frames across capture gaps", category: "VideoWriter")
        }
    }

    private func failStart(_ error: Error) {
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        writer?.cancelWriting()
        discardOutput()
        reset()
    }

    private func discardOutput() {
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        firstVideoSample = nil
        firstAudioSample = nil
        outputURL = nil
        requestedCodec = nil
        lastVideoTime = .invalid
        lastAudioTime = .invalid
        lastAudioEndTime = .invalid
        lastCapturedAudioTime = .invalid
        firstVideoTime = .invalid
        firstAudioTime = .invalid
        droppedAudioBuffers = 0
        pendingAudioSamples.removeAll()
        audioRetryScheduled = false
        videoWidth = 0
        videoHeight = 0
        isVideoPaused = false
        isFinishing = false
        isAwaitingAudioTail = false
        audioTailID = nil
        audioTailStartedAt = 0
        audioTailLastProgressAt = 0
        insertedSilenceFrames = 0
        startID = nil
    }
}

extension AGVideoRecordingWriter: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === videoOutput {
            processVideo(sampleBuffer)
        } else if output === audioOutput {
            queue.async {
                guard !self.isFinishing || self.isAwaitingAudioTail else { return }
                if self.startContinuation != nil {
                    self.firstAudioSample = sampleBuffer
                    self.beginWriting()
                } else {
                    self.appendAudio(sampleBuffer)
                }
            }
        }
    }
}
