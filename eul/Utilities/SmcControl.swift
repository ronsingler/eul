//
//  SmcControl.swift
//  eul
//
//  Created by Gao Sun on 2020/6/27.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary
import SwiftyJSON

class SmcControl: Refreshable {
    static var shared = SmcControl()

    var sensors: [TemperatureData] = []
    var fans: [FanData] = []
    /// Power used by the whole Mac in watts. Only on Macs whose SMC has PSTR.
    var systemPower: Double?
    private let systemPowerCode = FourCharCode(fromStaticString: "PSTR")
    private var hasSystemPower = false
    var tempUnit: TemperatureUnit = .celius
    var cpuDieTemperature: Double? {
        sensors.first(where: { $0.sensor.name == "CPU_0_DIE" })?.temp
            ?? averageTemperature(prefixes: ["Tp", "Te"])
    }

    var cpuProximityTemperature: Double? {
        sensors.first(where: { $0.sensor.name == "CPU_0_PROXIMITY" })?.temp
    }

    var gpuProximityTemperature: Double? {
        sensors.first(where: { $0.sensor.name == "GPU_0_PROXIMITY" })?.temp
            ?? averageTemperature(prefixes: ["Tg"])
    }

    var memoryProximityTemperature: Double? {
        sensors.first(where: { $0.sensor.name == "MEM_SLOTS_PROXIMITY" })?.temp
            ?? averageTemperature(prefixes: ["Tm"])
    }

    /// Average of the Apple silicon sensors whose names start with one of the prefixes
    private func averageTemperature(prefixes: [String]) -> Double? {
        let temps = sensors
            .filter { sensor in prefixes.contains { sensor.sensor.name.hasPrefix($0) } }
            .compactMap { $0.temp }
        guard temps.count > 0 else {
            return nil
        }
        return temps.reduce(0, +) / Double(temps.count)
    }

    var isFanValid: Bool {
        fans.count > 0
    }

    func formatTemp(_ value: Double) -> String {
        String(format: "%.0f°\(tempUnit == .celius ? "C" : "F")", value)
    }

    init() {
        do {
            try SMCKit.open()
            hasSystemPower = (try? SMCKit.keyInformation(systemPowerCode)) == DataTypes.FLT
            let knownSensors = try SMCKit.allKnownTemperatureSensors()
            let appleSiliconSensors = try SMCKit.appleSiliconTemperatureSensors()
            // Some Intel key names exist on Apple silicon with another data type,
            // so read each sensor with the type the SMC reports for it
            sensors = (knownSensors + appleSiliconSensors).compactMap { sensor in
                guard let info = try? SMCKit.keyInformation(sensor.code) else {
                    return nil
                }
                return TemperatureData(sensor: sensor, info: info)
            }
            fans = try (0..<SMCKit.fanCount()).map { FanData(
                id: $0,
                minSpeed: try? SMCKit.fanMinSpeed($0),
                maxSpeed: try? SMCKit.fanMaxSpeed($0)
            ) }
        } catch {
            print("SMC init error", error)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func subscribe() {
        initObserver(for: .SMCShouldRefresh)
    }

    func close() {
        SMCKit.close()
    }

    @objc func refresh() {
        for sensor in sensors {
            do {
                let celsius = try SMCKit.temperature(sensor.sensor.code, info: sensor.info)
                // Unused sensors read 0, and a few return junk
                guard celsius > 0, celsius < 150 else {
                    sensor.temp = nil
                    continue
                }
                switch tempUnit {
                case .celius:
                    sensor.temp = celsius
                case .fahrenheit:
                    sensor.temp = TemperatureUnit.toFahrenheit(celsius)
                case .kelvin:
                    sensor.temp = TemperatureUnit.toKelvin(celsius)
                }
            } catch {
                sensor.temp = nil
                print("error while getting temperature", error)
            }
        }
        if hasSystemPower, let power = try? SMCKit.power(systemPowerCode), power >= 0, power < 1000 {
            systemPower = power
        } else {
            systemPower = nil
        }
        fans = fans.map {
            FanData(
                id: $0.id,
                currentSpeed: try? SMCKit.fanCurrentSpeed($0.id),
                minSpeed: $0.minSpeed,
                maxSpeed: $0.maxSpeed
            )
        }
        NotificationCenter.default.post(name: .StoreShouldRefresh, object: nil)
    }
}

extension TemperatureUnit {
    var description: String {
        switch self {
        case .celius:
            return "temp.celsius".localized()
        case .fahrenheit:
            return "temp.fahrenheit".localized()
        case .kelvin:
            return "temp.kelvin".localized()
        }
    }
}

extension Fan: JSONCodabble {
    init?(json: JSON) {
        guard
            let id = json["id"].int,
            let name = json["name"].string,
            let minSpeed = json["id"].int,
            let maxSpeed = json["id"].int
        else {
            return nil
        }
        self.id = id
        self.name = name
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
    }

    var json: JSON {
        JSON([
            "id": id,
            "name": name,
            "minSpeed": minSpeed,
            "maxSpeed": maxSpeed,
        ])
    }
}

extension Double {
    var temperatureString: String {
        SmcControl.shared.formatTemp(self)
    }
}
