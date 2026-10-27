//
//  MemoryStore.swift
//  eul
//
//  Created by Gao Sun on 2020/6/29.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary
import SystemKit
import WidgetKit

class MemoryStore: ObservableObject, Refreshable {
    /// The kernel's memory pressure level, as Activity Monitor shows it
    enum PressureLevel: String {
        case normal
        case warning
        case critical

        var description: String {
            "memory.pressure.\(rawValue)".localized()
        }
    }

    @Published var free: Double = 0
    @Published var active: Double = 0
    @Published var inactive: Double = 0
    @Published var wired: Double = 0
    @Published var compressed: Double = 0
    @Published var appMemory: Double = 0
    @Published var cachedFiles: Double = 0
    @Published var temp: Double?
    @Published var usageHistory: [Double] = []
    @Published var pressure: Double?
    @Published var pressureLevel: PressureLevel?

    var used: Double {
        appMemory + wired + compressed
    }

    var usedPercentage: Double {
        used / total * 100
    }

    var usedPercentageString: String {
        (used / total).percentageString
    }

    var total: Double {
        free + inactive + active + wired + compressed
    }

    var allFree: Double {
        total - used
    }

    var allFreePercentage: Double {
        allFree / total * 100
    }

    var freeString: String {
        (total - used).memoryString
    }

    var usedString: String {
        used.memoryString
    }

    @objc func refresh() {
        (free, active, inactive, wired, compressed, appMemory, cachedFiles) = System.memoryUsage()
        temp = SmcControl.shared.memoryProximityTemperature
        getPressure()
        usageHistory = (usageHistory + [usedPercentage]).suffix(LineChart.defaultMaxPointCount)
        writeToContainer()
    }

    private func getPressure() {
        // Share of memory the kernel considers available, 0-100
        if let available = Self.sysctlInt32("kern.memorystatus_level") {
            pressure = Double(100 - available)
        } else {
            pressure = nil
        }
        switch Self.sysctlInt32("kern.memorystatus_vm_pressure_level") {
        case 1:
            pressureLevel = .normal
        case 2:
            pressureLevel = .warning
        case 4:
            pressureLevel = .critical
        default:
            pressureLevel = nil
        }
    }

    private static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }
        return value
    }

    func writeToContainer() {
        Container.set(MemoryEntry(used: used, total: total, temp: temp))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: MemoryEntry.kind)
        }
    }

    init() {
        initObserver(for: .StoreShouldRefresh)
    }
}
