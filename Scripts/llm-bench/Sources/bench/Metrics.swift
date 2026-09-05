import Darwin
import Foundation

/// Process and machine measurements for one benchmark run.
///
/// Resident memory comes from the task's own accounting, so for Apple
/// Intelligence, which runs in a system process, it stays near zero and only
/// the machine-wide CPU number says anything. Machine CPU is the busy share
/// of all cores over the run, from host_processor_info deltas.
struct Metrics {
    static func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Resident pages including memory-mapped model weights, which phys_footprint leaves out.
    static func residentSizeBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    static func processCPUSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
    }

    /// (busy ticks, total ticks) summed over every core.
    static func machineTicks() -> (busy: UInt64, total: UInt64) {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return (0, 0) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)]), sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)]), idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        return (busy, total)
    }

    /// Samples resident memory every 100 ms while a run is in flight.
    final class Sampler: @unchecked Sendable {
        private(set) var peakResident: UInt64 = 0
        private var running = true
        private let thread: Thread
        init() {
            var box: Sampler?
            thread = Thread { while box?.running == true { box?.peakResident = max(box?.peakResident ?? 0, Metrics.residentSizeBytes()); Thread.sleep(forTimeInterval: 0.1) } }
            box = self
            thread.start()
        }
        func stop() -> UInt64 { running = false; return max(peakResident, Metrics.residentSizeBytes()) }
    }
}

struct CaseResult: Encodable {
    var input: String, expected: String?, got: String, pass: Bool?
    var wallSeconds: Double, promptTokens: Int, outputTokens: Int, promptTokensPerSecond: Double, generationTokensPerSecond: Double
}

struct Summary: Encodable {
    var engine: String
    var fileGB: Double?
    var loadSeconds: Double
    /// Resident set including mapped weights.
    var residentAfterLoadGB: Double
    var peakResidentGB: Double
    /// Dirty and compressed memory the process owns, excluding mapped weights.
    var footprintGB: Double
    var processCPUSeconds: Double
    var machineCPUBusyPercent: Double
    var passed: String
    var meanWallSeconds: Double
    var meanGenerationTokensPerSecond: Double
    var longMeanWallSeconds: Double
}

struct Report: Encodable { var summary: Summary; var cases: [CaseResult]; var long: [CaseResult] }
