import CoreAudio
import OvertoneDSP
import Testing

/// Interleaved Float32 buffers wrapped in an AudioBufferList, as the HAL hands them to an IO proc.
private final class BufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(channels: [Int], frames: Int, fill: (_ buffer: Int, _ channel: Int) -> Float = { _, _ in 0 }) {
        list = AudioBufferList.allocate(maximumBuffers: max(channels.count, 1))
        list.count = channels.count
        for (index, count) in channels.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames * count)
            for frame in 0..<frames {
                for channel in 0..<count {
                    data[frame * count + channel] = fill(index, channel)
                }
            }
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(count), mDataByteSize: UInt32(frames * count * 4), mData: data
            )
        }
    }

    func sample(buffer: Int, frame: Int, channel: Int) -> Float {
        storage[buffer][frame * Int(list[buffer].mNumberChannels) + channel]
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

private func runIO(_ configure: (inout ot_params) -> Void, input: BufferList, output: BufferList) {
    let dsp = ot_dsp_create()!
    defer { ot_dsp_destroy(dsp) }
    var params = ot_params()
    ot_params_init(&params, 48_000)
    configure(&params)
    ot_dsp_publish(dsp, &params)
    var time = AudioTimeStamp()
    let proc = ot_io_proc_ptr()!
    _ = proc(
        0,
        &time,
        input.list.unsafePointer,
        &time,
        output.list.unsafeMutablePointer,
        &time,
        UnsafeMutableRawPointer(dsp)
    )
}

@Suite("IO proc")
struct IOProcTests {
    @Test func mixesTrailingTapBuffersWithGains() {
        // Buffer 0 is a device input (microphone) that must be ignored; buffers 1 and 2 are taps.
        let input = BufferList(channels: [1, 2, 2], frames: 256) { buffer, channel in
            switch buffer {
            case 0: return 0.9
            case 1: return channel == 0 ? 0.2 : 0.1
            default: return 0.4
            }
        }
        let output = BufferList(channels: [2], frames: 256)
        runIO({ p in
            p.tap_count = 2
            ot_params_set_tap_gain(&p, 1, 0.5)
        }, input: input, output: output)
        #expect(abs(output.sample(buffer: 0, frame: 200, channel: 0) - 0.4) < 1e-5)
        #expect(abs(output.sample(buffer: 0, frame: 200, channel: 1) - 0.3) < 1e-5)
    }

    @Test func routesToPreferredStereoChannelsAndSilencesOthers() {
        let input = BufferList(channels: [2], frames: 128) { _, channel in channel == 0 ? 0.25 : -0.25 }
        let output = BufferList(channels: [2, 2], frames: 128) { _, _ in 0.7 }
        runIO({ p in
            p.out_left = 2
            p.out_right = 3
        }, input: input, output: output)
        #expect(output.sample(buffer: 0, frame: 64, channel: 0) == 0)
        #expect(output.sample(buffer: 0, frame: 64, channel: 1) == 0)
        #expect(abs(output.sample(buffer: 1, frame: 64, channel: 0) - 0.25) < 1e-6)
        #expect(abs(output.sample(buffer: 1, frame: 64, channel: 1) + 0.25) < 1e-6)
    }

    @Test func foldsDownToMonoDevices() {
        let input = BufferList(channels: [2], frames: 64) { _, channel in channel == 0 ? 0.6 : 0.2 }
        let output = BufferList(channels: [1], frames: 64)
        runIO({ p in
            p.out_left = 0
            p.out_right = 0
        }, input: input, output: output)
        #expect(abs(output.sample(buffer: 0, frame: 10, channel: 0) - 0.4) < 1e-6)
    }

    @Test func processesBuffersLargerThanOneChunk() {
        let frames = Int(OT_MAX_CHUNK) * 2 + 300
        let input = BufferList(channels: [2], frames: frames) { _, _ in 0.5 }
        let output = BufferList(channels: [2], frames: frames)
        runIO({ $0.volume = 0.5 }, input: input, output: output)
        for frame in [0, Int(OT_MAX_CHUNK) - 1, Int(OT_MAX_CHUNK), frames - 1] {
            #expect(abs(output.sample(buffer: 0, frame: frame, channel: 1) - 0.25) < 1e-5, "frame \(frame)")
        }
    }

    @Test func missingInputProducesSilenceNotGarbage() {
        let input = BufferList(channels: [], frames: 0)
        let output = BufferList(channels: [2], frames: 64) { _, _ in 0.9 }
        runIO({ _ in }, input: input, output: output)
        #expect(output.sample(buffer: 0, frame: 32, channel: 0) == 0)
    }
}
