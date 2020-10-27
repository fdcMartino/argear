//
//  ViewController.swift
//  ARGearSample
//
//  Created by Jaecheol Kim on 2019/10/28.
//  Copyright © 2019 Seerslab. All rights reserved.
//

import UIKit
import CoreMedia
import SceneKit
import AVFoundation
import ARGear
import RealmSwift
import HaishinKit

public final class MainViewController: UIViewController {

    var toast_main_position = CGPoint(x: 0, y: 0)

    // MARK: - ARGearSDK properties
    private var argConfig: ARGConfig?
    private var argSession: ARGSession?
    private var currentFaceFrame: ARGFrame?
    private var nextFaceFrame: ARGFrame?
    private var preferences: ARGPreferences = ARGPreferences()

    // - views
    @IBOutlet weak var publishButton: UIButton!

    // LEAH: - make a camera view uiview
    private lazy var cameraView = UIView()
    
    // MARK: - Camera & Scene properties
    private let serialQueue = DispatchQueue(label: "serialQueue")
    private var currentCamera: CameraDeviceWithPosition = .front

    private var arCamera: ARGCamera!
    private var arScene: ARGScene!
    private var arMedia: ARGMedia = ARGMedia()

    private lazy var cameraPreviewCALayer = CALayer()

    // - rtmp variables
    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    private var currentPosition: AVCaptureDevice.Position = .front
    private var retryCount: Int = 0

    // MARK: - Functions UI
//    @IBOutlet weak var filterCancelLabel: UILabel!
//    @IBOutlet weak var contentCancelLabel: UILabel!
    
    // MARK: - UI
    @IBOutlet weak var touchLockView: UIView!
    @IBOutlet weak var permissionView: PermissionView!
    @IBOutlet weak var settingView: SettingView!
    @IBOutlet weak var ratioView: RatioView!
    @IBOutlet weak var mainTopFunctionView: MainTopFunctionView!
    @IBOutlet weak var mainBottomFunctionView: MainBottomFunctionView!

    private var argObservers = [NSKeyValueObservation]()

    // AVAudtionSession HaishinKit
    let session = AVAudioSession.sharedInstance()


    // MARK: - Lifecycles
    override public func viewDidLoad() {
      super.viewDidLoad()

        // HaishinKit
        do {
            // https://stackoverflow.com/questions/51010390/avaudiosession-setcategory-swift-4-2-ios-12-play-sound-on-silent
            if #available(iOS 10.0, *) {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            } else {
                session.perform(NSSelectorFromString("setCategory:withOptions:error:"), with: AVAudioSession.Category.playAndRecord, with: [
                    AVAudioSession.CategoryOptions.allowBluetooth,
                    AVAudioSession.CategoryOptions.defaultToSpeaker]
                )
                try session.setMode(.default)
            }
            try session.setActive(true)
        } catch {
            print(error)
        }
        // - set rtmp stream
        rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.orientation = AVCaptureVideoOrientation.portrait

        // - capture settings
        rtmpStream.captureSettings = [
         .sessionPreset: AVCaptureSession.Preset.medium
        ]

        // - video settings
        rtmpStream.videoSettings = [
         .width: 720,
         .height: 1280
        ]


        setupARGearConfig()
        setupScene()
        setupCamera()
        setupUI()
        addObservers()

        initHelpers()
        connectAPI()

//        rtmpStream.attachCamera(arCamera.cameraDevice) { error in
//             print("martino debug \(error)")
//        }
        // iOS
        //rtmpStream.attachScreen(ScreenCaptureSession(shared: UIApplication.shared))
    }
    // - on disappear
       // - clean stream
   override public func viewWillDisappear(_ animated: Bool) {
       super.viewWillDisappear(animated)
       rtmpStream.close()
       rtmpStream.dispose()
   }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        runARGSession()

    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopARGSession()

        rtmpStream.close()
        rtmpStream.dispose()
    }

    deinit {
        removeObservers()
    }

    private func initHelpers() {
        NetworkManager.shared.argSession = self.argSession
        FilterManager.shared.argSession = self.argSession
    }

    /**
       HAISHINkit
        delegates
        */
    @objc
    private func rtmpStatusHandler(_ notification: Notification) {
       let e = Event.from(notification)
       guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
           return
       }

       debugPrint(code)
    }

    @objc
    private func rtmpErrorHandler(_ notification: Notification) {
    }

    // MARK: - connect argear API
    private func connectAPI() {

        NetworkManager.shared.connectAPI { (result: Result<[String: Any], APIError>) in
            debugPrint("result martino--\(result)")
            switch result {

            case .success(let data):
                debugPrint("result martino data--\(data)")
                RealmManager.shared.setARGearData(data) { [weak self] success in
                    guard let self = self else { return }

                    self.loadAPIData()
                }
            case .failure(.network):
                self.loadAPIData()
                break
            case .failure(.data):
                self.loadAPIData()
                break
            case .failure(.serializeJSON):
                self.loadAPIData()
                break
            }
        }
    }

    private func loadAPIData() {
        DispatchQueue.main.async {
           // let categories = RealmManager.shared.getCategories()
            
//            self.mainBottomFunctionView.contentView.contentsCollectionView.contents = categories
//            self.mainBottomFunctionView.contentView.contentTitleListScrollView.contents = categories
            self.mainBottomFunctionView.filterView.filterCollectionView.filters = RealmManager.shared.getFilters()
        }
    }

    @IBAction func publish(_ publish: UIButton) {
        if publish.isSelected {
               UIApplication.shared.isIdleTimerDisabled = false
               rtmpConnection.close()
               rtmpConnection.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
               rtmpConnection.removeEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            publish.setTitle("●", for: [])
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
            rtmpConnection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
            // - attach audio
            rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
            }
            // - attach screen
            rtmpStream.attachScreen(ScreenCaptureSession(viewToCapture: self.cameraView))
            
            rtmpConnection.connect("rtmp://13.73.1.230:1935/live/")
            rtmpStream.publish("martino_sample")

            publish.setTitle("■", for: [])
        }

        publish.isSelected.toggle()
    }

    // MARK: - ARGearSDK setupConfig
    private func setupARGearConfig() {
        do {
            let config = ARGConfig(
                apiURL: API_HOST,
                apiKey: API_KEY,
                secretKey: API_SECRET_KEY,
                authKey: API_AUTH_KEY
            )
            argSession = try ARGSession(argConfig: config, feature: [.faceLowTracking])
            argSession?.delegate = self

            let debugOption: ARGInferenceDebugOption = self.preferences.showLandmark ? .optionDebugFaceLandmark2D : .optionDebugNON
            argSession?.inferenceDebugOption = debugOption

        } catch let error as NSError {
            print("Failed to initialize ARGear Session with error: %@", error.description)
        } catch let exception as NSException {
            print("Exception to initialize ARGear Session with error: %@", exception.description)
        }
    }

    // MARK: - setupScene
    private func setupScene() {
        arScene = ARGScene(viewContainer: view)

        arScene.sceneRenderUpdateAtTimeHandler = { [weak self] renderer, time in
            guard let self = self else { return }
            self.refreshARFrame()
        }

        arScene.sceneRenderDidRenderSceneHandler = { [weak self] renderer, scene, time in
            guard let _ = self else { return }
        }

        cameraPreviewCALayer.contentsGravity = .resizeAspect//.resizeAspectFill
        cameraPreviewCALayer.frame = CGRect(x: 0, y: 0, width: arScene.sceneView.frame.size.height, height: arScene.sceneView.frame.size.width)
        cameraPreviewCALayer.contentsScale = UIScreen.main.scale
        
        // - LEAH: set the frame of camera view we made,
        // and add the camera layer to the camera view
        cameraView.contentMode = .scaleAspectFit //.resizeAspectFill
        cameraView.frame = view.frame
        cameraView.contentScaleFactor = UIScreen.main.scale
        view.insertSubview(cameraView, at: 0)
        cameraView.layer.insertSublayer(cameraPreviewCALayer, at: 0)
    }

    // MARK: - setupCamera
    private func setupCamera() {
        arCamera = ARGCamera()

        arCamera.sampleBufferHandler = { [weak self] output, sampleBuffer, connection in
            guard let self = self else { return }

            self.serialQueue.async {

                self.argSession?.update(sampleBuffer, from: connection)
            }
        }

        arCamera.metadataObjectsHandler = { [weak self] metadataObjects, connection in
            guard let self = self else { return }

            self.serialQueue.async {
                self.argSession?.update(metadataObjects, from: self.arCamera.cameraConnection!)
            }
        }

        self.permissionCheck {
            self.arCamera.startCamera()

            self.setCameraInfo()
        }
    }

    func setCameraInfo() {

        if let device = arCamera.cameraDevice, let connection = arCamera.cameraConnection {
            self.arMedia.setVideoDevice(device)
            self.arMedia.setVideoDeviceOrientation(.portrait)
            self.arMedia.setVideoConnection(connection)
        }
        arMedia.setMediaRatio(._16x9)
        arMedia.setVideoBitrate(ARGMediaVideoBitrate(rawValue: self.preferences.videoBitrate) ?? ._4M)
    }

    // MARK: - UI
    private func setupUI() {

        self.mainTopFunctionView.delegate = self
        //self.mainBottomFunctionView.delegate = self
        self.settingView.delegate = self

        self.ratioView.setRatio(._16x9)
        // self.settingView.setPreferences(autoSave: self.arMedia.autoSave, showLandmark: self.preferences.showLandmark, videoBitrate: self.preferences.videoBitrate)

        toast_main_position = CGPoint(x: self.view.center.x, y: mainBottomFunctionView.frame.origin.y - 24.0)

        ARGLoading.prepare()
    }

    private func startUI() {
        self.setCameraInfo()
        self.touchLock(false)
    }

    private func pauseUI() {
        self.ratioView.blur(true)
        self.touchLock(true)
    }

    func refreshRatio() {
        let ratio = arCamera.ratio

        self.ratioView.setRatio(._16x9)
        self.mainTopFunctionView.setRatio(._16x9)

        self.setCameraPreview(._16x9)

        self.arMedia.setMediaRatio(._16x9)
    }

    func setCameraPreview(_ ratio: ARGMediaRatio) {
        self.cameraPreviewCALayer.contentsGravity = (ratio == ._16x9) ? .resizeAspectFill : .resizeAspect
    }

    // MARK: - ARGearSDK Handling
    private func refreshARFrame() {

        guard self.nextFaceFrame != nil && self.nextFaceFrame != self.currentFaceFrame else { return }
        self.currentFaceFrame = self.nextFaceFrame
    }

    private func drawARCameraPreview() {

        guard
            let frame = self.currentFaceFrame,
            let pixelBuffer = frame.renderedPixelBuffer
            else {
            return
        }

        var flipTransform = CGAffineTransform(scaleX: -1, y: 1)
        if self.arCamera.currentCamera == .back {
            flipTransform = CGAffineTransform(scaleX: 1, y: 1)
        }

        DispatchQueue.main.async {

            CATransaction.flush()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0)
            if #available(iOS 11.0, *) {
                self.cameraPreviewCALayer.contents = pixelBuffer
            } else {
                self.cameraPreviewCALayer.contents = self.pixelbufferToCGImage(pixelBuffer)
            }
            let angleTransform = CGAffineTransform(rotationAngle: .pi/2)
            let transform = angleTransform.concatenating(flipTransform)
            self.cameraPreviewCALayer.setAffineTransform(transform)
            self.cameraPreviewCALayer.frame = CGRect(x: 0, y: -self.getPreviewY(), width: self.cameraPreviewCALayer.frame.size.width, height: self.cameraPreviewCALayer.frame.size.height)
            self.view.backgroundColor = .white
            CATransaction.commit()
        }
    }

    private func getPreviewY() -> CGFloat {
        let height43: CGFloat = (self.view.frame.width * 4) / 3
        let height11: CGFloat = self.view.frame.width
        var previewY: CGFloat = 0
        if self.arCamera.ratio == ._1x1 {
            previewY = (height43 - height11)/2 + CGFloat(kRatioViewTopBottomAlign11/2)
        }

        if #available(iOS 11.0, *), self.arCamera.ratio != ._16x9 {
            if let topInset = UIApplication.shared.keyWindow?.rootViewController?.view.safeAreaInsets.top {
                if self.arCamera.ratio == ._1x1 {
                    previewY += topInset/2
                } else {
                    previewY += topInset
                }
            }
        }

        return previewY
    }

    private func pixelbufferToCGImage(_ pixelbuffer: CVPixelBuffer) -> CGImage? {
        let ciimage = CIImage(cvPixelBuffer: pixelbuffer)
        let context = CIContext()
        let cgimage = context.createCGImage(ciimage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelbuffer), height: CVPixelBufferGetHeight(pixelbuffer)))

        return cgimage
    }

    private func runARGSession() {

        argSession?.run()
    }

    private func stopARGSession() {
        argSession?.pause()
    }

    
}

// MARK: - ARGearSDK ARGSession delegate
extension MainViewController : ARGSessionDelegate {

      public func didUpdate(_ arFrame: ARGFrame) {

        self.drawARCameraPreview()
        
        nextFaceFrame = arFrame
        if #available(iOS 11.0, *) {
        } else {
            self.arScene.sceneView.sceneTime += 1
        }
    }

}

// MARK: - User Interaction
extension MainViewController {
    // Touch Lock Control
    func touchLock(_ lock: Bool) {

        self.touchLockView.isHidden = !lock
        if lock {
            mainTopFunctionView.disableButtons()
        } else {
            mainTopFunctionView.enableButtons()
        }
    }
}

// MARK: - Permission
extension MainViewController {
    func permissionCheck(_ permissionCheckComplete: @escaping PermissionCheckComplete) {

        let permissionLevel = self.permissionView.permission.getPermissionLevel()
        self.permissionView.permission.grantedHandler = permissionCheckComplete
        self.permissionView.setPermissionLevel(permissionLevel)

        switch permissionLevel {
        case .Granted:
            break
        case .None:
            break
        case .Restricted:
            break
        }
    }
}

// MARK: - Observers
extension MainViewController {

    // MainTopFunctionView
    func addMainTopFunctionViewObservers() {
        self.argObservers.append(
            self.arCamera.observe(\.ratio, options: [.new]) { [weak self] obj, _ in
                guard let self = self else { return }

                self.mainTopFunctionView.setRatio(obj.ratio)
            }
        )
    }

    // MainBottomFunctionView
    func addMainBottomFunctionViewObservers() {
        self.argObservers.append(
            self.arCamera.observe(\.ratio, options: [.new]) { [weak self] obj, _ in
                guard let self = self else { return }

                self.mainBottomFunctionView.setRatio(obj.ratio)
            }
        )
    }

    // Add
    func addObservers() {
        self.addMainTopFunctionViewObservers()
        self.addMainBottomFunctionViewObservers()
    }

    // Remove
    func removeObservers() {
        self.argObservers.removeAll()
    }
}

// MARK: - Setting Delegate
extension MainViewController: SettingDelegate {
    func autoSaveSwitchAction(_ sender: UISwitch) {
        self.arMedia.autoSave = sender.isOn
    }

    func faceLandmarkSwitchAction(_ sender: UISwitch) {
        self.preferences.setShowLandmark(sender.isOn)

        if let session = self.argSession {
            let debugOption: ARGInferenceDebugOption = sender.isOn ? .optionDebugFaceLandmark2D : .optionDebugNON
            session.inferenceDebugOption = debugOption
        }
    }

    func bitrateSegmentedControlAction(_ sender: UISegmentedControl) {
        self.preferences.setVideoBitrate(sender.selectedSegmentIndex)
        self.arMedia.setVideoBitrate(ARGMediaVideoBitrate(rawValue: sender.selectedSegmentIndex) ?? ._4M)
    }
}

// MARK: - MainTopFunction Delegate
extension MainViewController: MainTopFunctionDelegate {

    func settingButtonAction() {
        self.settingView.open()
    }

    func ratioButtonAction() {
        guard
            let session = argSession
            else { return }

        self.pauseUI()
        session.pause()

        self.arCamera.changeCameraRatio {

            self.startUI()
            self.refreshRatio()
            session.run()
        }
    }

    func toggleButtonAction() {
        guard
            let session = argSession
            else { return }

        self.pauseUI()
        session.pause()

        arCamera.toggleCamera {

            self.startUI()
            self.refreshRatio()
            session.run()
        }
    }
}
