import Foundation

/// A computer inventory scoped to the device that owns it. Computer ids are owner-local, so names and ids alone cannot
/// identify a placement.
struct ComputerOwnerInventory: Equatable, Identifiable {
    var deviceId: String?
    var name: String
    var inventory: ComputerInventory

    var id: String { deviceId.map { "owner/\($0)" } ?? "local" }

    var options: [ComputerPlacementOption] {
        inventory.allComputers.map {
            ComputerPlacementOption(deviceId: deviceId, ownerName: name, computer: $0)
        }
    }

    static func local(_ inventory: ComputerInventory) -> ComputerOwnerInventory {
        ComputerOwnerInventory(deviceId: nil, name: "This Mac", inventory: inventory)
    }

    static func remote(_ device: SiloWireDevice, inventory: ComputerInventory) -> ComputerOwnerInventory {
        ComputerOwnerInventory(deviceId: device.id, name: device.name, inventory: inventory)
    }
}

struct ComputerPlacementOption: Equatable, Identifiable {
    var deviceId: String?
    var ownerName: String
    var computer: ComputerRow

    var id: String { "\(deviceId ?? "local")/\(computer.id)" }
    var location: SessionLocation { .computer(deviceId: deviceId, computerId: computer.id) }
}

/// A connected device whose computers could not be read.
struct ComputerOwnerFailure: Equatable, Identifiable {
    var device: SiloWireDevice
    var message: String
    var id: String { "owner/\(device.id)" }
}
