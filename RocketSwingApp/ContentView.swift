import SwiftUI
@preconcurrency import SceneKit
import UIKit
@preconcurrency import AVFoundation
import simd

struct ContentView: View {
    @AppStorage("cameraDistance") private var cameraDistance = 6.0
    @AppStorage("cameraYaw") private var cameraYaw = 0.0
    @AppStorage("cameraPitch") private var cameraPitch = 0.0
    @AppStorage("masterVolume") private var masterVolume = 0.8
    @AppStorage("missileVolume") private var missileVolume = 0.85
    @AppStorage("ambienceVolume") private var ambienceVolume = 0.65
    @AppStorage("rocketCount") private var rocketCount = 6
    @AppStorage("trailLength") private var trailLength = 1.0
    @State private var isShowingSettings = false
    @State private var isPaused = false
    @State private var isFollowingRocket = false

    private let minimumCameraDistance = 0.95
    private let maximumCameraDistance = 30.0

    var body: some View {
        ZStack {
            RocketSceneView(
                cameraDistance: $cameraDistance,
                cameraYaw: $cameraYaw,
                cameraPitch: $cameraPitch,
                minimumCameraDistance: minimumCameraDistance,
                maximumCameraDistance: maximumCameraDistance,
                masterVolume: Float(masterVolume),
                missileVolume: Float(missileVolume),
                ambienceVolume: Float(ambienceVolume),
                rocketCount: rocketCount,
                trailLength: Float(trailLength),
                isPaused: isPaused,
                isFollowingRocket: isFollowingRocket
            )
                .ignoresSafeArea()
                .accessibilityHidden(true)

            HStack(spacing: 18) {
                PauseButton(isPaused: isPaused) {
                    isPaused.toggle()
                }

                FollowRocketButton(isFollowing: isFollowingRocket) {
                    isFollowingRocket.toggle()
                }

                SettingsButton {
                    isShowingSettings = true
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 24)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .hiddenPersistentSystemOverlaysWhenAvailable()
        .onAppear {
            cameraDistance = min(max(cameraDistance, minimumCameraDistance), maximumCameraDistance)
            cameraPitch = min(max(cameraPitch, -1.15), 1.15)
            masterVolume = min(max(masterVolume, 0), 1)
            missileVolume = min(max(missileVolume, 0), 1)
            ambienceVolume = min(max(ambienceVolume, 0), 1)
            rocketCount = min(max(rocketCount, 1), 50)
            trailLength = min(max(trailLength, 0.35), 2.5)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                masterVolume: $masterVolume,
                missileVolume: $missileVolume,
                ambienceVolume: $ambienceVolume,
                rocketCount: $rocketCount,
                trailLength: $trailLength
            )
            .settingsSheetPresentationStyle()
        }
    }
}

private extension View {
    @ViewBuilder
    func settingsSheetPresentationStyle() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

struct RocketSceneView: UIViewRepresentable {
    @Binding var cameraDistance: Double
    @Binding var cameraYaw: Double
    @Binding var cameraPitch: Double
    var minimumCameraDistance: Double
    var maximumCameraDistance: Double
    var masterVolume: Float
    var missileVolume: Float
    var ambienceVolume: Float
    var rocketCount: Int
    var trailLength: Float
    var isPaused: Bool
    var isFollowingRocket: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            cameraDistance: $cameraDistance,
            cameraYaw: $cameraYaw,
            cameraPitch: $cameraPitch,
            minimumCameraDistance: minimumCameraDistance,
            maximumCameraDistance: maximumCameraDistance
        )
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = makeScene()
        view.scene = scene
        view.backgroundColor = .black
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = true
        view.antialiasingMode = .multisampling4X
        context.coordinator.installGestures(on: view)
        context.coordinator.start(
            scene: scene,
            masterVolume: masterVolume,
            missileVolume: missileVolume,
            ambienceVolume: ambienceVolume,
            isPaused: isPaused,
            isFollowingRocket: isFollowingRocket
        )
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateVolumes(
            masterVolume: masterVolume,
            missileVolume: missileVolume,
            ambienceVolume: ambienceVolume
        )
        context.coordinator.updatePaused(isPaused)
        context.coordinator.updateFollowMode(isFollowingRocket)

        let clampedRocketCount = max(1, min(rocketCount, 50))
        let clampedTrailLength = max(0.35, min(trailLength, 2.5))
        if context.coordinator.shouldRebuildOrbitingRockets(
            rocketCount: clampedRocketCount,
            trailLength: clampedTrailLength
        ), let scene = uiView.scene {
            rebuildOrbitingRockets(
                in: scene,
                rocketCount: clampedRocketCount,
                trailLength: clampedTrailLength
            )
            context.coordinator.markOrbitingRocketsBuilt(
                rocketCount: clampedRocketCount,
                trailLength: clampedTrailLength
            )
        }

        context.coordinator.syncExternalCameraDistance(cameraDistance)
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.name = "main-camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 55
        cameraNode.position = cameraPosition(
            distance: Float(cameraDistance),
            yaw: Float(cameraYaw),
            pitch: Float(cameraPitch)
        )
        scene.rootNode.addChildNode(cameraNode)

        let rocketNode = rocketNode(
            bodyColor: .white,
            accentColor: .systemRed,
            finColor: .systemBlue,
            scale: 0.62
        )
        rocketNode.name = "rocket-firing-source"
        rocketNode.eulerAngles = SCNVector3Zero
        scene.rootNode.addChildNode(rocketNode)

        addStarField(to: scene)
        addOrbitingRockets(to: scene, rocketCount: max(1, min(rocketCount, 50)), trailLength: max(0.35, min(trailLength, 2.5)))

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 900
        light.position = SCNVector3(2, 3, 4)
        scene.rootNode.addChildNode(light)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 360
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    private func cameraPosition(distance: Float, yaw: Float, pitch: Float) -> SCNVector3 {
        let horizontalDistance = distance * cos(pitch)
        return SCNVector3(
            sin(yaw) * horizontalDistance,
            sin(pitch) * distance,
            cos(yaw) * horizontalDistance
        )
    }

    private func addStarField(to scene: SCNScene) {
        let starMaterial = SCNMaterial()
        starMaterial.diffuse.contents = UIColor.white
        starMaterial.emission.contents = UIColor.white
        starMaterial.lightingModel = .constant

        for index in 0..<320 {
            let star = SCNSphere(radius: index.isMultiple(of: 7) ? 0.046 : 0.028)
            star.segmentCount = 8
            star.materials = [starMaterial]

            let theta = Float.random(in: 0...(Float.pi * 2))
            let z = Float.random(in: -1...1)
            let radius = Float.random(in: 18...34)
            let ring = sqrt(max(0, 1 - z * z))
            let node = SCNNode(geometry: star)
            node.position = SCNVector3(
                cos(theta) * ring * radius,
                z * radius,
                sin(theta) * ring * radius
            )
            scene.rootNode.addChildNode(node)

            let shimmer = CABasicAnimation(keyPath: "opacity")
            shimmer.fromValue = Float.random(in: 0.18...0.38)
            shimmer.toValue = Float.random(in: 0.88...1.0)
            shimmer.duration = CFTimeInterval.random(in: 0.65...1.5)
            shimmer.autoreverses = true
            shimmer.repeatCount = .infinity
            shimmer.beginTime = CACurrentMediaTime() + CFTimeInterval(index) * 0.018
            node.addAnimation(shimmer, forKey: "star-shimmer")

            let pulse = CABasicAnimation(keyPath: "scale")
            pulse.fromValue = SCNVector3(0.72, 0.72, 0.72)
            pulse.toValue = SCNVector3(1.35, 1.35, 1.35)
            pulse.duration = shimmer.duration
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = shimmer.beginTime
            node.addAnimation(pulse, forKey: "star-pulse")
        }
    }

    private func rebuildOrbitingRockets(in scene: SCNScene, rocketCount: Int, trailLength: Float) {
        scene.rootNode.childNode(withName: "orbiting-rockets", recursively: false)?.removeFromParentNode()
        addOrbitingRockets(to: scene, rocketCount: rocketCount, trailLength: trailLength)
    }

    private func addOrbitingRockets(to scene: SCNScene, rocketCount: Int, trailLength: Float) {
        let colors: [UIColor] = [
            .systemOrange,
            .systemMint,
            .systemPurple,
            .systemCyan,
            .systemIndigo
        ]
        let orbitGroup = SCNNode()
        orbitGroup.name = "orbiting-rockets"
        scene.rootNode.addChildNode(orbitGroup)
        let satelliteCount = max(0, rocketCount - 1)

        for index in 0..<satelliteCount {
            let satellite = rocketNode(
                bodyColor: colors[index % colors.count].withAlphaComponent(0.94),
                accentColor: colors[(index + 1) % colors.count],
                finColor: colors[(index + 2) % colors.count],
                scale: 0.24
            )
            satellite.name = "rocket-firing-source"
            satellite.position = Self.orbitPosition(for: index, progress: 0)
            satellite.simdOrientation = Self.rocketOrientation(for: index, progress: 0)
            orbitGroup.addChildNode(satellite)

            let duration = TimeInterval(7.4 + Double(index % 7) * 1.15)
            let phaseDelay = TimeInterval(index) * 0.18
            let orbitAction = SCNAction.customAction(duration: duration) { node, elapsed in
                let progress = Float(elapsed / CGFloat(duration))
                node.position = Self.orbitPosition(for: index, progress: progress)
                node.simdOrientation = Self.rocketOrientation(for: index, progress: progress)
            }
            let delayedOrbit = SCNAction.sequence([
                .wait(duration: phaseDelay),
                .repeatForever(orbitAction)
            ])
            satellite.runAction(delayedOrbit, forKey: "smooth-orbit")

            attachTrail(to: satellite, color: colors[index % colors.count], length: trailLength)
        }
    }

    private func attachTrail(to rocket: SCNNode, color: UIColor, length: Float) {
        let flame = engineFlame(color: color)
        flame.position = SCNVector3(0, -1.13, 0)
        rocket.addChildNode(flame)

        let emitter = SCNNode()
        emitter.position = SCNVector3(0, -1.28, 0)
        emitter.addParticleSystem(trailParticles(color: color, length: length))
        rocket.addChildNode(emitter)

        let glow = SCNSphere(radius: 0.055)
        glow.segmentCount = 16
        let glowMaterial = material(color.withAlphaComponent(0.9))
        glowMaterial.emission.contents = color.withAlphaComponent(0.9)
        glowMaterial.transparency = 0.72
        glow.materials = [glowMaterial]
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(0, -0.94, 0)
        rocket.addChildNode(glowNode)
    }

    private func engineFlame(color: UIColor) -> SCNNode {
        let root = SCNNode()

        let outer = SCNCone(topRadius: 0.055, bottomRadius: 0.18, height: 0.42)
        outer.radialSegmentCount = 32
        outer.materials = [flameMaterial(color.withAlphaComponent(0.72))]
        let outerNode = SCNNode(geometry: outer)
        root.addChildNode(outerNode)

        let core = SCNCone(topRadius: 0.028, bottomRadius: 0.09, height: 0.34)
        core.radialSegmentCount = 32
        core.materials = [flameMaterial(UIColor.white.withAlphaComponent(0.78))]
        let coreNode = SCNNode(geometry: core)
        coreNode.position = SCNVector3(0, 0.03, 0)
        root.addChildNode(coreNode)

        let pulse = CABasicAnimation(keyPath: "scale")
        pulse.fromValue = SCNVector3(0.82, 0.92, 0.82)
        pulse.toValue = SCNVector3(1.08, 1.04, 1.08)
        pulse.duration = 0.18
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        root.addAnimation(pulse, forKey: "flame-pulse")

        return root
    }

    private func flameMaterial(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.transparency = 0.72
        material.blendMode = .add
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        return material
    }

    nonisolated private static func orbitPosition(for index: Int, progress: Float) -> SCNVector3 {
        let angle = progress * Float.pi * 2
        let phase = Float(index) * 0.83
        let horizontalRadius = Float(1.75 + Double(index % 4) * 0.48)
        let verticalRadius = Float(0.62 + Double((index + 1) % 3) * 0.34)
        let depthRadius = Float(1.05 + Double(index % 6) * 0.36)
        let verticalFrequency = Float((index % 3) + 1)
        let radialFrequency = Float((index % 2) + 1)
        let radialPulse = 1 + sin(angle * radialFrequency + phase * 0.7) * 0.08

        var point = SCNVector3(
            cos(angle + phase) * horizontalRadius * radialPulse,
            sin(angle * verticalFrequency + phase) * verticalRadius,
            sin(angle + phase) * depthRadius * radialPulse
        )

        let rotations: [(Float, Float, Float)] = [
            (0.20, 0.45, 0.12),
            (1.02, 0.18, 0.76),
            (0.38, 1.15, 1.05),
            (1.34, 0.72, 0.24),
            (0.74, 1.42, 0.92)
        ]
        let rotation = rotations[index % rotations.count]
        point = rotate(point, aroundX: rotation.0)
        point = rotate(point, aroundY: rotation.1)
        point = rotate(point, aroundZ: rotation.2)

        let wobble = sin(angle * Float((index % 4) + 2) + phase) * 0.10
        return SCNVector3(point.x, point.y + wobble, point.z)
    }

    nonisolated private static func rocketOrientation(for index: Int, progress: Float) -> simd_quatf {
        let previous = orbitPosition(for: index, progress: progress - 0.004).simdVector
        let next = orbitPosition(for: index, progress: progress + 0.004).simdVector
        let rawDirection = next - previous
        let direction = simd_length(rawDirection) > 0.0001
            ? simd_normalize(rawDirection)
            : SIMD3<Float>(0, 1, 0)
        let tangentAlignment = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        let angle = progress * Float.pi * 2
        let roll = sin(angle * Float((index % 3) + 1) + Float(index) * 0.37) * 0.22
        let rollAroundTangent = simd_quatf(angle: roll, axis: direction)
        return simd_normalize(simd_mul(rollAroundTangent, tangentAlignment))
    }

    nonisolated private static func rotate(_ vector: SCNVector3, aroundX angle: Float) -> SCNVector3 {
        SCNVector3(
            vector.x,
            vector.y * cos(angle) - vector.z * sin(angle),
            vector.y * sin(angle) + vector.z * cos(angle)
        )
    }

    nonisolated private static func rotate(_ vector: SCNVector3, aroundY angle: Float) -> SCNVector3 {
        SCNVector3(
            vector.x * cos(angle) + vector.z * sin(angle),
            vector.y,
            -vector.x * sin(angle) + vector.z * cos(angle)
        )
    }

    nonisolated private static func rotate(_ vector: SCNVector3, aroundZ angle: Float) -> SCNVector3 {
        SCNVector3(
            vector.x * cos(angle) - vector.y * sin(angle),
            vector.x * sin(angle) + vector.y * cos(angle),
            vector.z
        )
    }

    private func trailParticles(color: UIColor, length: Float) -> SCNParticleSystem {
        let clampedLength = CGFloat(max(0.35, min(length, 2.5)))
        let particles = SCNParticleSystem()
        particles.birthRate = 260 * clampedLength
        particles.loops = true
        particles.particleLifeSpan = 1.15 * clampedLength
        particles.particleLifeSpanVariation = 0.35 * clampedLength
        particles.particleSize = 0.085
        particles.particleSizeVariation = 0.03
        particles.particleImage = UIImage(named: "PremiumParticle")
        particles.particleColor = color.withAlphaComponent(0.82)
        particles.particleColorVariation = SCNVector4(0.18, 0.18, 0.18, 0.35)
        particles.blendMode = .additive
        particles.emitterShape = SCNSphere(radius: 0.055)
        particles.birthDirection = .constant
        particles.emittingDirection = SCNVector3(0, -1, 0)
        particles.spreadingAngle = 8
        particles.particleVelocity = 0.025
        particles.particleVelocityVariation = 0.035
        particles.isAffectedByGravity = false
        particles.stretchFactor = 0.12
        return particles
    }

    private func rocketNode(
        bodyColor: UIColor,
        accentColor: UIColor,
        finColor: UIColor,
        scale: Float
    ) -> SCNNode {
        if let scene = SCNScene(named: "Rocket.scnassets/RocketIcon.dae"),
           let model = scene.rootNode.childNode(withName: "RocketIconRoot", recursively: true)?.clone() {
            let root = SCNNode()
            root.name = "RocketIconAsset"
            root.scale = SCNVector3(scale * 0.78, scale * 0.78, scale * 0.78)
            applyRocketAssetMaterials(
                to: model,
                bodyColor: bodyColor,
                accentColor: accentColor,
                finColor: finColor
            )
            root.addChildNode(model)
            return root
        }

        return fallbackRocketNode(
            bodyColor: bodyColor,
            accentColor: accentColor,
            finColor: finColor,
            scale: scale
        )
    }

    private func applyRocketAssetMaterials(
        to node: SCNNode,
        bodyColor: UIColor,
        accentColor: UIColor,
        finColor: UIColor
    ) {
        node.enumerateChildNodes { child, _ in
            guard let geometry = child.geometry else {
                return
            }

            switch child.name {
            case "glossyWhiteBody":
                geometry.materials = [material(bodyColor)]
            case "candyRedNose":
                geometry.materials = [material(accentColor)]
            case "leftIconFin", "rightIconFin", "frontIconFin":
                geometry.materials = [material(finColor)]
            case "blueGlassWindow":
                let glass = material(.systemCyan)
                glass.emission.contents = UIColor.systemCyan.withAlphaComponent(0.42)
                geometry.materials = [glass]
            case "silverWindowRim":
                geometry.materials = [material(UIColor(white: 0.78, alpha: 1))]
            case "chromeEngineLeft", "chromeEngineRight":
                geometry.materials = [material(.darkGray)]
            case "tailRing":
                geometry.materials = [material(.systemOrange)]
            default:
                break
            }
        }
    }

    private func fallbackRocketNode(
        bodyColor: UIColor,
        accentColor: UIColor,
        finColor: UIColor,
        scale: Float
    ) -> SCNNode {
        let root = SCNNode()
        root.scale = SCNVector3(scale, scale, scale)

        let body = SCNCylinder(radius: 0.32, height: 1.28)
        body.radialSegmentCount = 32
        body.materials = [material(bodyColor)]
        let bodyNode = SCNNode(geometry: body)
        root.addChildNode(bodyNode)

        let nose = SCNCone(topRadius: 0, bottomRadius: 0.32, height: 0.48)
        nose.radialSegmentCount = 32
        nose.materials = [material(accentColor)]
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0, 0.88, 0)
        root.addChildNode(noseNode)

        let engine = SCNCylinder(radius: 0.22, height: 0.18)
        engine.radialSegmentCount = 24
        engine.materials = [material(.darkGray)]
        let engineNode = SCNNode(geometry: engine)
        engineNode.position = SCNVector3(0, -0.73, 0)
        root.addChildNode(engineNode)

        let window = SCNSphere(radius: 0.15)
        window.segmentCount = 24
        let glass = material(.systemCyan)
        glass.emission.contents = UIColor.systemCyan.withAlphaComponent(0.35)
        window.materials = [glass]
        let windowNode = SCNNode(geometry: window)
        windowNode.position = SCNVector3(0, 0.32, 0.3)
        windowNode.scale = SCNVector3(1, 1, 0.18)
        root.addChildNode(windowNode)

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi * 2 / 3) {
            let fin = SCNBox(width: 0.12, height: 0.44, length: 0.34, chamferRadius: 0.025)
            fin.materials = [material(finColor)]
            let finNode = SCNNode(geometry: fin)
            finNode.position = SCNVector3(Float(cos(angle)) * 0.34, -0.42, Float(sin(angle)) * 0.34)
            finNode.eulerAngles = SCNVector3(0, -Float(angle), 0)
            root.addChildNode(finNode)
        }

        return root
    }

    private func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor.white
        material.shininess = 0.45
        material.isDoubleSided = true
        return material
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var scene: SCNScene?
        private weak var sceneView: SCNView?
        private var missileTimer: Timer?
        private var ambiencePlayer: AVAudioPlayer?
        private var effectPlayers: [AVAudioPlayer] = []
        private var inertiaDisplayLink: CADisplayLink?
        private var lastInertiaTimestamp: CFTimeInterval?
        private var cameraInertiaVelocity = SIMD2<Double>(repeating: 0)
        private var zoomInertiaDisplayLink: CADisplayLink?
        private var lastZoomInertiaTimestamp: CFTimeInterval?
        private var cameraZoomVelocity = 0.0
        private var followDisplayLink: CADisplayLink?
        private weak var followedRocket: SCNNode?
        private var masterVolume: Float = 0.8
        private var missileVolume: Float = 0.85
        private var ambienceVolume: Float = 0.65
        private var builtRocketCount: Int?
        private var builtTrailLength: Float?
        private var isPaused = false
        private var cameraDistance: Binding<Double>
        private var cameraYaw: Binding<Double>
        private var cameraPitch: Binding<Double>
        private let minimumCameraDistance: Double
        private let maximumCameraDistance: Double
        private var currentCameraDistance: Double
        private var currentCameraYaw: Double
        private var currentCameraPitch: Double
        private var cameraOrientation: simd_quatd
        private var lastSyncedCameraDistance: Double
        private var isInteractingWithCamera = false
        private var activeCameraGestures = 0
        private var isFollowingRocket = false
        private var cameraPersistenceTask: Task<Void, Never>?
        private var panPreviousTranslation = CGPoint.zero
        private var pinchStartDistance = 0.0
        private let trackballSensitivity = 0.006

        init(
            cameraDistance: Binding<Double>,
            cameraYaw: Binding<Double>,
            cameraPitch: Binding<Double>,
            minimumCameraDistance: Double,
            maximumCameraDistance: Double
        ) {
            self.cameraDistance = cameraDistance
            self.cameraYaw = cameraYaw
            self.cameraPitch = cameraPitch
            self.minimumCameraDistance = minimumCameraDistance
            self.maximumCameraDistance = maximumCameraDistance
            self.currentCameraDistance = cameraDistance.wrappedValue
            self.currentCameraYaw = cameraYaw.wrappedValue
            self.currentCameraPitch = cameraPitch.wrappedValue
            self.cameraOrientation = Self.makeCameraOrientation(
                yaw: cameraYaw.wrappedValue,
                pitch: cameraPitch.wrappedValue
            )
            self.lastSyncedCameraDistance = cameraDistance.wrappedValue
        }

        func installGestures(on view: SCNView) {
            guard sceneView !== view else {
                return
            }

            sceneView = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
        }

        func start(
            scene: SCNScene,
            masterVolume: Float,
            missileVolume: Float,
            ambienceVolume: Float,
            isPaused: Bool,
            isFollowingRocket: Bool
        ) {
            self.scene = scene
            updateCamera(animated: false)
            updateVolumes(
                masterVolume: masterVolume,
                missileVolume: missileVolume,
                ambienceVolume: ambienceVolume
            )
            startAmbience()
            updatePaused(isPaused)
            if !isPaused {
                scheduleNextMissile()
            }
            updateFollowMode(isFollowingRocket)
        }

        func syncExternalCameraDistance(_ distance: Double) {
            guard !isFollowingRocket else {
                return
            }

            let clampedDistance = max(minimumCameraDistance, min(maximumCameraDistance, distance))
            guard !isInteractingWithCamera else {
                return
            }

            guard abs(clampedDistance - lastSyncedCameraDistance) > 0.001 else {
                updateCamera(animated: false)
                return
            }

            currentCameraDistance = clampedDistance
            lastSyncedCameraDistance = clampedDistance
            updateCamera(animated: false)
        }

        func updateCamera(animated: Bool) {
            guard let cameraNode = scene?.rootNode.childNode(withName: "main-camera", recursively: false) else {
                return
            }

            let distance = max(minimumCameraDistance, min(currentCameraDistance, maximumCameraDistance))
            let offset = cameraOrientation.act(SIMD3<Double>(0, 0, distance))
            let position = SCNVector3(Float(offset.x), Float(offset.y), Float(offset.z))

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.18 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            cameraNode.position = position
            cameraNode.simdOrientation = simd_quatf(
                ix: Float(cameraOrientation.imag.x),
                iy: Float(cameraOrientation.imag.y),
                iz: Float(cameraOrientation.imag.z),
                r: Float(cameraOrientation.real)
            )
            SCNTransaction.commit()
        }

        func updateFollowMode(_ shouldFollow: Bool) {
            guard isFollowingRocket != shouldFollow else {
                if shouldFollow {
                    updateFollowCamera(animated: false)
                }
                return
            }

            isFollowingRocket = shouldFollow
            if shouldFollow {
                cameraPersistenceTask?.cancel()
                stopCameraInertia()
                stopZoomInertia()
                isInteractingWithCamera = false
                activeCameraGestures = 0
                followedRocket = randomOrbitingRocket()
                startFollowCamera()
            } else {
                stopFollowCamera()
                followedRocket = nil
                updateCamera(animated: true)
            }
        }

        private func startFollowCamera() {
            followDisplayLink?.invalidate()
            updateFollowCamera(animated: true)

            let displayLink = CADisplayLink(target: self, selector: #selector(stepFollowCamera(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            displayLink.add(to: .main, forMode: .common)
            followDisplayLink = displayLink
        }

        private func stopFollowCamera() {
            followDisplayLink?.invalidate()
            followDisplayLink = nil
        }

        @objc private func stepFollowCamera(_ displayLink: CADisplayLink) {
            updateFollowCamera(animated: false)
        }

        private func updateFollowCamera(animated: Bool) {
            guard isFollowingRocket,
                  let scene,
                  let cameraNode = scene.rootNode.childNode(withName: "main-camera", recursively: false) else {
                return
            }

            if followedRocket?.parent == nil {
                followedRocket = randomOrbitingRocket()
            }

            guard let rocket = followedRocket else {
                return
            }

            let presentation = rocket.presentation
            let nose = presentation.convertPosition(SCNVector3(0, 1.05, 0), to: nil).simdVector
            let body = presentation.convertPosition(SCNVector3(0, 0.12, 0), to: nil).simdVector
            let tail = presentation.convertPosition(SCNVector3(0, -0.9, 0), to: nil).simdVector
            var forward = nose - tail
            if simd_length(forward) < 0.001 {
                forward = SIMD3<Float>(0, 1, 0)
            } else {
                forward = simd_normalize(forward)
            }

            var side = simd_cross(SIMD3<Float>(0, 1, 0), forward)
            if simd_length(side) < 0.001 {
                side = SIMD3<Float>(1, 0, 0)
            } else {
                side = simd_normalize(side)
            }
            let up = simd_normalize(simd_cross(forward, side))
            let followDistance = Float(max(1.35, min(3.8, currentCameraDistance * 0.36)))
            let cameraPosition = tail - forward * followDistance + up * 0.48 + side * 0.18
            let lookTarget = body + forward * 1.65

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.22 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            cameraNode.position = SCNVector3(cameraPosition.x, cameraPosition.y, cameraPosition.z)
            cameraNode.look(
                at: SCNVector3(lookTarget.x, lookTarget.y, lookTarget.z),
                up: SCNVector3(up.x, up.y, up.z),
                localFront: SCNVector3(0, 0, -1)
            )
            SCNTransaction.commit()
        }

        private func randomOrbitingRocket() -> SCNNode? {
            guard let orbitGroup = scene?.rootNode.childNode(withName: "orbiting-rockets", recursively: false) else {
                return nil
            }

            let rockets = orbitGroup.childNodes.filter { $0.name == "rocket-firing-source" }
            return rockets.randomElement()
        }

        private func beginCameraInteraction() {
            cameraPersistenceTask?.cancel()
            if inertiaDisplayLink != nil || zoomInertiaDisplayLink != nil {
                stopCameraInertia()
                stopZoomInertia()
                activeCameraGestures = 0
            } else {
                stopCameraInertia()
                stopZoomInertia()
            }
            activeCameraGestures += 1
            isInteractingWithCamera = true
        }

        private func finishCameraInteraction() {
            activeCameraGestures = max(0, activeCameraGestures - 1)
            guard activeCameraGestures == 0 else {
                return
            }

            let finalDistance = max(minimumCameraDistance, min(maximumCameraDistance, currentCameraDistance))
            currentCameraDistance = finalDistance
            lastSyncedCameraDistance = finalDistance
            updateCamera(animated: false)

            cameraPersistenceTask?.cancel()
            cameraPersistenceTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled else {
                    return
                }

                self.cameraDistance.wrappedValue = finalDistance

                await Task.yield()
                guard !Task.isCancelled else {
                    return
                }

                self.currentCameraDistance = finalDistance
                self.lastSyncedCameraDistance = finalDistance
                self.isInteractingWithCamera = false
                self.updateCamera(animated: false)
            }
        }

        private static func makeCameraOrientation(yaw: Double, pitch: Double) -> simd_quatd {
            let yawRotation = simd_quatd(angle: yaw, axis: SIMD3<Double>(0, 1, 0))
            let pitchRotation = simd_quatd(angle: -pitch, axis: SIMD3<Double>(1, 0, 0))
            return simd_normalize(yawRotation * pitchRotation)
        }

        private func applyTrackballDelta(_ delta: CGPoint) {
            guard delta != .zero else {
                return
            }

            let localRight = simd_normalize(cameraOrientation.act(SIMD3<Double>(1, 0, 0)))
            let localUp = simd_normalize(cameraOrientation.act(SIMD3<Double>(0, 1, 0)))
            let yawRotation = simd_quatd(
                angle: -Double(delta.x) * trackballSensitivity,
                axis: localUp
            )
            let pitchRotation = simd_quatd(
                angle: -Double(delta.y) * trackballSensitivity,
                axis: localRight
            )
            cameraOrientation = simd_normalize(pitchRotation * yawRotation * cameraOrientation)
            updateCamera(animated: false)
        }

        private func startCameraInertia(with velocity: CGPoint) {
            let initialVelocity = SIMD2<Double>(Double(velocity.x), Double(velocity.y))
            guard simd_length(initialVelocity) > 45 else {
                finishCameraInteraction()
                return
            }

            cameraInertiaVelocity = initialVelocity
            lastInertiaTimestamp = nil
            inertiaDisplayLink?.invalidate()

            let displayLink = CADisplayLink(target: self, selector: #selector(stepCameraInertia(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            displayLink.add(to: .main, forMode: .common)
            inertiaDisplayLink = displayLink
        }

        private func stopCameraInertia() {
            inertiaDisplayLink?.invalidate()
            inertiaDisplayLink = nil
            lastInertiaTimestamp = nil
            cameraInertiaVelocity = SIMD2<Double>(repeating: 0)
        }

        private func startZoomInertia(with velocity: Double) {
            guard abs(velocity) > 0.35 else {
                finishCameraInteraction()
                return
            }

            cameraZoomVelocity = velocity
            lastZoomInertiaTimestamp = nil
            zoomInertiaDisplayLink?.invalidate()

            let displayLink = CADisplayLink(target: self, selector: #selector(stepZoomInertia(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            displayLink.add(to: .main, forMode: .common)
            zoomInertiaDisplayLink = displayLink
        }

        private func stopZoomInertia() {
            zoomInertiaDisplayLink?.invalidate()
            zoomInertiaDisplayLink = nil
            lastZoomInertiaTimestamp = nil
            cameraZoomVelocity = 0
        }

        @objc private func stepZoomInertia(_ displayLink: CADisplayLink) {
            let timestamp = displayLink.timestamp
            let previousTimestamp = lastZoomInertiaTimestamp ?? timestamp
            lastZoomInertiaTimestamp = timestamp

            let elapsed = min(max(timestamp - previousTimestamp, 0), 1 / 30)
            guard elapsed > 0 else {
                return
            }

            currentCameraDistance = max(
                minimumCameraDistance,
                min(maximumCameraDistance, currentCameraDistance + cameraZoomVelocity * elapsed)
            )
            updateCamera(animated: false)

            let damping = exp(-4.8 * elapsed)
            cameraZoomVelocity *= damping

            let isAtZoomLimit = currentCameraDistance <= minimumCameraDistance + 0.001
                || currentCameraDistance >= maximumCameraDistance - 0.001
            if abs(cameraZoomVelocity) < 0.18 || isAtZoomLimit {
                stopZoomInertia()
                finishCameraInteraction()
            }
        }

        @objc private func stepCameraInertia(_ displayLink: CADisplayLink) {
            let timestamp = displayLink.timestamp
            let previousTimestamp = lastInertiaTimestamp ?? timestamp
            lastInertiaTimestamp = timestamp

            let elapsed = min(max(timestamp - previousTimestamp, 0), 1 / 30)
            guard elapsed > 0 else {
                return
            }

            applyTrackballDelta(CGPoint(
                x: cameraInertiaVelocity.x * elapsed,
                y: cameraInertiaVelocity.y * elapsed
            ))

            let damping = exp(-4.2 * elapsed)
            cameraInertiaVelocity *= damping

            if simd_length(cameraInertiaVelocity) < 8 {
                stopCameraInertia()
                finishCameraInteraction()
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard !isFollowingRocket else {
                return
            }

            guard let view = recognizer.view else {
                return
            }

            switch recognizer.state {
            case .began:
                beginCameraInteraction()
                panPreviousTranslation = .zero
            case .changed, .ended:
                let translation = recognizer.translation(in: view)
                let delta = CGPoint(
                    x: translation.x - panPreviousTranslation.x,
                    y: translation.y - panPreviousTranslation.y
                )
                panPreviousTranslation = translation
                applyTrackballDelta(delta)
                if recognizer.state == .ended {
                    startCameraInertia(with: recognizer.velocity(in: view))
                }
            case .cancelled, .failed:
                stopCameraInertia()
                finishCameraInteraction()
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard !isFollowingRocket else {
                return
            }

            switch recognizer.state {
            case .began:
                beginCameraInteraction()
                pinchStartDistance = currentCameraDistance
            case .changed, .ended:
                let scale = max(0.35, Double(recognizer.scale))
                let nextDistance = pinchStartDistance / scale
                currentCameraDistance = max(minimumCameraDistance, min(maximumCameraDistance, nextDistance))
                updateCamera(animated: false)
                if recognizer.state == .ended {
                    let zoomVelocity = -pinchStartDistance * Double(recognizer.velocity) / (scale * scale)
                    startZoomInertia(with: zoomVelocity)
                }
            case .cancelled, .failed:
                stopZoomInertia()
                finishCameraInteraction()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func updateVolumes(masterVolume: Float, missileVolume: Float, ambienceVolume: Float) {
            self.masterVolume = max(0, min(masterVolume, 1))
            self.missileVolume = max(0, min(missileVolume, 1))
            self.ambienceVolume = max(0, min(ambienceVolume, 1))
            ambiencePlayer?.volume = ambiencePlaybackVolume
        }

        func updatePaused(_ isPaused: Bool) {
            guard self.isPaused != isPaused else {
                return
            }

            self.isPaused = isPaused
            scene?.isPaused = isPaused

            if isPaused {
                missileTimer?.invalidate()
                missileTimer = nil
                ambiencePlayer?.pause()
                effectPlayers.forEach { $0.pause() }
            } else {
                ambiencePlayer?.play()
                effectPlayers.forEach { $0.play() }
                scheduleNextMissile()
            }
        }

        func shouldRebuildOrbitingRockets(rocketCount: Int, trailLength: Float) -> Bool {
            builtRocketCount != rocketCount || abs((builtTrailLength ?? -1) - trailLength) > 0.01
        }

        func markOrbitingRocketsBuilt(rocketCount: Int, trailLength: Float) {
            builtRocketCount = rocketCount
            builtTrailLength = trailLength
        }

        private var ambiencePlaybackVolume: Float {
            masterVolume * ambienceVolume * 0.36
        }

        private var missilePlaybackVolume: Float {
            masterVolume * missileVolume
        }

        private func startAmbience() {
            guard ambiencePlayer == nil,
                  let url = Bundle.main.url(forResource: "SpaceAmbience", withExtension: "wav", subdirectory: "Audio") else {
                return
            }

            do {
                try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)

                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = ambiencePlaybackVolume
                player.prepareToPlay()
                player.play()
                ambiencePlayer = player
            } catch {
                ambiencePlayer = nil
            }
        }

        private func scheduleNextMissile() {
            guard !isPaused else {
                return
            }

            missileTimer?.invalidate()
            missileTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 0.75...1.85), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.fireRandomMissile()
                    self?.scheduleNextMissile()
                }
            }
        }

        private func fireRandomMissile() {
            guard !isPaused, let scene else {
                return
            }

            let rockets = scene.rootNode.childNodes { node, _ in
                node.name == "rocket-firing-source"
            }
            guard let rocket = rockets.randomElement() else {
                return
            }

            let presentation = rocket.presentation
            let nose = presentation.convertPosition(SCNVector3(0, 1.02, 0), to: nil)
            let body = presentation.convertPosition(SCNVector3(0, 0.22, 0), to: nil)
            var direction = normalized(SCNVector3(nose.x - body.x, nose.y - body.y, nose.z - body.z))
            if direction.length < 0.01 {
                direction = SCNVector3(0, 1, 0)
            }

            let missile = missileNode()
            missile.transform = presentation.worldTransform
            missile.position = nose
            scene.rootNode.addChildNode(missile)

            let drift = SCNVector3(
                Float.random(in: -0.55...0.55),
                Float.random(in: -0.35...0.35),
                Float.random(in: -0.45...0.45)
            )
            let distance = Float.random(in: 2.5...4.7)
            let end = SCNVector3(
                nose.x + direction.x * distance + drift.x,
                nose.y + direction.y * distance + drift.y,
                nose.z + direction.z * distance + drift.z
            )
            let duration = TimeInterval.random(in: 0.72...1.15)

            playEffect(named: "MissileLaunch", volume: 0.62 * missilePlaybackVolume)
            playEffect(named: "MissileFlyby", volume: Bool.random() ? 0.28 * missilePlaybackVolume : 0.0)

            missile.runAction(.sequence([
                .group([
                    .move(to: end, duration: duration),
                    .scale(to: 0.58, duration: duration)
                ]),
                .fadeOut(duration: 0.16),
                .removeFromParentNode()
            ]))

            Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak scene] _ in
                Task { @MainActor [weak self, weak scene] in
                    self?.addMissileSpark(at: end, to: scene)
                }
            }
        }

        private func missileNode() -> SCNNode {
            let root = SCNNode()
            root.name = "missile"
            root.scale = SCNVector3(0.42, 0.42, 0.42)

            let body = SCNCylinder(radius: 0.045, height: 0.34)
            body.radialSegmentCount = 18
            body.materials = [missileMaterial(.systemYellow)]
            root.addChildNode(SCNNode(geometry: body))

            let nose = SCNCone(topRadius: 0, bottomRadius: 0.052, height: 0.13)
            nose.radialSegmentCount = 18
            nose.materials = [missileMaterial(.systemRed)]
            let noseNode = SCNNode(geometry: nose)
            noseNode.position = SCNVector3(0, 0.235, 0)
            root.addChildNode(noseNode)

            let engine = SCNCylinder(radius: 0.052, height: 0.06)
            engine.radialSegmentCount = 18
            engine.materials = [missileMaterial(.darkGray)]
            let engineNode = SCNNode(geometry: engine)
            engineNode.position = SCNVector3(0, -0.20, 0)
            root.addChildNode(engineNode)

            let trail = SCNNode()
            trail.position = SCNVector3(0, -0.28, 0)
            trail.addParticleSystem(missileTrailParticles())
            root.addChildNode(trail)

            return root
        }

        private func addMissileSpark(at position: SCNVector3, to scene: SCNScene?) {
            guard let scene else {
                return
            }

            let spark = SCNNode()
            spark.position = position
            spark.addParticleSystem(missileSparkParticles())
            scene.rootNode.addChildNode(spark)
            spark.runAction(.sequence([
                .wait(duration: 0.55),
                .removeFromParentNode()
            ]))
        }

        private func playEffect(named name: String, volume: Float) {
            guard !isPaused, volume > 0,
                  let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio") else {
                return
            }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = volume
                player.pan = Float.random(in: -0.35...0.35)
                player.prepareToPlay()
                player.play()
                effectPlayers.append(player)

                Timer.scheduledTimer(withTimeInterval: player.duration + 0.2, repeats: false) { [weak self, weak player] _ in
                    Task { @MainActor [weak self, weak player] in
                        guard let player else {
                            return
                        }
                        self?.effectPlayers.removeAll { $0 === player }
                    }
                }
            } catch {
                return
            }
        }

        private func missileTrailParticles() -> SCNParticleSystem {
            let particles = SCNParticleSystem()
            particles.birthRate = 95
            particles.loops = true
            particles.particleLifeSpan = 0.34
            particles.particleLifeSpanVariation = 0.12
            particles.particleSize = 0.06
            particles.particleSizeVariation = 0.03
            particles.particleImage = UIImage(named: "PremiumParticle")
            particles.particleColor = UIColor.systemOrange.withAlphaComponent(0.9)
            particles.particleColorVariation = SCNVector4(0.32, 0.18, 0.04, 0.2)
            particles.blendMode = .additive
            particles.emitterShape = SCNSphere(radius: 0.025)
            particles.birthDirection = .constant
            particles.emittingDirection = SCNVector3(0, -1, 0)
            particles.spreadingAngle = 18
            particles.particleVelocity = 0.24
            particles.particleVelocityVariation = 0.08
            particles.isAffectedByGravity = false
            particles.stretchFactor = 0.4
            return particles
        }

        private func missileSparkParticles() -> SCNParticleSystem {
            let particles = SCNParticleSystem()
            particles.birthRate = 460
            particles.loops = false
            particles.emissionDuration = 0.08
            particles.particleLifeSpan = 0.34
            particles.particleLifeSpanVariation = 0.16
            particles.particleSize = 0.085
            particles.particleSizeVariation = 0.05
            particles.particleImage = UIImage(named: "PremiumParticle")
            particles.particleColor = UIColor.systemYellow.withAlphaComponent(0.92)
            particles.particleColorVariation = SCNVector4(0.24, 0.18, 0.08, 0.32)
            particles.blendMode = .additive
            particles.emitterShape = SCNSphere(radius: 0.035)
            particles.spreadingAngle = 180
            particles.particleVelocity = 0.52
            particles.particleVelocityVariation = 0.38
            particles.isAffectedByGravity = false
            return particles
        }

        private func missileMaterial(_ color: UIColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.18)
            material.specular.contents = UIColor.white
            material.shininess = 0.8
            return material
        }

        private func normalized(_ vector: SCNVector3) -> SCNVector3 {
            let length = vector.length
            guard length > 0 else {
                return SCNVector3(0, 1, 0)
            }
            return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
        }
    }
}

private extension SCNVector3 {
    var length: Float {
        sqrt(x * x + y * y + z * z)
    }
}

private struct PauseButton: View {
    let isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Reprendre" : "Pause")
        .settingsButtonBackground()
    }
}

private struct FollowRocketButton: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFollowing ? "viewfinder.circle.fill" : "viewfinder")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Quitter le suivi" : "Suivre une fusee")
        .settingsButtonBackground()
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parametres")
        .settingsButtonBackground()
    }
}

private struct SettingsView: View {
    @Binding var masterVolume: Double
    @Binding var missileVolume: Double
    @Binding var ambienceVolume: Double
    @Binding var rocketCount: Int
    @Binding var trailLength: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Audio") {
                    VolumeSlider(
                        title: "Volume general",
                        systemName: "speaker.wave.2.fill",
                        value: $masterVolume
                    )
                    VolumeSlider(
                        title: "Missiles",
                        systemName: "scope",
                        value: $missileVolume
                    )
                    VolumeSlider(
                        title: "Ambiance",
                        systemName: "sparkles",
                        value: $ambienceVolume
                    )
                }

                Section("Scene") {
                    Stepper(value: $rocketCount, in: 1...50) {
                        SettingsValueRow(
                            title: "Fusees",
                            systemName: "paperplane.fill",
                            value: "\(rocketCount)"
                        )
                    }

                    SettingsSlider(
                        title: "Trainees",
                        systemName: "comet.fill",
                        valueText: String(format: "%.1fx", trailLength),
                        value: $trailLength,
                        bounds: 0.35...2.5
                    )
                }
            }
            .navigationTitle("Parametres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        dismiss()
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }
}

private struct VolumeSlider: View {
    let title: String
    let systemName: String
    @Binding var value: Double

    var body: some View {
        SettingsSlider(
            title: title,
            systemName: systemName,
            valueText: "\(Int((value * 100).rounded()))%",
            value: $value,
            bounds: 0...1
        )
    }
}

private struct SettingsSlider: View {
    let title: String
    let systemName: String
    let valueText: String
    @Binding var value: Double
    let bounds: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsValueRow(title: title, systemName: systemName, value: valueText)
            Slider(value: $value, in: bounds)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let systemName: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    @ViewBuilder
    func settingsButtonBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }
}

private extension SCNVector3 {
    var simdVector: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
