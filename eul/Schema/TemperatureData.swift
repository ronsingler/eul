//
//  TemperatureData.swift
//  eul
//
//  Created by Gao Sun on 2020/12/1.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary

class TemperatureData {
    let sensor: TemperatureSensor
    let info: DataType
    var temp: Double?

    init(sensor: TemperatureSensor, info: DataType = DataTypes.SP78, temp: Double? = nil) {
        self.sensor = sensor
        self.info = info
        self.temp = temp
    }
}
