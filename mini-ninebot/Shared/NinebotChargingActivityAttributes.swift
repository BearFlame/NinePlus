import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct NinebotChargingActivityAttributes: ActivityAttributes {
    var vehicleSN: String
    var vehicleName: String
    var vehicleModel: String

    struct ContentState: Codable, Hashable {
        var battery: Int
        var estimatedRange: Double?
        var estimatedFullAt: Date?
        var chargingPower: Double?
        var batteryTemperature: Double?
        var batteryVoltage: Double?
        var chargingSpeed: Double?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case battery
            case estimatedRange
            case estimatedFullAt
            case chargingPower
            case batteryTemperature
            case batteryVoltage
            case chargingSpeed
            case updatedAt
        }

        init(
            battery: Int,
            estimatedRange: Double?,
            estimatedFullAt: Date?,
            chargingPower: Double?,
            batteryTemperature: Double?,
            batteryVoltage: Double?,
            chargingSpeed: Double?,
            updatedAt: Date
        ) {
            self.battery = battery
            self.estimatedRange = estimatedRange
            self.estimatedFullAt = estimatedFullAt
            self.chargingPower = chargingPower
            self.batteryTemperature = batteryTemperature
            self.batteryVoltage = batteryVoltage
            self.chargingSpeed = chargingSpeed
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            battery = try container.decode(Int.self, forKey: .battery)
            estimatedRange = try container.decodeIfPresent(Double.self, forKey: .estimatedRange)
            estimatedFullAt = Self.decodeDateIfPresent(from: container, forKey: .estimatedFullAt)
            chargingPower = try container.decodeIfPresent(Double.self, forKey: .chargingPower)
            batteryTemperature = try container.decodeIfPresent(Double.self, forKey: .batteryTemperature)
            batteryVoltage = try container.decodeIfPresent(Double.self, forKey: .batteryVoltage)
            chargingSpeed = try container.decodeIfPresent(Double.self, forKey: .chargingSpeed)
            updatedAt = Self.decodeDateIfPresent(from: container, forKey: .updatedAt) ?? Date()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(battery, forKey: .battery)
            try container.encodeIfPresent(estimatedRange, forKey: .estimatedRange)
            try container.encodeIfPresent(estimatedFullAt?.timeIntervalSince1970, forKey: .estimatedFullAt)
            try container.encodeIfPresent(chargingPower, forKey: .chargingPower)
            try container.encodeIfPresent(batteryTemperature, forKey: .batteryTemperature)
            try container.encodeIfPresent(batteryVoltage, forKey: .batteryVoltage)
            try container.encodeIfPresent(chargingSpeed, forKey: .chargingSpeed)
            try container.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
        }

        private static func decodeDateIfPresent(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> Date? {
            if let timestamp = try? container.decodeIfPresent(Double.self, forKey: key) {
                if timestamp > 1_000_000_000 {
                    return Date(timeIntervalSince1970: timestamp)
                }
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            if let text = try? container.decodeIfPresent(String.self, forKey: key) {
                if let timestamp = Double(text) {
                    return Date(timeIntervalSince1970: timestamp)
                }
                return ISO8601DateFormatter().date(from: text)
            }
            return nil
        }
    }
}
#endif
