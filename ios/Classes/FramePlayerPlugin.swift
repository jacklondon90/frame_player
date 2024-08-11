import Flutter
import UIKit
import AVKit
import MediaPlayer



public class FramePlayerPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "frame_player", binaryMessenger: registrar.messenger())
        let instance = FramePlayerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let factory = SwiftPlayerFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "SwiftPlayer")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Handle method calls from Flutter
    }
}

public class SwiftPlayerFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    public func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return SwiftPlayer(frame: frame, viewId: viewId, args: args, messenger: messenger)
    }
}

public class SwiftPlayer: NSObject, FlutterPlatformView {
  
    private let frame: CGRect
    private let viewId: Int64
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private let methodChannel: FlutterMethodChannel
    private var containerView: UIView
    private var isThumbSeek: Bool = false
    private var isObserverAdded = false
    private var timeObserverToken: Any?
    private var isSliderBeingDragged = false

    init(frame: CGRect, viewId: Int64, args: Any?) {
        self.frame = frame
        self.viewId = viewId
        self.containerView = Self.createContainerView()
        self.methodChannel = FlutterMethodChannel(
            name: "fluff_view_channel_\(viewId)",
            binaryMessenger: (UIApplication.shared.delegate as! FlutterAppDelegate).window?.rootViewController as! FlutterBinaryMessenger
        )
        super.init()
        setupPlayer()
        setupAirPlayButton()
        methodChannel.setMethodCallHandler(handle)
        addPeriodicTimeObserver()
        fetchAudioAndSubtitles()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    public func view() -> UIView {
        return containerView
    }

    private static func createContainerView() -> UIView {
        let fixedWidth: CGFloat = UIScreen.main.bounds.width
        let fixedHeight: CGFloat = 300.0
        let xPos = (UIScreen.main.bounds.width - fixedWidth) / 2
        let yPos = (UIScreen.main.bounds.height - fixedHeight) / 3
        return UIView(frame: CGRect(x: xPos, y: yPos, width: fixedWidth, height: fixedHeight))
    }

    private func setupAirPlayButton() {
        let airplayButton = AVRoutePickerView(frame: CGRect(x: 20, y: 20, width: 44, height: 44))
        airplayButton.activeTintColor = .blue
        airplayButton.tintColor = .gray
        containerView.addSubview(airplayButton)
    }

    @objc private func orientationChanged() {
        updateContainerViewFrame()
    }

    private func updateContainerViewFrame() {
        let orientation = UIDevice.current.orientation
        containerView.frame = orientation.isLandscape ? UIScreen.main.bounds : Self.createContainerView().frame
        playerLayer?.frame = containerView.bounds
    }

    private func setupPlayer() {
        guard let videoUrl = URL(string: "https://files.etibor.uz/media/backup_beekeeper/master.m3u8") else {
            print("Failed to create URL for video")
            return
        }
        let asset = AVURLAsset(url: videoUrl)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 60
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player = AVPlayer(playerItem: playerItem)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = containerView.bounds
        playerLayer?.videoGravity = .resizeAspect
        if let playerLayer = playerLayer {
            containerView.layer.addSublayer(playerLayer)
        }
        addObserverToPlayerItem()
        player?.play()
        if let playerItem = player?.currentItem {
            setInitialAudioLanguage(playerItem: playerItem)
        }
    }

    private func setInitialAudioLanguage(playerItem: AVPlayerItem) {
        guard let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              let firstOption = mediaSelectionGroup.options.first else { return }
        playerItem.select(firstOption, in: mediaSelectionGroup)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "sendData":
            handleSendData(call: call, result: result)
        case "seekTo":
            handleSeekTo(call: call, result: result)
        case "fetchAudio":
            fetchAudioAndSubtitles()
            result(nil)
        case "fetchSubtitles":
            fetchSubtitles()
            result(nil)
        case "changeAudio":
            guard let args = call.arguments as? [String: Any], let language = args["language"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Language is missing", details: nil))
                return
            }
            changeAudio(language: language)
            result(nil)
        case "setPlaybackSpeed":
            guard let args = call.arguments as? [String: Any], let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Speed is missing", details: nil))
                return
            }
            setPlaybackSpeed(speed: speed)
            result(nil)
        case "changeVideoQuality":
            handleChangeVideoQuality(call: call, result: result)
        case "changeSubtitle":
            guard let args = call.arguments as? [String: Any], let language = args["language"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Language is missing", details: nil))
                return
            }
            changeSubtitle(language: language)
            result(nil)
        case "disposePlayer":
              dispose()
              result(nil)
        case "isSliderBeingDragged":
            if let args = call.arguments as? [String: Any], let isDragging = args["isDragging"] as? Bool {
                isSliderBeingDragged = isDragging
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }


    private func setPlaybackSpeed(speed: Double) {
        player?.rate = Float(speed)
    }

    private func addObserverToPlayerItem() {
        player?.currentItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new, .initial], context: nil)
        player?.currentItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new, .initial], context: nil)
        player?.currentItem?.addObserver(self, forKeyPath: "playbackBufferFull", options: [.new, .initial], context: nil)
        player?.currentItem?.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new, .initial], context: nil)
        player?.currentItem?.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)
        player?.currentItem?.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        isObserverAdded = true
    }

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "playbackBufferEmpty" {
            if let isBufferEmpty = change?[.newKey] as? Bool, isBufferEmpty {
                print("Buffer is empty. Loading more content...")
            }
        } else if keyPath == "playbackLikelyToKeepUp" {
            if let isLikelyToKeepUp = change?[.newKey] as? Bool, isLikelyToKeepUp {
                print("Buffer is likely to keep up. Resuming playback...")
                player?.play()
            }
        } else if keyPath == "playbackBufferFull" {
            if let isBufferFull = change?[.newKey] as? Bool, isBufferFull {
                print("Buffer is full. Resuming playback...")
                player?.play()
            }
        } else if keyPath == "loadedTimeRanges", let playerItem = object as? AVPlayerItem {
            if let timeRange = playerItem.loadedTimeRanges.first?.timeRangeValue {
                let bufferDuration = CMTimeGetSeconds(timeRange.end)
                sendBufferDurationToFlutter(bufferDuration: bufferDuration)
            }
        } else if keyPath == "duration", let duration = player?.currentItem?.duration.seconds, duration.isFinite {
            sendDurationToFlutter(duration: duration)
        } else if keyPath == "status", let playerItem = object as? AVPlayerItem, playerItem.status == .readyToPlay {
            let currentTime = player?.currentTime() ?? CMTime.zero
            player?.seek(to: currentTime) { [weak self] _ in
                self?.player?.play()
            }
        }
    }
    
    private func sendBufferDurationToFlutter(bufferDuration: Double) {
        methodChannel.invokeMethod("updateBuffer", arguments: "\(bufferDuration)") { result in
            if let error = result as? FlutterError {
                print("Failed to send buffer duration to Flutter: \(error.message ?? "")")
            } else {
                print("Buffer duration sent to Flutter: \(result ?? "nil")")
            }
        }
    }


    private func handleChangeVideoQuality(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let urlString = args["url"] as? String, let videoUrl = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URL is missing or invalid", details: nil))
            return
        }
        changeVideoQuality(url: videoUrl)
        result(nil)
    }
    private func getSelectedAudioTrack() -> AVMediaSelectionOption? {
        guard let playerItem = player?.currentItem else { return nil }
        let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        return playerItem.selectedMediaOption(in: mediaSelectionGroup!)
    }
    private func getSelectedSubtitleTrack() -> AVMediaSelectionOption? {
        guard let playerItem = player?.currentItem else { return nil }
        let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        return playerItem.selectedMediaOption(in: mediaSelectionGroup!)
    }

    private func changeVideoQuality(url: URL) {
        guard let player = player, let currentItem = player.currentItem else { return }

        let selectedAudioTrack = getSelectedAudioTrack()
        let selectedSubtitleTrack = getSelectedSubtitleTrack()

        let currentTime = player.currentTime()
        player.pause()
        removeObservers(from: currentItem)

        isThumbSeek = true

        let masterUrl = URL(string: "https://files.etibor.uz/media/backup_beekeeper/master.m3u8")!
        let newItem = AVPlayerItem(url: masterUrl)

        newItem.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "playbackBufferFull", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)
        newItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        isObserverAdded = true

        player.replaceCurrentItem(with: newItem)

      /*  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.selectAudioTrack(for: newItem)
            self.selectVideoQuality(for: newItem, qualityUrl: url)
            let timeScale = newItem.asset.duration.timescale
            let seekTime = CMTime(seconds: CMTimeGetSeconds(currentTime), preferredTimescale: timeScale)
            newItem.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.isThumbSeek = false
                self?.player?.play()
                if let playerItem = self?.player?.currentItem {
                    self?.setInitialAudioLanguage(playerItem: playerItem)
                }
            }
        }*/
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
             let timeScale = newItem.asset.duration.timescale
             let seekTime = CMTime(seconds: CMTimeGetSeconds(currentTime), preferredTimescale: timeScale)
             newItem.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                 self?.isThumbSeek = false
                 self?.player?.play()
                 self?.reapplyAudioTrack(selectedAudioTrack, to: newItem)
                 self?.reapplySubtitleTrack(selectedSubtitleTrack, to: newItem)

             }
         }
    }
    
    private func reapplyAudioTrack(_ selectedAudioTrack: AVMediaSelectionOption?, to playerItem: AVPlayerItem) {
        guard let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }

        if let selectedAudioTrack = selectedAudioTrack {
            playerItem.select(selectedAudioTrack, in: mediaSelectionGroup)
        } else if let defaultOption = mediaSelectionGroup.defaultOption {
            playerItem.select(defaultOption, in: mediaSelectionGroup)
        }
    }
    
    private func reapplySubtitleTrack(_ selectedSubtitleTrack: AVMediaSelectionOption?, to playerItem: AVPlayerItem) {
        guard let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }

        if let selectedSubtitleTrack = selectedSubtitleTrack {
            playerItem.select(selectedSubtitleTrack, in: mediaSelectionGroup)
        } else {
            playerItem.select(nil, in: mediaSelectionGroup)
        }
    }
    
    private func removeObservers(from playerItem: AVPlayerItem) {
        if isObserverAdded {
            playerItem.removeObserver(self, forKeyPath: "playbackBufferEmpty", context: nil)
            playerItem.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp", context: nil)
            playerItem.removeObserver(self, forKeyPath: "playbackBufferFull", context: nil)
            playerItem.removeObserver(self, forKeyPath: "loadedTimeRanges", context: nil)
            playerItem.removeObserver(self, forKeyPath: "duration", context: nil)
            playerItem.removeObserver(self, forKeyPath: "status", context: nil)
            isObserverAdded = false
        }
    }

    private func selectAudioTrack(for playerItem: AVPlayerItem) {
        guard let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }

        if let selectedOption = player?.currentItem?.selectedMediaOption(in: mediaSelectionGroup) {
            playerItem.select(selectedOption, in: mediaSelectionGroup)
        } else if let defaultOption = mediaSelectionGroup.defaultOption {
            playerItem.select(defaultOption, in: mediaSelectionGroup)
        }
    }

    private func selectVideoQuality(for playerItem: AVPlayerItem, qualityUrl: URL) {
        let groupOptions = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .visual)?.options ?? []

        for option in groupOptions {
            if let optionUrl = option.value(forKey: "url") as? String, optionUrl == qualityUrl.absoluteString {
                playerItem.select(option, in: playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .visual)!)
                break
            }
        }
    }

    private func handleSendData(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any], let data = args["data"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data is missing", details: nil))
            return
        }

        print("Received data from Flutter: \(data)")
        switch data {
        case "pause":
            player?.pause()
        case "play":
            player?.play()
        case "10+":
            seek(by: 10)
        case "10-":
            seek(by: -10)
        default:
            print("Unknown command")
        }

        let processedData = "Processed: \(data)"
        result(processedData)
    }

    private func handleSeekTo(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any], let value = args["value"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Value is missing", details: nil))
            return
        }

        onTapToSlide(value)
        print("Data received from Flutter slider: \(value)")
        result(nil)
    }

    private func seek(by seconds: Float64) {
        guard let currentTime = player?.currentTime() else { return }
        let seekTime = CMTime(seconds: CMTimeGetSeconds(currentTime) + seconds, preferredTimescale: 1)
        player?.seek(to: seekTime)
    }

    @objc private func onTapToSlide(_ value: Double) {
        isThumbSeek = true
        guard let duration = player?.currentItem?.duration else { return }
        let seekValue = value * CMTimeGetSeconds(duration)

        if !seekValue.isNaN {
            let seekTime = CMTime(seconds: seekValue, preferredTimescale: 1)
            player?.seek(to: seekTime) { [weak self] completed in
                if completed {
                    self?.isThumbSeek = false
                    self?.isSliderBeingDragged = false
                }
            }
        }
    }
    
    private func fetchAudioAndSubtitles() {
        fetchAudio { [weak self] in
            self?.fetchSubtitles()
        }
    }

    private func fetchAudio(completion: @escaping () -> Void) {
        guard let playerItem = player?.currentItem else {
            methodChannel.invokeMethod("updateAudio", arguments: []) { result in
                if let error = result as? FlutterError {
                    print("Failed to send audio tracks to Flutter: \(error.message ?? "")")
                } else {
                    print("Audio tracks sent to Flutter: \(result ?? "nil")")
                }
                completion()
            }
            return
        }

        var audioOptions: [String] = []
        if let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            for option in mediaSelectionGroup.options {
                if let locale = option.locale {
                    audioOptions.append(locale.identifier)
                } else {
                    audioOptions.append("Unknown")
                }
            }
        }

        methodChannel.invokeMethod("updateAudio", arguments: audioOptions) { result in
            if let error = result as? FlutterError {
                print("Failed to send audio tracks to Flutter: \(error.message ?? "")")
            } else {
                print("Audio tracks sent to Flutter successfully")
            }
            completion()
        }
    }
    
    private func fetchSubtitles() {
        guard let playerItem = player?.currentItem else {
            methodChannel.invokeMethod("updateSubtitles", arguments: []) { result in
                if let error = result as? FlutterError {
                    print("Failed to send subtitles to Flutter: \(error.message ?? "")")
                } else {
                    print("Subtitles sent to Flutter: \(result ?? "nil")")
                }
            }
            return
        }

        var subtitles: [String] = []
        if let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            for option in mediaSelectionGroup.options {
                if let locale = option.locale {
                    subtitles.append(locale.identifier)
                } else {
                    subtitles.append("Unknown")
                }
            }
        }

        methodChannel.invokeMethod("updateSubtitles", arguments: subtitles) { result in
            if let error = result as? FlutterError {
                print("Failed to send subtitles to Flutter: \(error.message ?? "")")
            } else {
                print("Subtitles sent to Flutter: \(result ?? "nil")")
            }
        }
    }
    private func changeSubtitle(language: String) {
        guard let playerItem = player?.currentItem, let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }

        for option in mediaSelectionGroup.options {
            if option.locale?.identifier == language {
                playerItem.select(option, in: mediaSelectionGroup)
                return
            }
        }
        playerItem.select(nil, in: mediaSelectionGroup)
    }


    private func changeAudio(language: String) {
        guard let playerItem = player?.currentItem, let mediaSelectionGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }

        for option in mediaSelectionGroup.options {
            if option.locale?.identifier == language {
                playerItem.select(option, in: mediaSelectionGroup)
                return
            }
        }
        playerItem.select(nil, in: mediaSelectionGroup)
    }

    private func sendDurationToFlutter(duration: Double) {
        methodChannel.invokeMethod("updateDuration", arguments: "\(duration)") { result in
            if let error = result as? FlutterError {
                print("Failed to send duration to Flutter: \(error.message ?? "")")
            } else {
                print("Duration sent to Flutter: \(result ?? "nil")")
            }
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isThumbSeek,!self.isSliderBeingDragged, let duration = self.player?.currentItem?.duration else { return }
            let currentTime = CMTimeGetSeconds(time)
            let durationTime = CMTimeGetSeconds(duration)
            let value = Float(currentTime / durationTime)
            self.sendDataToFlutter(data: "\(value)")
        }
    }

    private func sendDataToFlutter(data: String) {
        methodChannel.invokeMethod("updateSlider", arguments: data) { result in
            if let error = result as? FlutterError {
                print("Failed to send data to Flutter: \(error.message ?? "")")
            } else {
                print("Data sent to Flutter: \(result ?? "nil")")
            }
        }
    }
    
    public func dispose() {
        if let playerItem = player?.currentItem, isObserverAdded {
            removeObservers(from: playerItem)
        }
        if let observer = timeObserverToken {
            player?.removeTimeObserver(observer)
            timeObserverToken = nil
        }
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        print("Player disposed")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        if isObserverAdded {
            player?.currentItem?.removeObserver(self, forKeyPath: "duration")
            player?.currentItem?.removeObserver(self, forKeyPath: "status")
        }
        dispose()
    }

}
 