import Darwin
import Foundation
import IOKit.ps
import Observation
import DeskBotCore

/// CPU (host_statistics), RAM (host_statistics64), Battery (IOKit power sources).
/// Control center нээлттэй үед 2с, хаалттай үед 30с (C# SystemMonitorService) — шаардлагагүй polling хийхгүй.
/// Уншиж чадаагүй утга nil → UI "unavailable" (хуурамч тоо харуулахгүй).
@MainActor
@Observable
final class SystemMonitor {
    static let slowInterval: TimeInterval = 30
    static let fastInterval: TimeInterval = 2

    private(set) var cpuPercent: Double?
    private(set) var memory: MemoryUsage?
    private(set) var battery: BatteryState = .none

    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let host = mach_host_self()

    func start() {
        sample()
        schedule(Self.slowInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setFast(_ fast: Bool) {
        schedule(fast ? Self.fastInterval : Self.slowInterval)
        if fast { sample() }
    }

    private func schedule(_ interval: TimeInterval) {
        if let t = timer, t.timeInterval == interval { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func sample() {
        if let ticks = readCPUTicks() {
            if let last = lastTicks, let u = CPUTicks.usage(from: last, to: ticks) { cpuPercent = u }
            lastTicks = ticks
        }
        memory = readMemory()
        battery = Self.readBattery()
        onUpdate?()
    }

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks // (user, system, idle, nice)
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    private func readMemory() -> MemoryUsage? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return MemoryUsage(internalPages: UInt64(vm.internal_page_count), purgeablePages: UInt64(vm.purgeable_count),
                           wiredPages: UInt64(vm.wire_count), compressedPages: UInt64(vm.compressor_page_count),
                           pageSize: UInt64(getpagesize()), totalBytes: ProcessInfo.processInfo.physicalMemory)
    }

    static func readBattery() -> BatteryState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return .none }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let percent = (d[kIOPSCurrentCapacityKey] as? Int).flatMap { cur in
                (d[kIOPSMaxCapacityKey] as? Int).flatMap { BatteryState.percent(current: cur, max: $0) }
            }
            return BatteryState(present: (d[kIOPSIsPresentKey] as? Bool) ?? true,
                                percent: percent,
                                onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                                charging: (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return .none
    }
}
