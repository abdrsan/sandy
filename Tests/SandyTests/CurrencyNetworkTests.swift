import Foundation
import Testing
@testable import Sandy

@MainActor
private final class ExchangeFixture {
    var requests: [URLRequest] = []
    var failPrimary = false
    var offline = false
    var malformed = false
    var delayUSD = false
    var usdRequested = false

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        let status = failPrimary && url.host == "cdn.jsdelivr.net" ? 503 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        let json: String
        switch url.lastPathComponent {
        case "currencies.min.json": json = #"{"usd":"US Dollar","eur":"Euro","jpy":"Japanese Yen"}"#
        case "eur.min.json": json = #"{"date":"2026-10-25","eur":{"eur":1,"usd":1.25,"jpy":150}}"#
        default:
            usdRequested = true
            if delayUSD { try await Task.sleep(for: .milliseconds(100)) }
            json = malformed ? #"{"date":"2026-10-25","usd":{"usd":true,"eur":-2}}"#
                : #"{"date":"2026-10-25","usd":{"usd":1,"eur":0.8,"jpy":120}}"#
        }
        return (Data(json.utf8), response)
    }
}

@MainActor
struct CurrencyNetworkTests {
    private func defaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set("usd", forKey: "currency.source")
        defaults.set("eur", forKey: "currency.target")
        return defaults
    }

    @Test func convertsBothDirectionsAndFallsBackWhenPrimaryFails() async throws {
        let domain = "SandyTests.Currency.\(UUID())"
        let defaults = try defaults(domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let fixture = ExchangeFixture()
        fixture.failPrimary = true
        let store = CurrencyStore(defaults: defaults, fetchData: { try await fixture.fetch($0) })
        await store.refresh()
        #expect(store.failure == nil)
        #expect(store.rateBase == "usd")
        #expect(fixture.requests.contains { $0.url?.host == "latest.currency-api.pages.dev" })
        #expect(fixture.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        store.setSourceText("10")
        #expect(CurrencyStore.parse(store.targetText) == 8)
        store.setTargetText("16")
        #expect(CurrencyStore.parse(store.sourceText) == 20)
        #expect(store.filtered(query: "jpy").first?.displayCode == "JPY")
        #expect(store.filtered(query: "Euro").first?.code == "eur")
    }

    @Test func offlineAndMalformedDataShowErrorsWithoutInventingRates() async throws {
        for malformed in [false, true] {
            let domain = "SandyTests.Currency.\(UUID())"
            let defaults = try defaults(domain)
            defer { defaults.removePersistentDomain(forName: domain) }
            let fixture = ExchangeFixture()
            fixture.offline = !malformed
            fixture.malformed = malformed
            let store = CurrencyStore(defaults: defaults, fetchData: { try await fixture.fetch($0) })
            await store.refresh()
            #expect(store.failure != nil)
            #expect(store.rates.isEmpty)
            #expect(store.targetText.isEmpty)
            #expect(!store.isLoading)
        }
    }

    @Test func slowOldResponseCannotReplaceCurrentCurrencyTable() async throws {
        let domain = "SandyTests.Currency.\(UUID())"
        let defaults = try defaults(domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let fixture = ExchangeFixture()
        fixture.delayUSD = true
        let store = CurrencyStore(defaults: defaults, fetchData: { try await fixture.fetch($0) })
        let old = Task { await store.refresh() }
        while !fixture.usdRequested { await Task.yield() }
        store.sourceCode = "eur"
        store.targetCode = "jpy"
        await store.refresh()
        await old.value
        #expect(store.rateBase == "eur")
        store.setSourceText("2")
        #expect(CurrencyStore.parse(store.targetText) == 300)
    }

    @Test func changingBaseHidesPreviousAmountUntilNewRatesArrive() async throws {
        let domain = "SandyTests.Currency.\(UUID())"
        let defaults = try defaults(domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let fixture = ExchangeFixture()
        let store = CurrencyStore(defaults: defaults, fetchData: { try await fixture.fetch($0) })
        await store.refresh()
        store.setSourceText("10")
        #expect(!store.targetText.isEmpty)
        store.sourceCode = "eur"
        #expect(store.targetText.isEmpty)
        await store.refresh()
    }
}
