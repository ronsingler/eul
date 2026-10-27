//
//  BatteryStore.swift
//  eul
//
//  Created by Gao Sun on 2020/8/7.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import IOKit
import SharedLibrary
import SystemKit
import WidgetKit

class BatteryStore: ObservableObject, Refreshable {
    private var battery = Battery()

    var io = Info.Battery()

    @Published var isValid = true

    @Published var acPowered = false
    @Published var charged = false
    @Published var charging = false
    @Published var capacity = 0
    @Published var maxCapacity = 0
    @Published var designCapacity = 0
    @Published var cycleCount = 0
    @Published var timeRemaining = "∞"

    var charge: Double {
        io.currentCharge
    }

    var health: Double {
        Double(maxCapacity) / Double(designCapacity)
    }

    @objc func refresh() {
        io = Info.Battery()

        guard battery.open() == kIOReturnSuccess else {
            isValid = false
            return
        }

        isValid = true

        acPowered = battery.isACPowered()
        charged = battery.isCharged()
        charging = battery.isCharging()
        capacity = battery.currentCapacity()
        maxCapacity = battery.maxCapactiy()
        designCapacity = battery.designCapacity()
        // Newer macOS on Apple silicon reports percentages at the top level and
        // keeps the mAh values only inside "BatteryData"
        if let batteryData = Self.getBatteryData() {
            capacity = batteryData["AppleRawCurrentCapacity"] as? Int ?? capacity
            maxCapacity = batteryData["AppleRawMaxCapacity"] as? Int ?? maxCapacity
            designCapacity = batteryData["DesignCapacity"] as? Int ?? designCapacity
        }
        cycleCount = battery.cycleCount()
        timeRemaining = io.powerSource == .battery ? battery.timeRemainingFormatted() : "∞"
        _ = battery.close()
        writeToContainer()
    }

    private static func getBatteryData() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }
        return IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    func writeToContainer() {
        Container.set(BatteryEntry(
            isCharging: charging, acPowered: acPowered, charge: charge, capacity: capacity, maxCapacity: maxCapacity, designCapacity: designCapacity, cycleCount: cycleCount, condition: io.condition
        ))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: BatteryEntry.kind)
        }
    }

    init() {
        initObserver(for: .StoreShouldRefresh)
        refresh()
    }
}
