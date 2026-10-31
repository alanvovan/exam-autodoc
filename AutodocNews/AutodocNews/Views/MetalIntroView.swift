import MetalKit
import UIKit

/// Заставка поверх окна при холодном старте сцены.
/// При Reduce Motion не показывается. Повторный выход из фона её не запускает:
/// показ живёт только в `scene(_:willConnectTo:options:)`.
final class MetalIntroView: MTKView, MTKViewDelegate {
    static let playDuration: TimeInterval = 2.2
    private static let fadeDuration: TimeInterval = 0.4

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let logoTexture: MTLTexture
    private var startTime: CFTimeInterval = 0
    private var isDismissing = false
    private var fallbackTask: Task<Void, Never>?
    private var motionObserver: NSObjectProtocol?

    static func presentIfNeeded(on window: UIWindow) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        guard let resources = makeResources() else { return }

        var frame = window.bounds
        if frame.width < 1 || frame.height < 1 {
            frame = window.windowScene?.screen.bounds ?? frame
        }

        let intro = MetalIntroView(
            frame: frame,
            device: resources.device,
            commandQueue: resources.commandQueue,
            pipeline: resources.pipeline,
            logoTexture: resources.logoTexture
        )
        intro.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        intro.contentScaleFactor = window.screen.scale
        window.addSubview(intro)
        window.bringSubviewToFront(intro)
        intro.begin()
    }

    private static func makeResources() -> (device: MTLDevice, commandQueue: MTLCommandQueue, pipeline: MTLRenderPipelineState, logoTexture: MTLTexture)? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let logoTexture = loadLogoTexture(device: device),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "liquidMetalVertex"),
              let fragment = library.makeFunction(name: "liquidMetalFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return (device, commandQueue, pipeline, logoTexture)
    }

    /// Поле расстояний логотипа: 512×512 uint16 little-endian,
    /// строки в порядке файла. Декодирование в [-1, 1] делает шейдер.
    private static func loadLogoTexture(device: MTLDevice) -> MTLTexture? {
        let size = 512
        let bytesPerRow = size * MemoryLayout<UInt16>.size
        guard let url = Bundle.main.url(forResource: "FluidChromeShapeSDF", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              data.count == bytesPerRow * size
        else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }

    private init(
        frame: CGRect,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState,
        logoTexture: MTLTexture
    ) {
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.logoTexture = logoTexture
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        clearColor = MTLClearColor(red: 14.0 / 255.0, green: 18.0 / 255.0, blue: 22.0 / 255.0, alpha: 1)
        isOpaque = true
        backgroundColor = GarageTheme.metal
        isUserInteractionEnabled = true
        accessibilityLabel = "Autodoc"
        accessibilityViewIsModal = true
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Заставка создаётся в коде")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 1, view.drawableSize.height > 1 else { return }
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        if startTime == 0 {
            startTime = CACurrentMediaTime()
        }

        let elapsed = Float(CACurrentMediaTime() - startTime)
        let progress = min(elapsed / Float(Self.playDuration), 1)
        var uniforms = IntroUniforms(
            elapsed: elapsed,
            progress: progress,
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<IntroUniforms>.stride, index: 0)
        encoder.setFragmentTexture(logoTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        guard progress >= 1, !isDismissing else { return }
        isPaused = true
        Task { @MainActor in
            self.finishAndFade()
        }
    }

    private func begin() {
        startTime = CACurrentMediaTime()
        isPaused = false
        motionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard UIAccessibility.isReduceMotionEnabled else { return }
                self?.detach()
            }
        }

        let budget = Self.playDuration + Self.fadeDuration + 1
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(budget))
            guard !Task.isCancelled else { return }
            self?.finishAndFade()
        }
    }

    private func finishAndFade() {
        guard !isDismissing else { return }
        isDismissing = true
        fallbackTask?.cancel()
        fallbackTask = nil
        isPaused = true
        UIView.animate(
            withDuration: Self.fadeDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.alpha = 0
        } completion: { [weak self] _ in
            self?.detach()
        }
    }

    private func detach() {
        isDismissing = true
        fallbackTask?.cancel()
        fallbackTask = nil
        isPaused = true
        delegate = nil
        if let motionObserver {
            NotificationCenter.default.removeObserver(motionObserver)
            self.motionObserver = nil
        }
        releaseDrawables()
        removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        if scale > 0, contentScaleFactor != scale {
            contentScaleFactor = scale
        }
        superview?.bringSubviewToFront(self)
    }
}

private struct IntroUniforms {
    var elapsed: Float
    var progress: Float
    var resolution: SIMD2<Float>
}
