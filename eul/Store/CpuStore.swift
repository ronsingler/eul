//
//  CpuStore.swift
//  eul
//
//  Created by Gao Sun on 2020/6/27.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import IOKit
import SharedLibrary
import SystemKit
import WidgetKit

class CpuStore: ObservableObject, Refreshable {
    @Published var temp: Double?
    @Published var usageCPU: (system: Double, user: Double, idle: Double, nice: Double)?
    @Published var loadAverage: [Double]?
    @Published var physicalCores = 0
    @Published var logicalCores = 0
    @Published var upTime: (days: Int, hrs: Int, mins: Int, secs: Int)?
    @Published var thermalLevel: System.ThermalLevel = .Unknown
    @Published var usageHistory: [Double] = []
    @Published var performanceUsage: Double?
    @Published var efficiencyUsage: Double?

    /// Core kind ("P" or "E") of each logical CPU. Empty on Intel Macs.
    let coreTypes = CpuStore.getCoreTypes()
    private var previousCoreTicks: [[UInt32]] = []

    var performanceCores: Int {
        coreTypes.values.filter { $0 == "P" }.count
    }

    var efficiencyCores: Int {
        coreTypes.values.filter { $0 == "E" }.count
    }

    var loadAverage1MinString: String {
        formatDouble(loadAverage?[safe: 0])
    }

    var loadAverage5MinString: String {
        formatDouble(loadAverage?[safe: 1])
    }

    var loadAverage15MinString: String {
        formatDouble(loadAverage?[safe: 2])
    }

    var usageString: String {
        guard let usage = usageCPU else {
            return "N/A"
        }
        return String(format: "%.0f%%", usage.system + usage.user)
    }

    var usage: Double? {
        guard let usageCPU = usageCPU else {
            return nil
        }
        return usageCPU.system + usageCPU.user
    }

    private func formatDouble(_ value: Double?) -> String {
        guard let value = value else {
            return "N/A"
        }
        return String(format: "%.2f", value)
    }

    private func getInfo() {
        physicalCores = System.physicalCores()
        logicalCores = System.logicalCores()
        upTime = System.uptime()
        thermalLevel = System.thermalLevel()
    }

    private func getUsage() {
        let usage = Info.system.usageCPU()
        usageCPU = usage
        loadAverage = System.loadAverage()
        usageHistory = (usageHistory + [usage.system + usage.user]).suffix(LineChart.defaultMaxPointCount)
    }

    private func getCoreUsage() {
        let ticks = Self.getCoreTicks()
        defer {
            previousCoreTicks = ticks
        }
        guard !coreTypes.isEmpty, ticks.count == previousCoreTicks.count else {
            return
        }
        performanceUsage = usage(of: "P", ticks: ticks)
        efficiencyUsage = usage(of: "E", ticks: ticks)
    }

    /// Busy share of all cores of one kind since the last refresh, in percent
    private func usage(of type: String, ticks: [[UInt32]]) -> Double? {
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (cpu, kind) in coreTypes where kind == type && cpu < ticks.count {
            let delta = zip(ticks[cpu], previousCoreTicks[cpu]).map { UInt64($0 &- $1) }
            let sum = delta.reduce(0, +)
            total += sum
            busy += sum - delta[Int(CPU_STATE_IDLE)]
        }
        guard total > 0 else {
            return nil
        }
        return Double(busy) / Double(total) * 100
    }

    /// Ticks per logical CPU, in the order user, system, idle, nice
    private static func getCoreTicks() -> [[UInt32]] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard
            host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
            let info = info
        else {
            return []
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { cpu in
            (0..<states).map { UInt32(bitPattern: info[states * cpu + $0]) }
        }
    }

    /// On Apple silicon each CPU in the device tree has a cluster type of "P" or "E"
    private static func getCoreTypes() -> [Int: String] {
        let cpus = IORegistryEntryFromPath(kIOMasterPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else {
            return [:]
        }
        defer {
            IOObjectRelease(cpus)
        }

        var iterator = io_iterator_t()
        guard IORegistryEntryGetChildIterator(cpus, "IODeviceTree", &iterator) == kIOReturnSuccess else {
            return [:]
        }
        defer {
            IOObjectRelease(iterator)
        }

        var types = [Int: String]()
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if
                let properties = IOHelper.getProperties(entry: entry),
                let cpu = properties["logical-cpu-id"] as? Int,
                let data = properties["cluster-type"] as? Data,
                let type = String(data: data, encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            {
                types[cpu] = type
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return types
    }

    private func getTemp() {
        temp = (SmcControl.shared.cpuDieTemperature ?? 0) > 0
            ? SmcControl.shared.cpuDieTemperature
            : SmcControl.shared.cpuProximityTemperature
    }

    @objc func refresh() {
        getInfo()
        getUsage()
        getCoreUsage()
        getTemp()
        writeToContainer()
    }

    func writeToContainer() {
        Container.set(CpuEntry(
            temp: temp,
            usageSystem: usageCPU?.system,
            usageUser: usageCPU?.user,
            usageNice: usageCPU?.nice
        ))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: CpuEntry.kind)
        }
    }

    init() {
        initObserver(for: .StoreShouldRefresh)
    }
}
