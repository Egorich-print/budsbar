import Testing
@testable import BudsCore

@Suite("FreeBuds Pro 5")
struct FreeBudsPro5Tests {
    @Test("Recognizes the model reported by the Pro 5")
    func identifiesModel() {
        var identity = DeviceIdentity()
        identity.modelCode = "BTFT0023"
        #expect(identity.displayName == "HUAWEI FreeBuds Pro 5")
    }

    @Test("Advertised disabled gesture remains 255 through a write")
    func disabledGestureRoundTrip() throws {
        let response = Frame(command: Command.doubleTap, fields: [
            Tag.options: [1, 7, 2, 0, 0xFF]
        ])
        let action = try #require(response.byteList(Tag.options)?.last)
        #expect(action == GestureAction.disabled.rawValue)
        #expect(GestureAction.title(for: action) == "Do Nothing")
        #expect(ProtocolCatalogue.setDoubleTap(side: .right, action: action)
            .fields[Tag.right] == [0xFF])
        #expect(ProtocolCatalogue.setLongTap(side: .left, action: action)
            .fields[Tag.left] == [0xFF])
    }
}
