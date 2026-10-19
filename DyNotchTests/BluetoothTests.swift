import CoreGraphics
import Foundation
import Testing

@testable import DyNotch

struct BluetoothTests {
    @Test func parsesAirPodsBatteryFromSystemProfiler() throws {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelLeft":"90 %","device_batteryLevelRight":"85 %","device_batteryLevelCase":"40 %"}},
          {"Magic Mouse":{"device_address":"11:22:33:44:55:66","device_batteryLevelMain":"70 %"}}
        ]}]}
        """
        let battery = try #require(BluetoothMonitor.parseSystemProfiler(Data(json.utf8), address: "AABBCCDDEEFF"))
        #expect(battery.left == 90)
        #expect(battery.right == 85)
        #expect(battery.caseLevel == 40)
        #expect(battery.summary == 85)
        #expect(BluetoothMonitor.parseSystemProfiler(Data(json.utf8), address: BluetoothMonitor.normalize("11-22-33-44-55-66"))?.main == 70)
    }

    @Test func picksSymbolsByName() {
        #expect(BluetoothMonitor.symbol(name: "Jane's AirPods Pro", major: 0x04, minor: 0) == "airpods.pro")
        #expect(BluetoothMonitor.symbol(name: "Headset", major: 0x04, minor: 0) == "headphones")
        #expect(BluetoothMonitor.symbol(name: "Magic Keyboard", major: 0x05, minor: 0x10) == "keyboard.fill")
    }

    @Test func knowsAirPodsByProductIDAndName() {
        #expect(AirPodsModel(productID: 0x2024) == .airPodsPro)
        #expect(AirPodsModel(productID: 0x201F) == .airPodsMax)
        #expect(AirPodsModel(productID: 0x200A) == .airPodsMax)
        #expect(AirPodsModel(productID: 0x2019) == .airPods4)
        #expect(AirPodsModel(productID: 0x2009) == nil)
        #expect(AirPodsModel(name: "AirPods Max de Carlos") == .airPodsMax)
        #expect(AirPodsModel(name: "Jane’s AirPods Pro") == .airPodsPro)
        #expect(AirPodsModel(name: "AirPods 4") == .airPods4)
        #expect(AirPodsModel(name: "Carlos’s AirPods") == .airPods)
        #expect(AirPodsModel(name: "Magic Mouse") == nil)
        #expect(AirPodsModel.airPodsMax.earbuds == nil)
        #expect(AirPodsModel.airPodsPro.earbuds?.chargingCase == "airpods.pro.chargingcase.wireless.fill")
    }

    @Test func airPodsDropDownOnlyWhenTheyConnect() {
        let notch = CGSize(width: 185, height: 32)
        func layout(_ airPods: AirPodsModel?, connected: Bool, animates: Bool = true) -> ActivityLayout {
            LiveActivityKind.bluetooth(BluetoothEvent(
                address: "A", name: "Device", symbol: "airpods", isConnected: connected, airPods: airPods, animatesAirPods: animates
            )).layout(notch: notch)
        }
        #expect(layout(.airPodsMax, connected: true) == .expanded(width: 421, extraHeight: 74))
        #expect(layout(.airPodsPro, connected: false) == .wings(140))
        #expect(layout(nil, connected: true) == .wings(140))
        // With the animation off in Settings, AirPods fit beside the notch like anything else.
        #expect(layout(.airPodsPro, connected: true, animates: false) == .wings(140))
    }
}
