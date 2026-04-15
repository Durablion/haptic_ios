import Foundation

/// One entry in the curated pattern list. Effect IDs come from
/// DRV2605 ROM library 1 (TS2200 Library A).
struct HapticPattern: Identifiable, Hashable {
    let id: UInt8       // effect number 1..123
    let name: String
    let detail: String  // short hint shown under the name

    static let all: [HapticPattern] = [
        HapticPattern(id: 1,   name: "Strong Click",          detail: "100%"),
        HapticPattern(id: 2,   name: "Strong Click",          detail: "60%"),
        HapticPattern(id: 3,   name: "Strong Click",          detail: "30%"),
        HapticPattern(id: 4,   name: "Sharp Click",           detail: "100%"),
        HapticPattern(id: 5,   name: "Sharp Click",           detail: "60%"),
        HapticPattern(id: 7,   name: "Soft Bump",             detail: "100%"),
        HapticPattern(id: 8,   name: "Soft Bump",             detail: "60%"),
        HapticPattern(id: 10,  name: "Double Click",          detail: "100%"),
        HapticPattern(id: 12,  name: "Triple Click",          detail: "100%"),
        HapticPattern(id: 13,  name: "Soft Fuzz",             detail: "60%"),
        HapticPattern(id: 14,  name: "Strong Buzz",           detail: "100%"),
        HapticPattern(id: 15,  name: "Alert",                 detail: "750 ms"),
        HapticPattern(id: 16,  name: "Alert",                 detail: "1000 ms"),
        HapticPattern(id: 47,  name: "Buzz 1",                detail: "100%"),
        HapticPattern(id: 58,  name: "Transition Ramp Up",    detail: "Long"),
        HapticPattern(id: 67,  name: "Transition Ramp Down",  detail: "Long"),
        HapticPattern(id: 82,  name: "Pulsing Strong",        detail: "Slow"),
        HapticPattern(id: 84,  name: "Pulsing Sharp",         detail: "Slow"),
        HapticPattern(id: 96,  name: "Long Double Sharp",     detail: "Medium"),
        HapticPattern(id: 118, name: "Transition Hum",        detail: "Long"),
    ]
}
