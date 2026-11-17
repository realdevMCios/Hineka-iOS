import MetalKit
import SwiftUI

private final class HinekaMetalTriangleRenderer: NSObject, ObservableObject, MTKViewDelegate {
    @Published private(set) var status = "Đang khởi tạo Metal…"
    @Published private(set) var frameCount = 0

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private weak var attachedView: MTKView?

    var isReady: Bool {
        device != nil && commandQueue != nil && pipelineState != nil
    }

    override init() {
        super.init()
        configureMetal()
    }

    private func configureMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            status = "Thiết bị không cung cấp Metal device mặc định."
            return
        }
        guard let commandQueue = device.makeCommandQueue() else {
            status = "Không tạo được Metal command queue."
            return
        }

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct HinekaVertexOutput {
            float4 position [[position]];
            float4 color;
        };

        vertex HinekaVertexOutput hinekaVertex(uint vertexID [[vertex_id]]) {
            constexpr float2 positions[3] = {
                float2(0.0, 0.72),
                float2(-0.72, -0.62),
                float2(0.72, -0.62)
            };
            constexpr float4 colors[3] = {
                float4(0.30, 0.78, 1.00, 1.00),
                float4(0.55, 0.38, 0.96, 1.00),
                float4(0.30, 0.88, 0.66, 1.00)
            };

            HinekaVertexOutput output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.color = colors[vertexID];
            return output;
        }

        fragment float4 hinekaFragment(HinekaVertexOutput input [[stage_in]]) {
            return input.color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard
                let vertexFunction = library.makeFunction(name: "hinekaVertex"),
                let fragmentFunction = library.makeFunction(name: "hinekaFragment")
            else {
                status = "Không tìm thấy Metal vertex/fragment shader."
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Hineka Metal Surface Probe"
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            self.device = device
            self.commandQueue = commandQueue
            self.pipelineState = pipeline
            status = "Metal sẵn sàng: \(device.name)"
        } catch {
            status = "Không tạo được Metal pipeline: \(error.localizedDescription)"
        }
    }

    func attach(to view: MTKView) {
        attachedView = view
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0.055, green: 0.065, blue: 0.11, alpha: 1.0)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 30

        if isReady {
            status = "Metal sẵn sàng — chờ render frame đầu tiên."
            view.setNeedsDisplay()
        }
    }

    func renderOneFrame() {
        guard isReady else { return }
        attachedView?.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard
            let commandQueue,
            let pipelineState,
            let renderPass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        else {
            DispatchQueue.main.async { [weak self] in
                self?.status = "Metal không tạo được drawable hoặc command encoder."
            }
            return
        }

        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = view.clearColor

        encoder.setRenderPipelineState(pipelineState)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            DispatchQueue.main.async {
                guard let self else { return }
                if buffer.status == .completed {
                    self.frameCount += 1
                    self.status = "Metal render PASS — \(self.frameCount) frame(s) đã present."
                } else {
                    self.status = "Metal command buffer lỗi: \(buffer.error?.localizedDescription ?? "không rõ nguyên nhân")"
                }
            }
        }
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isReady else { return }
            self.status = "Metal surface đổi kích thước: \(Int(size.width)) × \(Int(size.height))"
        }
    }
}

private struct HinekaMetalTriangleSurface: UIViewRepresentable {
    @ObservedObject var renderer: HinekaMetalTriangleRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: nil)
        renderer.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        if renderer.isReady && view.delegate == nil {
            renderer.attach(to: view)
        }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: ()) {
        view.delegate = nil
    }
}

public struct HinekaMetalSurfaceProbeScreen: View {
    @StateObject private var renderer = HinekaMetalTriangleRenderer()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Metal Surface Probe")
                    .font(.title2.bold())

                Text("Bài thử native iOS: render một tam giác bằng Metal qua MTKView. Đây chưa phải renderer Minecraft, LWJGL hay OpenGL translation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HinekaMetalTriangleSurface(renderer: renderer)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.quaternary, lineWidth: 1)
                    }

                Text(renderer.status)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Text("Frames presented: \(renderer.frameCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Button {
                    renderer.renderOneFrame()
                } label: {
                    Label("Render lại một frame", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!renderer.isReady)

                Text("Kết quả CI chỉ xác nhận mã biên dịch. Cần chạy trên iPhone/iPad thật để xác nhận Metal device, drawable và frame presentation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Kiểm tra Metal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HinekaMetalSurfaceProbeScreen()
    }
}
