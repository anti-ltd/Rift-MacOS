import Testing
@testable import RiftCore

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    @Test func newerVersion() {
        #expect(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        #expect(UpdateChecker.isNewer("2.0.0", than: "1.99.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.9", than: "1.1.0"))
    }
}

@Suite("DiscordModels")
struct DiscordModelsTests {
    @Test func guildInitial() {
        let g = Guild(id: "1", name: "Anti Limited")
        #expect(g.initial == "A")
    }

    @Test func channelSymbols() {
        #expect(Channel.Kind.text.symbol == "number")
        #expect(Channel.Kind.voice.symbol == "speaker.wave.2")
    }
}
