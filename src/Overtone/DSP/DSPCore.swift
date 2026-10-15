import CoreAudio
import Foundation
import OvertoneDSP

/// Swift owner of the C processing core. Lives for the whole app session so
/// effect state and the plugin chain survive pipeline rebuilds.
final class DSPCore: @unchecked Sendable {
    let handle: OpaquePointer

    init() {
        guard let handle = ot_dsp_create() else { fatalError("Unable to allocate DSP core") }
        self.handle = handle
    }

    deinit { ot_dsp_destroy(handle) }

    var clientData: UnsafeMutableRawPointer { UnsafeMutableRawPointer(handle) }
    var ioProc: AudioDeviceIOProc { ot_io_proc_ptr()! }
    var cycleCount: UInt64 { ot_dsp_cycle_count(handle) }

    /// Resets effect state for a new sample rate. Only call while no IO is running.
    func prepare(sampleRate: Double) {
        ot_dsp_prepare(handle, Float(sampleRate))
    }

    func publish(_ params: ot_params) {
        var copy = params
        ot_dsp_publish(handle, &copy)
    }

    func readAnalyzer(into buffer: inout [Float]) -> Int {
        let count = UInt32(buffer.count)
        return buffer.withUnsafeMutableBufferPointer {
            Int(ot_dsp_read_analyzer(handle, $0.baseAddress, count))
        }
    }

    func readPeaks() -> (left: Float, right: Float) {
        var left: Float = 0, right: Float = 0
        ot_dsp_read_peaks(handle, &left, &right)
        return (left, right)
    }
}
