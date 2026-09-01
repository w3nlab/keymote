import Testing
import Foundation
@testable import SriVibeCore

@Test func tapFiresOnRelease() {
    var engine = ButtonGestureEngine(holdThresholdMilliseconds: 600)
    let start = Date(timeIntervalSince1970: 10)
    engine.press(.center, at: start)
    #expect(engine.advance(to: start.addingTimeInterval(0.5)).isEmpty)
    #expect(engine.release(.center, at: start.addingTimeInterval(0.51)) == [.perform(.center, .tap)])
}

@Test func holdSuppressesTap() {
    var engine = ButtonGestureEngine(holdThresholdMilliseconds: 600)
    let start = Date(timeIntervalSince1970: 10)
    engine.press(.playPause, at: start)
    #expect(engine.advance(to: start.addingTimeInterval(0.6)) == [.perform(.playPause, .hold)])
    #expect(engine.release(.playPause, at: start.addingTimeInterval(0.7)).isEmpty)
}

@Test func cancellationPreventsAStaleHoldOrTap() {
    var engine = ButtonGestureEngine(holdThresholdMilliseconds: 600)
    let start = Date(timeIntervalSince1970: 10)
    engine.press(.playPause, at: start)
    engine.cancelAll()
    #expect(engine.advance(to: start.addingTimeInterval(1)).isEmpty)
    #expect(engine.release(.playPause, at: start.addingTimeInterval(1)).isEmpty)
}

@Test func profileResolutionAndDefaultMappings() {
    #expect(AppProfile.forBundleIdentifier("com.mitchellh.ghostty") == .ghostty)
    #expect(AppProfile.forBundleIdentifier("io.appmakes.otty") == .otty)
    #expect(AppProfile.forBundleIdentifier("com.google.Chrome") == .chrome)
    #expect(AppProfile.forBundleIdentifier("com.microsoft.edgemac") == .edge)
    #expect(AppProfile.forBundleIdentifier("unknown") == .default)
    let config = AppConfiguration()
    #expect(config.mappings[.terminal]?.action(for: .center, gesture: .tap) == .confirm)
    #expect(config.mappings[.default]?.action(for: .back, gesture: .hold) == .quitApplication)
    #expect(config.mappings[.chatGPT]?.action(for: .playPause, gesture: .tap) == RemoteAction.none)
    #expect(config.mappings[.chatGPT]?.action(for: .tv, gesture: .hold) == .useDefault)
    #expect(config.mappings[.terminal]?.action(for: .playPause, gesture: .tap) == RemoteAction.none)
    #expect(config.mappings[.terminal]?.action(for: .playPause, gesture: .hold) == RemoteAction.none)
    #expect(config.mappings[.otty]?.action(for: .playPause, gesture: .tap) == RemoteAction.none)
    #expect(config.mappings[.chrome]?.action(for: .up, gesture: .tap) == .arrowUp)
    #expect(config.mappings[.chrome]?.action(for: .playPause, gesture: .tap) == .togglePlayPause)
    #expect(config.mappings[.chrome]?.action(for: .playPause, gesture: .hold) == RemoteAction.none)
    #expect(config.mappings[.default]?.action(for: .mute, gesture: .tap) == .toggleMute)
}

@Test func nonTerminalProfilesRejectTerminalTabActions() {
    var config = AppConfiguration()
    var chatGPT = config.mappings[.chatGPT]!
    chatGPT.set(.nextTerminalTab, for: .center, gesture: .tap)
    config.mappings[.chatGPT] = chatGPT
    #expect(config.normalized().mappings[.chatGPT]?.action(for: .center, gesture: .tap) == RemoteAction.none)
}

@Test func profileCanInheritADefaultBinding() {
    var config = AppConfiguration()
    var chrome = config.mappings[.chrome]!
    chrome.set(.useDefault, for: .tv, gesture: .tap)
    config.mappings[.chrome] = chrome
    #expect(config.mappings[.default]?.action(for: .tv, gesture: .tap) == .launchSelectedApplication)
}

@Test func siriRemoteA2854AdapterMapsOnlyVerifiedHIDUsages() {
    let adapter = AppleSiriRemoteA2854Adapter()
    #expect(adapter.vendorID == 0x004C)
    #expect(adapter.productID == 0x0315)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0x42)) == .up)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0x80)) == .center)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0x60)) == .tv)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0x04)) == .siri)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0xE9)) == .volumeUp)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0xEA)) == .volumeDown)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0xE2)) == .mute)
    #expect(adapter.button(for: .init(page: 0x01, usage: 0x86)) == .back)
    #expect(adapter.button(for: .init(page: 0x0C, usage: 0xFFFF)) == nil)
}

@Test func voiceConfigurationDefaultsSafelyToLocalAndDisabled() {
    let configuration = AppConfiguration()
    #expect(configuration.voiceInputMode == .disabled)
    #expect(configuration.transcriptionSource == .localSpeech)
    #expect(configuration.cloudTranscriptionProvider == .openAI)
    #expect(configuration.normalized().cloudProviders?[.openAI] != nil)
    #expect(CloudProvider.anthropic.supportsTranscription == false)
    #expect(CloudProvider.openRouter.supportsTranscription == true)
}
