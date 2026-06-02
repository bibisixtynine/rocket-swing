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
    @AppStorage("padRingSpacing") private var padRingSpacing = 1.35
    @AppStorage("padLateralSpacing") private var padLateralSpacing = 0.45
    @State private var isShowingSettings = false
    @State private var isPaused = false
    @State private var isFollowingRocket = false
    @State private var autolandRequest = 0
    @State private var takeoffRequest = 0
    @State private var areRocketsLanded = true

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
                padRingSpacing: Float(padRingSpacing),
                padLateralSpacing: Float(padLateralSpacing),
                isPaused: isPaused,
                isFollowingRocket: isFollowingRocket,
                autolandRequest: autolandRequest,
                takeoffRequest: takeoffRequest,
                areRocketsLanded: $areRocketsLanded
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

                AutolandButton(isLanded: areRocketsLanded) {
                    if areRocketsLanded {
                        takeoffRequest += 1
                    } else {
                        autolandRequest += 1
                    }
                }
                .opacity(areRocketsLanded ? 0.58 : 1)
                .animation(
                    areRocketsLanded
                        ? .easeInOut(duration: 0.72).repeatForever(autoreverses: true)
                        : .default,
                    value: areRocketsLanded
                )

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
            padRingSpacing = min(max(padRingSpacing, 0), 3.0)
            padLateralSpacing = min(max(padLateralSpacing, 0), 3.0)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                masterVolume: $masterVolume,
                missileVolume: $missileVolume,
                ambienceVolume: $ambienceVolume,
                rocketCount: $rocketCount,
                trailLength: $trailLength,
                padRingSpacing: $padRingSpacing,
                padLateralSpacing: $padLateralSpacing
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
    private static let platformDiameter: Float = 1.0
    private static let platformDiskRadius: CGFloat = 0.5
    private static let platformDiskHeight: CGFloat = 0.16
    private static let lunarPlatformScale: Float = 0.68
    private static let lunarPadDiameter: Float = platformDiameter * lunarPlatformScale

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
    var padRingSpacing: Float
    var padLateralSpacing: Float
    var isPaused: Bool
    var isFollowingRocket: Bool
    var autolandRequest: Int
    var takeoffRequest: Int
    @Binding var areRocketsLanded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            cameraDistance: $cameraDistance,
            cameraYaw: $cameraYaw,
            cameraPitch: $cameraPitch,
            areRocketsLanded: $areRocketsLanded,
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
        context.coordinator.handleAutolandRequest(autolandRequest)
        context.coordinator.handleTakeoffRequest(takeoffRequest)

        let clampedRocketCount = max(1, min(rocketCount, 50))
        let clampedTrailLength = max(0.35, min(trailLength, 2.5))
        let clampedPadRingSpacing = max(0, min(padRingSpacing, 3.0))
        let clampedPadLateralSpacing = max(0, min(padLateralSpacing, 3.0))
        if context.coordinator.shouldRebuildOrbitingRockets(
            rocketCount: clampedRocketCount,
            trailLength: clampedTrailLength,
            padRingSpacing: clampedPadRingSpacing,
            padLateralSpacing: clampedPadLateralSpacing
        ), let scene = uiView.scene {
            rebuildOrbitingRockets(
                in: scene,
                rocketCount: clampedRocketCount,
                trailLength: clampedTrailLength,
                padRingSpacing: clampedPadRingSpacing,
                padLateralSpacing: clampedPadLateralSpacing
            )
            context.coordinator.markOrbitingRocketsBuilt(
                rocketCount: clampedRocketCount,
                trailLength: clampedTrailLength,
                padRingSpacing: clampedPadRingSpacing,
                padLateralSpacing: clampedPadLateralSpacing
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

        addCentralRocket(to: scene)

        addStarField(to: scene)
        let clampedRocketCount = max(1, min(rocketCount, 50))
        let clampedPadRingSpacing = max(0, min(padRingSpacing, 3.0))
        let clampedPadLateralSpacing = max(0, min(padLateralSpacing, 3.0))
        addLandingPlatforms(to: scene, count: clampedRocketCount, ringSpacing: clampedPadRingSpacing, lateralSpacing: clampedPadLateralSpacing)
        addOrbitingRockets(to: scene, rocketCount: clampedRocketCount, trailLength: max(0.35, min(trailLength, 2.5)))
        addLunarMissionWorld(to: scene, count: clampedRocketCount, ringSpacing: clampedPadRingSpacing, lateralSpacing: clampedPadLateralSpacing)
        placeRocketsOnInitialPlatforms(in: scene)

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

    private func rebuildOrbitingRockets(in scene: SCNScene, rocketCount: Int, trailLength: Float, padRingSpacing: Float, padLateralSpacing: Float) {
        scene.rootNode.childNode(withName: "orbiting-rockets", recursively: false)?.removeFromParentNode()
        scene.rootNode.childNode(withName: "landing-platforms", recursively: false)?.removeFromParentNode()
        scene.rootNode.childNodes { node, _ in
            node.name == "rocket-firing-source"
        }
        .forEach { $0.removeFromParentNode() }
        addCentralRocket(to: scene)
        addLandingPlatforms(to: scene, count: rocketCount, ringSpacing: padRingSpacing, lateralSpacing: padLateralSpacing)
        addOrbitingRockets(to: scene, rocketCount: rocketCount, trailLength: trailLength)
        addLunarMissionWorld(to: scene, count: rocketCount, ringSpacing: padRingSpacing, lateralSpacing: padLateralSpacing)
        placeRocketsOnInitialPlatforms(in: scene)
    }

    private func addCentralRocket(to scene: SCNScene) {
        let rocketNode = rocketNode(
            bodyColor: .white,
            accentColor: .systemRed,
            finColor: .systemBlue,
            scale: 0.62
        )
        rocketNode.name = "rocket-firing-source"
        rocketNode.setValue(NSNumber(value: 0), forKey: "rocketIndex")
        rocketNode.setValue(NSNumber(value: 0.74), forKey: "landingHeight")
        rocketNode.eulerAngles = SCNVector3Zero
        scene.rootNode.addChildNode(rocketNode)
    }

    private func placeRocketsOnInitialPlatforms(in scene: SCNScene) {
        let rockets = scene.rootNode.childNodes { node, _ in
            node.name == "rocket-firing-source"
        }
        .sorted { Self.rocketSortIndex(for: $0) < Self.rocketSortIndex(for: $1) }
        guard let platformGroup = scene.rootNode.childNode(withName: "landing-platforms", recursively: false) else {
            return
        }
        let platforms = Self.orderedPlatforms(in: platformGroup, named: "landing-platform")

        for (index, rocket) in rockets.enumerated() where index < platforms.count {
            rocket.removeAllActions()
            rocket.removeAllAnimations()
            Self.cutVisibleEngine(on: rocket)
            let platform = platforms[index]
            rocket.removeFromParentNode()
            platform.addChildNode(rocket)
            rocket.position = SCNVector3(0, Self.landingHeight(for: rocket), 0)
            rocket.simdOrientation = simd_quatf(angle: Float(index) * 0.73, axis: SIMD3<Float>(0, 1, 0))
            rocket.opacity = 1
        }
    }

    private func addLunarMissionWorld(to scene: SCNScene, count: Int, ringSpacing: Float, lateralSpacing: Float) {
        scene.rootNode.childNode(withName: "lunar-mission-world", recursively: false)?.removeFromParentNode()

        let world = SCNNode()
        world.name = "lunar-mission-world"
        world.position = SCNVector3(0, -3.4, -24)
        scene.rootNode.addChildNode(world)

        let moon = SCNSphere(radius: 4.2)
        moon.segmentCount = 64
        let moonMaterial = material(UIColor(red: 0.72, green: 0.68, blue: 0.53, alpha: 1))
        moonMaterial.emission.contents = UIColor(red: 0.10, green: 0.09, blue: 0.06, alpha: 1)
        moon.materials = [moonMaterial]
        let moonNode = SCNNode(geometry: moon)
        moonNode.name = "lunar-planet"
        world.addChildNode(moonNode)

        let base = SCNNode()
        base.name = "lunar-base"
        base.position = lunarSurfacePosition(x: 0, z: 1.2, lift: 0.05)
        base.simdOrientation = lunarSurfaceOrientation(x: 0, z: 1.2, yaw: 0)
        world.addChildNode(base)

        let dome = SCNSphere(radius: 0.82)
        dome.segmentCount = 40
        let domeMaterial = material(.systemCyan.withAlphaComponent(0.34))
        domeMaterial.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.25)
        domeMaterial.emission.contents = UIColor.systemCyan.withAlphaComponent(0.20)
        domeMaterial.transparency = 0.38
        dome.materials = [domeMaterial]
        let domeNode = SCNNode(geometry: dome)
        let domeFootingY: Float = -0.37
        let domeFootingRadius: CGFloat = 0.82 * 1.51
        domeNode.position = SCNVector3(0, domeFootingY, 0)
        domeNode.scale = SCNVector3(1.45, 0.58, 1.45)
        base.addChildNode(domeNode)
        addGlassFacetGrid(to: domeNode)
        addDomeFootingRing(to: base, radius: domeFootingRadius, y: domeFootingY)

        let habitatColors: [UIColor] = [.systemPink, .systemGreen, .systemYellow, .systemPurple, .systemOrange]
        for index in 0..<5 {
            let habitat = SCNSphere(radius: 0.22)
            habitat.segmentCount = 24
            habitat.materials = [material(habitatColors[index])]
            let node = SCNNode(geometry: habitat)
            let angle = Float(index) / 5 * Float.pi * 2
            node.position = SCNVector3(cos(angle) * 0.55, -0.18, sin(angle) * 0.38)
            node.scale = SCNVector3(1, 0.55, 1)
            base.addChildNode(node)
        }

        let lunarPads = SCNNode()
        lunarPads.name = "lunar-landing-platforms"
        world.addChildNode(lunarPads)
        for index in 0..<count {
            let pad = landingPlatformNode(index: index, accentColor: habitatColors[index % habitatColors.count], secondaryColor: .systemCyan)
            pad.name = "lunar-landing-platform"
            pad.setValue(NSNumber(value: index), forKey: "platformIndex")
            let layout = sphericalConcentricPadLayout(
                index: index,
                count: count,
                sphereRadius: 4.2,
                minimumRadius: Float(domeFootingRadius) + Self.lunarPadDiameter * 0.65,
                podDiameter: Self.lunarPadDiameter,
                ringSpacing: ringSpacing,
                lateralSpacing: lateralSpacing
            )
            let angle = layout.angle + 0.14
            let surface = lunarSurfacePointAroundBase(angle: angle, radius: layout.radius, lift: 0.025)
            pad.position = surface.position
            pad.simdOrientation = lunarSurfaceOrientation(normal: surface.normal, yaw: angle + Float.pi)
            pad.scale = SCNVector3(Self.lunarPlatformScale, Self.lunarPlatformScale, Self.lunarPlatformScale)
            pad.removeAllAnimations()
            lunarPads.addChildNode(pad)
        }
    }

    private func lunarSurfacePosition(x: Float, z: Float, lift: Float) -> SCNVector3 {
        let moonRadius: Float = 4.2
        let point = clampedLunarPlanePoint(x: x, z: z, moonRadius: moonRadius)
        let surfaceY = sqrt(max(0, moonRadius * moonRadius - point.x * point.x - point.z * point.z))
        return SCNVector3(point.x, surfaceY + lift, point.z)
    }

    private func lunarSurfaceOrientation(x: Float, z: Float, yaw: Float) -> simd_quatf {
        let moonRadius: Float = 4.2
        let point = clampedLunarPlanePoint(x: x, z: z, moonRadius: moonRadius)
        let surfaceY = sqrt(max(0, moonRadius * moonRadius - point.x * point.x - point.z * point.z))
        let normal = simd_normalize(SIMD3<Float>(point.x, surfaceY, point.z))
        return lunarSurfaceOrientation(normal: normal, yaw: yaw)
    }

    private func lunarSurfacePointAroundBase(angle: Float, radius: Float, lift: Float) -> (position: SCNVector3, normal: SIMD3<Float>) {
        let moonRadius: Float = 4.2
        let baseNormal = lunarBaseNormal(moonRadius: moonRadius)
        let tangentX = simd_normalize(SIMD3<Float>(1, 0, 0) - simd_dot(SIMD3<Float>(1, 0, 0), baseNormal) * baseNormal)
        let tangentZ = simd_normalize(simd_cross(baseNormal, tangentX))
        let tangentDirection = simd_normalize(cos(angle) * tangentX + sin(angle) * tangentZ)
        let surfaceAngle = min(radius / moonRadius, Float.pi * 0.82)
        let normal = simd_normalize(cos(surfaceAngle) * baseNormal + sin(surfaceAngle) * tangentDirection)
        let point = normal * (moonRadius + lift)
        return (SCNVector3(point.x, point.y, point.z), normal)
    }

    private func lunarBaseNormal(moonRadius: Float) -> SIMD3<Float> {
        let baseZ: Float = 1.2
        let baseY = sqrt(max(0, moonRadius * moonRadius - baseZ * baseZ))
        return simd_normalize(SIMD3<Float>(0, baseY, baseZ))
    }

    private func lunarSurfaceOrientation(normal: SIMD3<Float>, yaw: Float) -> simd_quatf {
        let tangentAlignment = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: normal)
        let spin = simd_quatf(angle: yaw, axis: normal)
        return simd_normalize(simd_mul(spin, tangentAlignment))
    }

    private func clampedLunarPlanePoint(x: Float, z: Float, moonRadius: Float) -> (x: Float, z: Float) {
        let maxPlaneRadius = moonRadius * 0.94
        let length = sqrt(x * x + z * z)
        guard length > maxPlaneRadius, length > 0 else {
            return (x, z)
        }

        let scale = maxPlaneRadius / length
        return (x * scale, z * scale)
    }

    private func addGlassFacetGrid(to dome: SCNNode) {
        let gridMaterial = material(UIColor.white.withAlphaComponent(0.72))
        gridMaterial.emission.contents = UIColor.systemCyan.withAlphaComponent(0.55)
        gridMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.62)

        for latitude in [0.24, 0.46, 0.66, 0.82] as [Float] {
            let ringRadius = CGFloat(0.82 * sqrt(max(0, 1 - latitude * latitude)))
            let ring = SCNTorus(ringRadius: ringRadius, pipeRadius: 0.006)
            ring.ringSegmentCount = 72
            ring.pipeSegmentCount = 6
            ring.materials = [gridMaterial]
            let ringNode = SCNNode(geometry: ring)
            ringNode.position = SCNVector3(0, 0.82 * latitude, 0)
            dome.addChildNode(ringNode)
        }

        for index in 0..<12 {
            let azimuth = Float(index) / 12 * Float.pi * 2
            let segmentCount = 8
            for segment in 0..<segmentCount {
                let startPolar = Float(segment) / Float(segmentCount) * Float.pi / 2
                let endPolar = Float(segment + 1) / Float(segmentCount) * Float.pi / 2
                let start = domePoint(radius: 0.82, polar: startPolar, azimuth: azimuth)
                let end = domePoint(radius: 0.82, polar: endPolar, azimuth: azimuth)
                dome.addChildNode(glassGridSegment(from: start, to: end, radius: 0.0055, material: gridMaterial))
            }
        }
    }

    private func addDomeFootingRing(to base: SCNNode, radius: CGFloat, y: Float) {
        let ringMaterial = material(UIColor.white.withAlphaComponent(0.78))
        ringMaterial.lightingModel = .constant
        ringMaterial.emission.contents = UIColor.systemCyan.withAlphaComponent(0.95)
        ringMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.82)

        let ring = SCNTorus(ringRadius: radius, pipeRadius: 0.018)
        ring.ringSegmentCount = 96
        ring.pipeSegmentCount = 8
        ring.materials = [ringMaterial]

        let ringNode = SCNNode(geometry: ring)
        ringNode.name = "dome-footing-ring"
        ringNode.position = SCNVector3(0, y + 0.018, 0)
        base.addChildNode(ringNode)
    }

    private func domePoint(radius: Float, polar: Float, azimuth: Float) -> SCNVector3 {
        SCNVector3(
            sin(polar) * radius * cos(azimuth),
            cos(polar) * radius,
            sin(polar) * radius * sin(azimuth)
        )
    }

    private func glassGridSegment(from start: SCNVector3, to end: SCNVector3, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let delta = end.simdVector - start.simdVector
        let length = CGFloat(simd_length(delta))
        let cylinder = SCNCylinder(radius: radius, height: length)
        cylinder.radialSegmentCount = 8
        cylinder.materials = [material]

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((start.simdVector + end.simdVector) * 0.5)
        if simd_length(delta) > 0 {
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        }
        return node
    }

    private func addLandingPlatforms(to scene: SCNScene, count: Int, ringSpacing: Float, lateralSpacing: Float) {
        let colors: [UIColor] = [
            .systemCyan,
            .systemPink,
            .systemYellow,
            .systemGreen,
            .systemOrange,
            .systemPurple,
            .systemBlue
        ]
        let platformGroup = SCNNode()
        platformGroup.name = "landing-platforms"
        scene.rootNode.addChildNode(platformGroup)

        for index in 0..<count {
            let color = colors[index % colors.count]
            let platform = landingPlatformNode(
                index: index,
                accentColor: color,
                secondaryColor: colors[(index + 3) % colors.count]
            )
            platform.setValue(NSNumber(value: index), forKey: "platformIndex")
            platform.position = initialPadPosition(index: index, count: count, ringSpacing: ringSpacing, lateralSpacing: lateralSpacing)
            platform.eulerAngles = SCNVector3(0, Float(index) / Float(max(1, count)) * Float.pi * 2 + Float.pi, 0)
            platformGroup.addChildNode(platform)
        }
    }

    private func initialPadPosition(index: Int, count: Int, ringSpacing: Float, lateralSpacing: Float) -> SCNVector3 {
        let layout = concentricPadLayout(
            index: index,
            count: count,
            hasCenterPod: true,
            minimumRadius: Self.platformDiameter * 1.15,
            podDiameter: Self.platformDiameter,
            ringSpacing: ringSpacing,
            lateralSpacing: lateralSpacing
        )
        let height = layout.ring == 0 ? 0 : sin(layout.angle * 1.7 + Float(layout.ring) * 0.41) * 0.46
        return SCNVector3(
            cos(layout.angle) * layout.radius,
            height,
            sin(layout.angle) * layout.radius
        )
    }

    private func concentricPadLayout(
        index: Int,
        count: Int,
        hasCenterPod: Bool,
        minimumRadius: Float,
        podDiameter: Float,
        ringSpacing: Float,
        lateralSpacing: Float
    ) -> (angle: Float, radius: Float, ring: Int) {
        if hasCenterPod && index == 0 {
            return (0, 0, 0)
        }

        let centerDistance = podDiameter * (1 + max(0, min(lateralSpacing, 3.0)))
        let ringStep = podDiameter * (1 + max(0, min(ringSpacing, 3.0)))
        let adjustedIndex = hasCenterPod ? index - 1 : index
        let totalRingPods = max(0, count - (hasCenterPod ? 1 : 0))
        var ring = 0
        var remainingBeforeRing = adjustedIndex
        var radius = minimumRadius
        var capacity = max(1, Int(floor((Float.pi * 2 * radius) / centerDistance)))
        while remainingBeforeRing >= capacity {
            remainingBeforeRing -= capacity
            ring += 1
            radius = minimumRadius + Float(ring) * ringStep
            capacity = max(1, Int(floor((Float.pi * 2 * radius) / centerDistance)))
        }

        let remainingOnRing = max(1, totalRingPods - (adjustedIndex - remainingBeforeRing))
        let slotsOnRing = min(capacity, remainingOnRing)
        let slot = remainingBeforeRing
        let angle = Float(slot) / Float(slotsOnRing) * Float.pi * 2 + Float(ring) * 0.19
        return (angle, radius, ring + (hasCenterPod ? 1 : 0))
    }

    private func sphericalConcentricPadLayout(
        index: Int,
        count: Int,
        sphereRadius: Float,
        minimumRadius: Float,
        podDiameter: Float,
        ringSpacing: Float,
        lateralSpacing: Float
    ) -> (angle: Float, radius: Float, ring: Int) {
        let centerDistance = podDiameter * (1 + max(0, min(lateralSpacing, 3.0)))
        let ringStep = podDiameter * (1 + max(0, min(ringSpacing, 3.0)))
        let safeSphereRadius = max(sphereRadius, 0.1)
        let maxSurfaceRadius = safeSphereRadius * 1.45
        var ring = 0
        var remainingBeforeRing = index
        var radius = minimumRadius
        var capacity = sphericalRingCapacity(surfaceRadius: radius, sphereRadius: safeSphereRadius, centerDistance: centerDistance)

        while remainingBeforeRing >= capacity {
            remainingBeforeRing -= capacity
            ring += 1
            radius = min(minimumRadius + Float(ring) * ringStep, maxSurfaceRadius)
            capacity = sphericalRingCapacity(surfaceRadius: radius, sphereRadius: safeSphereRadius, centerDistance: centerDistance)
        }

        let usedBeforeRing = index - remainingBeforeRing
        let remainingOnRing = max(1, count - usedBeforeRing)
        let slotsOnRing = min(capacity, remainingOnRing)
        let angleStep = Float.pi * 2 / Float(slotsOnRing)
        let stagger = (ring % 2 == 0 ? 0 : angleStep * 0.5) + Float(ring) * 0.11
        let angle = Float(remainingBeforeRing) * angleStep + stagger
        return (angle, radius, ring)
    }

    private func sphericalRingCapacity(surfaceRadius: Float, sphereRadius: Float, centerDistance: Float) -> Int {
        let theta = min(max(surfaceRadius / sphereRadius, 0.02), Float.pi * 0.48)
        let circumference = Float.pi * 2 * sphereRadius * sin(theta)
        return max(1, Int(floor(circumference / max(centerDistance, 0.1))))
    }

    private func landingPlatformNode(index: Int, accentColor: UIColor, secondaryColor: UIColor) -> SCNNode {
        let root = SCNNode()
        root.name = "landing-platform"

        let diskRadius = Self.platformDiskRadius
        let diskHeight = Self.platformDiskHeight
        let disk = SCNCylinder(radius: diskRadius, height: diskHeight)
        disk.radialSegmentCount = 64
        disk.materials = [
            platformTopMaterial(accentColor),
            platformTopMaterial(accentColor),
            platformSideMaterial(secondaryColor)
        ]
        let diskNode = SCNNode(geometry: disk)
        root.addChildNode(diskNode)

        let inset = SCNCylinder(radius: diskRadius * 0.62, height: diskHeight + 0.01)
        inset.radialSegmentCount = 64
        let insetMaterial = material(UIColor(white: 0.06, alpha: 1))
        insetMaterial.emission.contents = accentColor.withAlphaComponent(0.08)
        inset.materials = [insetMaterial]
        let insetNode = SCNNode(geometry: inset)
        insetNode.position = SCNVector3(0, Float(diskHeight) * 0.54, 0)
        root.addChildNode(insetNode)

        let ring = SCNTorus(ringRadius: diskRadius * 0.78, pipeRadius: 0.012)
        ring.ringSegmentCount = 80
        ring.pipeSegmentCount = 8
        let ringMaterial = material(accentColor)
        ringMaterial.emission.contents = accentColor.withAlphaComponent(0.48)
        ring.materials = [ringMaterial]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = SCNVector3(0, Float(diskHeight) * 0.62, 0)
        root.addChildNode(ringNode)

        addPlatformEdgeLights(
            to: root,
            index: index,
            radius: Float(diskRadius) + 0.012,
            height: Float(diskHeight) * 0.18,
            accentColor: accentColor,
            secondaryColor: secondaryColor
        )

        let hover = CABasicAnimation(keyPath: "position.y")
        hover.fromValue = -0.045
        hover.toValue = 0.045
        hover.duration = CFTimeInterval.random(in: 1.8...3.2)
        hover.autoreverses = true
        hover.repeatCount = .infinity
        hover.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hover.beginTime = CACurrentMediaTime() + CFTimeInterval(index) * 0.11
        root.addAnimation(hover, forKey: "platform-hover")

        return root
    }

    private func addPlatformEdgeLights(
        to platform: SCNNode,
        index: Int,
        radius: Float,
        height: Float,
        accentColor: UIColor,
        secondaryColor: UIColor
    ) {
        let lightCount = 8
        for lightIndex in 0..<lightCount {
            let color = lightIndex.isMultiple(of: 2) ? accentColor : secondaryColor
            let bulb = SCNSphere(radius: 0.035)
            bulb.segmentCount = 12
            let bulbMaterial = material(color)
            bulbMaterial.emission.contents = color
            bulbMaterial.lightingModel = .constant
            bulb.materials = [bulbMaterial]

            let angle = Float(lightIndex) / Float(lightCount) * Float.pi * 2
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.name = "platform-edge-light"
            bulbNode.position = SCNVector3(cos(angle) * radius, height, sin(angle) * radius)
            platform.addChildNode(bulbNode)

            let point = SCNLight()
            point.type = .omni
            point.color = color
            point.intensity = 35
            point.attenuationStartDistance = 0.05
            point.attenuationEndDistance = 1.15
            let pointNode = SCNNode()
            pointNode.light = point
            bulbNode.addChildNode(pointNode)

            let blink = CABasicAnimation(keyPath: "opacity")
            blink.fromValue = 0.24
            blink.toValue = 1.0
            blink.duration = CFTimeInterval.random(in: 0.34...0.86)
            blink.autoreverses = true
            blink.repeatCount = .infinity
            blink.beginTime = CACurrentMediaTime() + CFTimeInterval(index + lightIndex) * 0.09
            bulbNode.addAnimation(blink, forKey: "edge-light-blink")

            let lightPulse = CABasicAnimation(keyPath: "light.intensity")
            lightPulse.fromValue = 10
            lightPulse.toValue = 58
            lightPulse.duration = blink.duration
            lightPulse.autoreverses = true
            lightPulse.repeatCount = .infinity
            lightPulse.beginTime = blink.beginTime
            pointNode.addAnimation(lightPulse, forKey: "edge-light-intensity")
        }
    }

    private func platformTopMaterial(_ color: UIColor) -> SCNMaterial {
        let material = self.material(UIColor(white: 0.12, alpha: 1))
        material.emission.contents = color.withAlphaComponent(0.10)
        material.metalness.contents = 0.72
        material.roughness.contents = 0.28
        return material
    }

    private func platformSideMaterial(_ color: UIColor) -> SCNMaterial {
        let material = self.material(UIColor(white: 0.04, alpha: 1))
        material.emission.contents = color.withAlphaComponent(0.24)
        material.metalness.contents = 0.88
        material.roughness.contents = 0.18
        return material
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
            satellite.setValue(index + 1, forKey: "rocketIndex")
            satellite.setValue(0.40 as Float, forKey: "landingHeight")
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
        flame.name = "engine-flame"
        flame.position = SCNVector3(0, -1.13, 0)
        rocket.addChildNode(flame)

        let emitter = SCNNode()
        emitter.name = "engine-trail"
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
        glowNode.name = "engine-glow"
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
            rememberBaseScale(for: root)
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

        rememberBaseScale(for: root)
        return root
    }

    private func rememberBaseScale(for rocket: SCNNode) {
        rocket.setValue(NSValue(scnVector3: rocket.scale), forKey: "baseRocketScale")
    }

    private func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor.white
        material.shininess = 0.45
        material.isDoubleSided = true
        return material
    }

    nonisolated private static func landingHeight(for rocket: SCNNode) -> Float {
        if let value = rocket.value(forKey: "landingHeight") as? Float {
            return value
        }

        if let value = rocket.value(forKey: "landingHeight") as? NSNumber {
            return value.floatValue
        }

        return rocket.scale.x > 0.4 ? 0.74 : 0.40
    }

    nonisolated private static func rocketSortIndex(for rocket: SCNNode) -> Int {
        if let value = rocket.value(forKey: "rocketIndex") as? Int {
            return value
        }

        if let value = rocket.value(forKey: "rocketIndex") as? NSNumber {
            return value.intValue
        }

        return Int.max
    }

    nonisolated private static func platformSortIndex(for platform: SCNNode) -> Int {
        if let value = platform.value(forKey: "platformIndex") as? Int {
            return value
        }

        if let value = platform.value(forKey: "platformIndex") as? NSNumber {
            return value.intValue
        }

        return Int.max
    }

    nonisolated private static func orderedPlatforms(in group: SCNNode, named name: String) -> [SCNNode] {
        group.childNodes
            .filter { $0.name == name }
            .sorted { platformSortIndex(for: $0) < platformSortIndex(for: $1) }
    }

    nonisolated private static func cutVisibleEngine(on rocket: SCNNode) {
        rocket.enumerateChildNodes { child, _ in
            if child.name == "engine-trail" || child.name == "engine-flame" || child.name == "engine-glow" {
                child.removeAllActions()
                child.removeFromParentNode()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private enum MissionPhase {
            case homeLanded
            case outbound
            case lunarLanded
            case inbound
        }

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
        private var followCameraPosition: SIMD3<Float>?
        private var followCameraLookTarget: SIMD3<Float>?
        private var followCameraUp: SIMD3<Float>?
        private var masterVolume: Float = 0.8
        private var missileVolume: Float = 0.85
        private var ambienceVolume: Float = 0.65
        private var builtRocketCount: Int?
        private var builtTrailLength: Float?
        private var builtPadRingSpacing: Float?
        private var builtPadLateralSpacing: Float?
        private var isPaused = false
        private var isAutolanding = false
        private var missionPhase: MissionPhase = .homeLanded
        private var lastAutolandRequest = 0
        private var lastTakeoffRequest = 0
        private var cameraDistance: Binding<Double>
        private var cameraYaw: Binding<Double>
        private var cameraPitch: Binding<Double>
        private var areRocketsLanded: Binding<Bool>
        private let minimumCameraDistance: Double
        private let maximumCameraDistance: Double
        private var currentCameraDistance: Double
        private var currentCameraYaw: Double
        private var currentCameraPitch: Double
        private var cameraOrientation: simd_quatd
        private var cameraFocusCenter = SIMD3<Double>(repeating: 0)
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
            areRocketsLanded: Binding<Bool>,
            minimumCameraDistance: Double,
            maximumCameraDistance: Double
        ) {
            self.cameraDistance = cameraDistance
            self.cameraYaw = cameraYaw
            self.cameraPitch = cameraPitch
            self.areRocketsLanded = areRocketsLanded
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
            setRocketsLanded(true)
            if !isPaused && !areRocketsLanded.wrappedValue {
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
            let position = SCNVector3(
                Float(cameraFocusCenter.x + offset.x),
                Float(cameraFocusCenter.y + offset.y),
                Float(cameraFocusCenter.z + offset.z)
            )

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
                followedRocket = randomRocket()
                startFollowCamera()
            } else {
                stopFollowCamera()
                followedRocket = nil
                followCameraPosition = nil
                followCameraLookTarget = nil
                followCameraUp = nil
                updateCamera(animated: true)
            }
        }

        func handleAutolandRequest(_ request: Int) {
            guard request != lastAutolandRequest else {
                return
            }

            lastAutolandRequest = request
            beginAutoland()
        }

        func handleTakeoffRequest(_ request: Int) {
            guard request != lastTakeoffRequest else {
                return
            }

            lastTakeoffRequest = request
            beginTakeoff()
        }

        private func beginAutoland() {
            guard let scene else {
                return
            }

            isAutolanding = true
            setRocketsLanded(false)
            missileTimer?.invalidate()
            missileTimer = nil

            let rockets = orderedRockets(in: scene)
            let platforms = orderedLandingPlatforms(in: scene)
            guard !rockets.isEmpty, !platforms.isEmpty else {
                return
            }

            var longestLandingDuration: TimeInterval = 0
            for (index, rocket) in rockets.enumerated() {
                guard index < platforms.count else {
                    break
                }

                let presentationTransform = rocket.presentation.worldTransform
                rocket.removeAllActions()
                rocket.removeAllAnimations()
                rocket.transform = presentationTransform
                rocket.opacity = 1

                let platform = platforms[index]
                let platformPosition = platform.presentation.worldPosition
                let landingHeight = RocketSceneView.landingHeight(for: rocket)
                let hoverHeight: Float = landingHeight > 0.6 ? 2.25 : 1.35
                let hoverPosition = SCNVector3(
                    platformPosition.x,
                    platformPosition.y + hoverHeight,
                    platformPosition.z
                )
                let yaw = Float(index) * 0.73
                let approachDuration = TimeInterval(2.35 + Double(index % 5) * 0.22)
                let descentDuration = TimeInterval(1.95 + Double(index % 4) * 0.16)
                let delay = TimeInterval(index) * 0.08
                longestLandingDuration = max(longestLandingDuration, delay + approachDuration + 0.08 + descentDuration)

                let startPosition = rocket.presentation.worldPosition
                let startOrientation = rocket.presentation.simdWorldOrientation
                let startForward = Self.rocketForward(for: rocket)
                let uprightOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
                let travelDistance = max(1.4, simd_length(hoverPosition.simdVector - startPosition.simdVector))
                let controlA = startPosition.simdVector + startForward * min(travelDistance * 0.42, 2.4)
                    + SIMD3<Float>(0, 0.55, 0)
                let controlB = hoverPosition.simdVector + SIMD3<Float>(0, 0.82 + Float(index % 3) * 0.16, 0)
                let approach = Self.guidedCurveAction(
                    from: startPosition,
                    to: hoverPosition,
                    controlA: SCNVector3(controlA),
                    controlB: SCNVector3(controlB),
                    startOrientation: startOrientation,
                    finalOrientation: uprightOrientation,
                    finalOrientationBlendStart: 0.54,
                    duration: approachDuration
                )
                let descend = Self.verticalLandingAction(
                    from: hoverPosition,
                    platform: platform,
                    landingHeight: landingHeight,
                    orientation: uprightOrientation,
                    duration: descentDuration
                )

                rocket.runAction(.sequence([
                    .wait(duration: delay),
                    approach,
                    .wait(duration: 0.08),
                    descend,
                    .run { node in
                        Self.cutEngine(on: node)
                        Self.attachLandedRocket(
                            node,
                            to: platform,
                            landingHeight: landingHeight,
                            orientation: uprightOrientation
                        )
                    }
                ]), forKey: "autoland")
            }

            Task { @MainActor [weak self] in
                let delay = UInt64((longestLandingDuration + 0.35) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard let self, self.isAutolanding else {
                    return
                }

                self.setRocketsLanded(true)
            }
        }

        private func beginTakeoff() {
            guard let scene else {
                return
            }

            isAutolanding = false
            setRocketsLanded(false)
            scheduleNextMissile()

            let rockets = orderedRockets(in: scene)
            let isReturningHome = missionPhase == .lunarLanded
            missionPhase = isReturningHome ? .inbound : .outbound
            let destinationPads = isReturningHome ? orderedLandingPlatforms(in: scene) : orderedLunarLandingPlatforms(in: scene)
            let colors: [UIColor] = [
                .systemRed,
                .systemOrange,
                .systemMint,
                .systemPurple,
                .systemCyan,
                .systemIndigo
            ]

            var longestTakeoffDuration: TimeInterval = 0
            for (index, rocket) in rockets.enumerated() {
                guard index < destinationPads.count else {
                    break
                }

                let currentTransform = rocket.presentation.worldTransform
                rocket.removeAllActions()
                rocket.removeAllAnimations()
                if rocket.parent?.name == "landing-platform" || rocket.parent?.name == "lunar-landing-platform" {
                    rocket.removeFromParentNode()
                    scene.rootNode.addChildNode(rocket)
                }
                rocket.transform = currentTransform
                Self.restoreBaseScale(on: rocket)
                rocket.opacity = 1
                rocket.setValue(NSNumber(value: 0), forKey: "followCameraStage")
                rocket.setValue(NSNumber(value: 0), forKey: "missionProgress")
                rocket.setValue(false, forKey: "isLandingDescent")
                rocket.setValue(0 as Float, forKey: "landingProgress")
                Self.restoreEngine(on: rocket, color: colors[index % colors.count])

                let currentPosition = rocket.presentation.worldPosition
                let destinationPad = destinationPads[index]
                let landingHeight = RocketSceneView.landingHeight(for: rocket)
                let targetPosition = destinationPad.presentation.convertPosition(
                    SCNVector3(0, landingHeight + 0.78, 0),
                    to: nil
                )
                let localLandingYaw = simd_quatf(angle: Float(index) * 0.55, axis: SIMD3<Float>(0, 1, 0))
                let targetOrientation = simd_normalize(simd_mul(destinationPad.presentation.simdWorldOrientation, localLandingYaw))
                let delay = TimeInterval(index) * 0.06
                let liftoffDuration = TimeInterval(0.85 + Double(index % 3) * 0.06)
                let cruiseDuration = TimeInterval(6.4 + Double(index % 5) * 0.34)
                let descentDuration = TimeInterval(1.45 + Double(index % 4) * 0.12)
                longestTakeoffDuration = max(longestTakeoffDuration, delay + liftoffDuration + cruiseDuration + descentDuration)

                let startOrientation = rocket.presentation.simdWorldOrientation
                let launchDirection = simd_normalize(startOrientation.act(SIMD3<Float>(0, 1, 0)))
                let liftoffDistance: Float = landingHeight > 0.6 ? 2.25 : 1.35
                let liftoffPosition = SCNVector3(currentPosition.simdVector + launchDirection * liftoffDistance)
                let travelDistance = max(1.4, simd_length(targetPosition.simdVector - liftoffPosition.simdVector))
                let lateral = simd_normalize(SIMD3<Float>(1.0 + Float(index % 3) * 0.35, 0.2, 0.45))
                let directionSign: Float = isReturningHome ? 1 : -1
                let controlA = liftoffPosition.simdVector + launchDirection * min(travelDistance * 0.18, 2.2)
                    + SIMD3<Float>(0, min(travelDistance * 0.12, 2.4), directionSign * min(travelDistance * 0.28, 6.2))
                    + lateral * Float(index % 2 == 0 ? 1.2 : -1.2)
                let controlB = targetPosition.simdVector + SIMD3<Float>(0, 1.8, -directionSign * 4.4)
                    - lateral * Float(index % 2 == 0 ? 1.4 : -1.4)
                let liftoff = Self.verticalTakeoffAction(
                    from: currentPosition,
                    to: liftoffPosition,
                    orientation: startOrientation,
                    duration: liftoffDuration
                )
                let cruise = Self.missionFlightAction(
                    from: liftoffPosition,
                    to: targetPosition,
                    controlA: SCNVector3(controlA),
                    controlB: SCNVector3(controlB),
                    startOrientation: startOrientation,
                    finalOrientation: targetOrientation,
                    wobbleSeed: Float(index) * 1.17,
                    duration: cruiseDuration
                )
                let descent = Self.verticalLandingAction(
                    from: targetPosition,
                    platform: destinationPad,
                    landingHeight: landingHeight,
                    orientation: targetOrientation,
                    duration: descentDuration
                )

                rocket.runAction(.sequence([
                    .wait(duration: delay),
                    liftoff,
                    cruise,
                    descent,
                    .run { node in
                        Self.cutEngine(on: node)
                        Self.attachLandedRocket(
                            node,
                            to: destinationPad,
                            landingHeight: landingHeight,
                            orientation: targetOrientation
                        )
                    }
                ]), forKey: "mission-one")
            }

            Task { @MainActor [weak self] in
                let delay = UInt64((longestTakeoffDuration + 0.45) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !self.isAutolanding else {
                    return
                }

                self.missileTimer?.invalidate()
                self.missileTimer = nil
                self.missionPhase = isReturningHome ? .homeLanded : .lunarLanded
                self.setRocketsLanded(true)
            }

            Task { @MainActor [weak self] in
                let delay = UInt64((longestTakeoffDuration * 0.48) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard let self else {
                    return
                }

                self.moveFreeCameraToMissionObservation(returningHome: isReturningHome)
            }
        }

        private func setRocketsLanded(_ isLanded: Bool) {
            guard areRocketsLanded.wrappedValue != isLanded else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.areRocketsLanded.wrappedValue = isLanded
            }
        }

        private func moveFreeCameraToMissionObservation(returningHome: Bool) {
            guard !isFollowingRocket else {
                return
            }

            if returningHome {
                cameraFocusCenter = SIMD3<Double>(repeating: 0)
                currentCameraDistance = min(maximumCameraDistance, 9.5)
                cameraOrientation = Self.makeCameraOrientation(yaw: -0.35, pitch: -0.78)
            } else if let center = lunarWorldCenter() {
                cameraFocusCenter = SIMD3<Double>(Double(center.x), Double(center.y), Double(center.z))
                currentCameraDistance = min(maximumCameraDistance, 8.2)
                cameraOrientation = Self.makeCameraOrientation(yaw: 0.22, pitch: -1.05)
            }
            updateCamera(animated: true)
        }

        private func lunarWorldCenter() -> SCNVector3? {
            scene?.rootNode.childNode(withName: "lunar-planet", recursively: true)?.presentation.worldPosition
        }

        private func orderedRockets(in scene: SCNScene) -> [SCNNode] {
            let allRockets = scene.rootNode.childNodes { node, _ in
                node.name == "rocket-firing-source"
            }
            return allRockets.sorted { RocketSceneView.rocketSortIndex(for: $0) < RocketSceneView.rocketSortIndex(for: $1) }
        }

        private func orderedLandingPlatforms(in scene: SCNScene) -> [SCNNode] {
            guard let platformGroup = scene.rootNode.childNode(withName: "landing-platforms", recursively: false) else {
                return []
            }

            return RocketSceneView.orderedPlatforms(in: platformGroup, named: "landing-platform")
        }

        private func orderedLunarLandingPlatforms(in scene: SCNScene) -> [SCNNode] {
            guard let lunarPads = scene.rootNode.childNode(withName: "lunar-landing-platforms", recursively: true) else {
                return []
            }

            return RocketSceneView.orderedPlatforms(in: lunarPads, named: "lunar-landing-platform")
        }

        nonisolated private static func guidedCurveAction(
            from start: SCNVector3,
            to end: SCNVector3,
            controlA: SCNVector3,
            controlB: SCNVector3,
            startOrientation: simd_quatf,
            finalOrientation: simd_quatf,
            finalOrientationBlendStart: Float,
            duration: TimeInterval
        ) -> SCNAction {
            SCNAction.customAction(duration: duration) { node, elapsed in
                let rawProgress = Float(elapsed / CGFloat(duration))
                let progress = smoothstep(rawProgress)
                let position = cubicBezier(
                    start: start.simdVector,
                    controlA: controlA.simdVector,
                    controlB: controlB.simdVector,
                    end: end.simdVector,
                    progress: progress
                )
                let tangent = cubicBezierTangent(
                    start: start.simdVector,
                    controlA: controlA.simdVector,
                    controlB: controlB.simdVector,
                    end: end.simdVector,
                    progress: progress
                )
                let tangentOrientation = orientationFollowing(direction: tangent, fallback: startOrientation)
                let launchBlend = smoothstep(min(rawProgress / 0.22, 1))
                var orientation = simd_slerp(startOrientation, tangentOrientation, launchBlend)

                if rawProgress > finalOrientationBlendStart {
                    let blend = smoothstep((rawProgress - finalOrientationBlendStart) / max(0.01, 1 - finalOrientationBlendStart))
                    orientation = simd_slerp(orientation, finalOrientation, blend)
                }

                node.position = SCNVector3(position)
                node.simdOrientation = simd_normalize(orientation)
            }
        }

        nonisolated private static func missionFlightAction(
            from start: SCNVector3,
            to end: SCNVector3,
            controlA: SCNVector3,
            controlB: SCNVector3,
            startOrientation: simd_quatf,
            finalOrientation: simd_quatf,
            wobbleSeed: Float,
            duration: TimeInterval
        ) -> SCNAction {
            SCNAction.customAction(duration: duration) { node, elapsed in
                let rawProgress = Float(elapsed / CGFloat(duration))
                let progress = smoothstep(rawProgress)
                node.setValue(NSNumber(value: rawProgress), forKey: "missionProgress")
                let followStage = rawProgress < 0.34 ? 0 : (rawProgress > 0.68 ? 2 : 1)
                node.setValue(NSNumber(value: followStage), forKey: "followCameraStage")
                var position = cubicBezier(
                    start: start.simdVector,
                    controlA: controlA.simdVector,
                    controlB: controlB.simdVector,
                    end: end.simdVector,
                    progress: progress
                )
                let wobbleEnvelope = smoothstep(min(rawProgress / 0.22, 1)) * (1 - rawProgress)
                let zigzag = sin(rawProgress * Float.pi * 8.0 + wobbleSeed) * wobbleEnvelope * 0.55
                let bob = sin(rawProgress * Float.pi * 5.0 + wobbleSeed * 0.4) * wobbleEnvelope * 0.22
                position += SIMD3<Float>(zigzag, bob, 0)

                let tangent = cubicBezierTangent(
                    start: start.simdVector,
                    controlA: controlA.simdVector,
                    controlB: controlB.simdVector,
                    end: end.simdVector,
                    progress: progress
                ) + SIMD3<Float>(cos(rawProgress * Float.pi * 8.0 + wobbleSeed) * wobbleEnvelope * 0.65, 0, 0)
                let tangentOrientation = orientationFollowing(direction: tangent, fallback: startOrientation)
                let launchBlend = smoothstep(min(rawProgress / 0.18, 1))
                var orientation = simd_slerp(startOrientation, tangentOrientation, launchBlend)

                let pirouetteWindow = max(0, 1 - abs(rawProgress - 0.48) / 0.14)
                if pirouetteWindow > 0.001 {
                    let direction = simd_length(tangent) > 0.001 ? simd_normalize(tangent) : SIMD3<Float>(0, 1, 0)
                    let roll = simd_quatf(angle: pirouetteWindow * Float.pi * 2.0, axis: direction)
                    orientation = simd_mul(roll, orientation)
                }

                if rawProgress > 0.76 {
                    let blend = smoothstep((rawProgress - 0.76) / 0.24)
                    orientation = simd_slerp(orientation, finalOrientation, blend)
                }

                node.position = SCNVector3(position)
                node.simdOrientation = simd_normalize(orientation)
            }
        }

        nonisolated private static func verticalTakeoffAction(
            from start: SCNVector3,
            to end: SCNVector3,
            orientation: simd_quatf,
            duration: TimeInterval
        ) -> SCNAction {
            SCNAction.customAction(duration: duration) { node, elapsed in
                let rawProgress = Float(elapsed / CGFloat(duration))
                let progress = smoothstep(rawProgress)
                node.setValue(NSNumber(value: 0), forKey: "followCameraStage")
                node.setValue(NSNumber(value: rawProgress), forKey: "missionProgress")
                node.position = mix(currentPosition: start, targetPosition: end, progress: progress)
                node.simdOrientation = orientation
            }
        }

        nonisolated private static func verticalLandingAction(
            from start: SCNVector3,
            platform: SCNNode,
            landingHeight: Float,
            orientation: simd_quatf,
            duration: TimeInterval
        ) -> SCNAction {
            SCNAction.customAction(duration: duration) { node, elapsed in
                let rawProgress = Float(elapsed / CGFloat(duration))
                let progress = smoothstep(rawProgress)
                node.setValue(NSNumber(value: 3), forKey: "followCameraStage")
                node.setValue(progress, forKey: "landingProgress")
                node.setValue(true, forKey: "isLandingDescent")
                let movingLandingPosition = platform.presentation.convertPosition(
                    SCNVector3(0, landingHeight, 0),
                    to: nil
                )
                node.position = mix(currentPosition: start, targetPosition: movingLandingPosition, progress: progress)
                node.simdOrientation = orientation
            }
        }

        nonisolated private static func attachLandedRocket(
            _ rocket: SCNNode,
            to platform: SCNNode,
            landingHeight: Float,
            orientation: simd_quatf
        ) {
            rocket.removeFromParentNode()
            platform.addChildNode(rocket)
            rocket.position = SCNVector3(0, landingHeight, 0)
            rocket.simdOrientation = simd_normalize(simd_inverse(platform.presentation.simdWorldOrientation) * orientation)
            let baseScale = baseScale(for: rocket)
            let parentScale = worldScale(of: platform.presentation)
            rocket.scale = SCNVector3(
                baseScale.x / max(parentScale.x, 0.001),
                baseScale.y / max(parentScale.y, 0.001),
                baseScale.z / max(parentScale.z, 0.001)
            )
            rocket.setValue(false, forKey: "isLandingDescent")
            rocket.setValue(1 as Float, forKey: "landingProgress")
        }

        nonisolated private static func restoreBaseScale(on rocket: SCNNode) {
            rocket.scale = baseScale(for: rocket)
        }

        nonisolated private static func baseScale(for rocket: SCNNode) -> SCNVector3 {
            if let value = rocket.value(forKey: "baseRocketScale") as? NSValue {
                return value.scnVector3Value
            }

            let current = rocket.scale
            rocket.setValue(NSValue(scnVector3: current), forKey: "baseRocketScale")
            return current
        }

        nonisolated private static func worldScale(of node: SCNNode) -> SCNVector3 {
            let transform = node.worldTransform
            let x = sqrt(transform.m11 * transform.m11 + transform.m12 * transform.m12 + transform.m13 * transform.m13)
            let y = sqrt(transform.m21 * transform.m21 + transform.m22 * transform.m22 + transform.m23 * transform.m23)
            let z = sqrt(transform.m31 * transform.m31 + transform.m32 * transform.m32 + transform.m33 * transform.m33)
            return SCNVector3(x, y, z)
        }

        nonisolated private static func rocketForward(for rocket: SCNNode) -> SIMD3<Float> {
            let presentation = rocket.presentation
            let nose = presentation.convertPosition(SCNVector3(0, 1.02, 0), to: nil).simdVector
            let tail = presentation.convertPosition(SCNVector3(0, -0.82, 0), to: nil).simdVector
            let forward = nose - tail
            if simd_length(forward) < 0.001 {
                return SIMD3<Float>(0, 1, 0)
            }
            return simd_normalize(forward)
        }

        nonisolated private static func orientationFollowing(
            direction: SIMD3<Float>,
            fallback: simd_quatf
        ) -> simd_quatf {
            guard simd_length(direction) > 0.001 else {
                return fallback
            }

            return simd_normalize(simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(direction)))
        }

        nonisolated private static func cubicBezier(
            start: SIMD3<Float>,
            controlA: SIMD3<Float>,
            controlB: SIMD3<Float>,
            end: SIMD3<Float>,
            progress: Float
        ) -> SIMD3<Float> {
            let t = max(0, min(progress, 1))
            let inverse = 1 - t
            return inverse * inverse * inverse * start
                + 3 * inverse * inverse * t * controlA
                + 3 * inverse * t * t * controlB
                + t * t * t * end
        }

        nonisolated private static func cubicBezierTangent(
            start: SIMD3<Float>,
            controlA: SIMD3<Float>,
            controlB: SIMD3<Float>,
            end: SIMD3<Float>,
            progress: Float
        ) -> SIMD3<Float> {
            let t = max(0, min(progress, 1))
            let inverse = 1 - t
            return 3 * inverse * inverse * (controlA - start)
                + 6 * inverse * t * (controlB - controlA)
                + 3 * t * t * (end - controlB)
        }

        nonisolated private static func cutEngine(on rocket: SCNNode) {
            rocket.enumerateChildNodes { child, _ in
                if child.name == "engine-trail" {
                    child.particleSystems?.forEach { $0.birthRate = 0 }
                    child.removeAllActions()
                    child.removeFromParentNode()
                } else if child.name == "engine-flame" || child.name == "engine-glow" {
                    child.removeAllActions()
                    child.removeFromParentNode()
                }
            }
        }

        nonisolated private static func restoreEngine(on rocket: SCNNode, color: UIColor) {
            cutEngine(on: rocket)

            let flame = SCNNode()
            flame.name = "engine-flame"
            flame.position = SCNVector3(0, -1.13, 0)

            let outer = SCNCone(topRadius: 0.055, bottomRadius: 0.18, height: 0.42)
            outer.radialSegmentCount = 32
            outer.materials = [takeoffFlameMaterial(color.withAlphaComponent(0.72))]
            flame.addChildNode(SCNNode(geometry: outer))

            let core = SCNCone(topRadius: 0.028, bottomRadius: 0.09, height: 0.34)
            core.radialSegmentCount = 32
            core.materials = [takeoffFlameMaterial(UIColor.white.withAlphaComponent(0.78))]
            let coreNode = SCNNode(geometry: core)
            coreNode.position = SCNVector3(0, 0.03, 0)
            flame.addChildNode(coreNode)

            let pulse = CABasicAnimation(keyPath: "scale")
            pulse.fromValue = SCNVector3(0.82, 0.92, 0.82)
            pulse.toValue = SCNVector3(1.08, 1.04, 1.08)
            pulse.duration = 0.18
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            flame.addAnimation(pulse, forKey: "flame-pulse")
            rocket.addChildNode(flame)

            let emitter = SCNNode()
            emitter.name = "engine-trail"
            emitter.position = SCNVector3(0, -1.28, 0)
            emitter.addParticleSystem(takeoffTrailParticles(color: color))
            rocket.addChildNode(emitter)
        }

        nonisolated private static func startOrbit(on rocket: SCNNode, index: Int) {
            let duration = TimeInterval(7.4 + Double(index % 7) * 1.15)
            let orbitAction = SCNAction.customAction(duration: duration) { node, elapsed in
                let progress = Float(elapsed / CGFloat(duration))
                node.position = RocketSceneView.orbitPosition(for: index, progress: progress)
                node.simdOrientation = RocketSceneView.rocketOrientation(for: index, progress: progress)
            }
            rocket.runAction(.repeatForever(orbitAction), forKey: "smooth-orbit")
        }

        nonisolated private static func takeoffFlameMaterial(_ color: UIColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            material.transparency = 0.72
            material.blendMode = .add
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            return material
        }

        nonisolated private static func takeoffTrailParticles(color: UIColor) -> SCNParticleSystem {
            let particles = SCNParticleSystem()
            particles.birthRate = 260
            particles.loops = true
            particles.particleLifeSpan = 1.15
            particles.particleLifeSpanVariation = 0.35
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

        nonisolated private static func smoothstep(_ value: Float) -> Float {
            let clamped = max(0, min(value, 1))
            return clamped * clamped * (3 - 2 * clamped)
        }

        nonisolated private static func mix(
            currentPosition: SCNVector3,
            targetPosition: SCNVector3,
            progress: Float
        ) -> SCNVector3 {
            let t = progress
            return SCNVector3(
                currentPosition.x + (targetPosition.x - currentPosition.x) * t,
                currentPosition.y + (targetPosition.y - currentPosition.y) * t,
                currentPosition.z + (targetPosition.z - currentPosition.z) * t
            )
        }

        nonisolated private static func mix(
            current: SIMD3<Float>,
            target: SIMD3<Float>,
            progress: Float
        ) -> SIMD3<Float> {
            let t = max(0, min(progress, 1))
            return current + (target - current) * t
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
                followedRocket = randomRocket()
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
            let isLandingView = isAutolanding || areRocketsLanded.wrappedValue
            let followStage = (rocket.value(forKey: "followCameraStage") as? NSNumber)?.intValue ?? -1
            let isDescending = (rocket.value(forKey: "isLandingDescent") as? Bool) == true
            let desiredCameraPosition: SIMD3<Float>
            let desiredLookTarget: SIMD3<Float>
            let desiredUp: SIMD3<Float>

            if followStage == 0 || followStage == 2 || followStage == 3 || isDescending {
                let sideDistance = max(2.35, followDistance * 1.45)
                desiredCameraPosition = body + side * sideDistance + up * 0.42 - forward * 0.14
                desiredLookTarget = body + forward * 0.34
                desiredUp = forward
            } else if isLandingView {
                let sideDistance = max(2.35, followDistance * 1.45)
                desiredCameraPosition = body + side * sideDistance + SIMD3<Float>(0, 0.92, 0) - forward * 0.18
                desiredLookTarget = body + SIMD3<Float>(0, 0.18, 0)
                desiredUp = forward
            } else {
                desiredCameraPosition = tail - forward * followDistance + up * 0.48 + side * 0.18
                desiredLookTarget = body + forward * 1.65
                desiredUp = up
            }

            if followCameraPosition == nil {
                followCameraPosition = cameraNode.presentation.worldPosition.simdVector
            }
            if followCameraLookTarget == nil {
                followCameraLookTarget = desiredLookTarget
            }
            if followCameraUp == nil {
                followCameraUp = desiredUp
            }

            let blend: Float = animated ? 0.045 : 0.055
            let cameraPosition = Self.mix(
                current: followCameraPosition ?? desiredCameraPosition,
                target: desiredCameraPosition,
                progress: blend
            )
            let lookTarget = Self.mix(
                current: followCameraLookTarget ?? desiredLookTarget,
                target: desiredLookTarget,
                progress: blend
            )
            let cameraUp = simd_normalize(Self.mix(
                current: followCameraUp ?? desiredUp,
                target: desiredUp,
                progress: blend
            ))
            followCameraPosition = cameraPosition
            followCameraLookTarget = lookTarget
            followCameraUp = cameraUp

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            cameraNode.position = SCNVector3(cameraPosition.x, cameraPosition.y, cameraPosition.z)
            cameraNode.look(
                at: SCNVector3(lookTarget.x, lookTarget.y, lookTarget.z),
                up: SCNVector3(cameraUp.x, cameraUp.y, cameraUp.z),
                localFront: SCNVector3(0, 0, -1)
            )
            SCNTransaction.commit()
        }

        private func randomRocket() -> SCNNode? {
            guard let scene else {
                return nil
            }

            let rockets = scene.rootNode.childNodes { node, _ in
                node.name == "rocket-firing-source"
            }
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

        func shouldRebuildOrbitingRockets(rocketCount: Int, trailLength: Float, padRingSpacing: Float, padLateralSpacing: Float) -> Bool {
            builtRocketCount != rocketCount ||
                abs((builtTrailLength ?? -1) - trailLength) > 0.01 ||
                abs((builtPadRingSpacing ?? -1) - padRingSpacing) > 0.01 ||
                abs((builtPadLateralSpacing ?? -1) - padLateralSpacing) > 0.01
        }

        func markOrbitingRocketsBuilt(rocketCount: Int, trailLength: Float, padRingSpacing: Float, padLateralSpacing: Float) {
            builtRocketCount = rocketCount
            builtTrailLength = trailLength
            builtPadRingSpacing = padRingSpacing
            builtPadLateralSpacing = padLateralSpacing
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
            guard !isPaused, !isAutolanding, !areRocketsLanded.wrappedValue else {
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
            guard !isPaused, !isAutolanding, !areRocketsLanded.wrappedValue, let scene else {
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

private struct AutolandButton: View {
    let isLanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLanded ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLanded ? "Takeoff" : "Autoland")
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
    @Binding var padRingSpacing: Double
    @Binding var padLateralSpacing: Double
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

                    SettingsSlider(
                        title: "Ecart anneaux",
                        systemName: "circle.grid.2x2.fill",
                        valueText: String(format: "%.1fx pod", padRingSpacing),
                        value: $padRingSpacing,
                        bounds: 0...3.0
                    )

                    SettingsSlider(
                        title: "Ecart lateral",
                        systemName: "arrow.left.and.right",
                        valueText: String(format: "%.1fx pod", padLateralSpacing),
                        value: $padLateralSpacing,
                        bounds: 0...3.0
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
    init(_ vector: SIMD3<Float>) {
        self.init(vector.x, vector.y, vector.z)
    }

    var simdVector: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
