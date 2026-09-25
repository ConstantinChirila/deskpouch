import CoreGraphics
import Foundation
import Testing
@testable import DeskpouchCore

@MainActor
struct ThumbnailCacheTests {
    nonisolated static func pixel() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    static func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/thumbs/\(name)") }

    /// Asks until the image is there; generation runs on other turns of the main actor.
    func load(_ url: URL, from cache: ThumbnailCache) async -> CGImage? {
        for _ in 0..<200 {
            if let image = cache.image(for: url) { return image }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    /// Waits for the generation of `url` to land, however busy the main actor is with other tests.
    func settle(_ url: URL, in cache: ThumbnailCache) async {
        for _ in 0..<400 where cache.isPending(url) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func leastRecentlyUsedIsEvicted() async {
        let generated = Counter()
        let cache = ThumbnailCache(maximumSize: ThumbnailCache.panelSize, countLimit: 2, now: Date.init) { _, _ in
            generated.increment()
            return Self.pixel()
        }
        #expect(await load(Self.url("a"), from: cache) != nil)
        #expect(await load(Self.url("b"), from: cache) != nil)
        // "a" is asked for again, so "b" is the one to go.
        #expect(cache.image(for: Self.url("a")) != nil)
        #expect(await load(Self.url("c"), from: cache) != nil)
        #expect(generated.value == 3)
        #expect(cache.image(for: Self.url("a")) != nil)
        #expect(cache.image(for: Self.url("c")) != nil)
        #expect(generated.value == 3)
        #expect(cache.image(for: Self.url("b")) == nil)
        #expect(await load(Self.url("b"), from: cache) != nil)
        #expect(generated.value == 4)
    }

    @Test func failedFileIsTriedAgainLater() async {
        var date = Date(timeIntervalSince1970: 1000)
        let exists = Counter()
        let generated = Counter()
        let cache = ThumbnailCache(maximumSize: ThumbnailCache.panelSize, countLimit: 10, now: { date }) { _, _ in
            generated.increment()
            return exists.value > 0 ? Self.pixel() : nil
        }
        let url = Self.url("late.png")
        #expect(cache.image(for: url) == nil)
        await settle(url, in: cache)
        #expect(generated.value == 1)
        exists.increment()
        // Still inside the retry interval: the cache decides synchronously not to generate again, so nothing is
        // pending (no timing involved) and the generator was not called a second time.
        date += ThumbnailCache.failedRetryInterval - 1
        #expect(cache.image(for: url) == nil)
        #expect(!cache.isPending(url))
        #expect(generated.value == 1)
        date += 1
        #expect(await load(url, from: cache) != nil)
    }

    @Test func forgetRetriesAtOnceAndRemoveAllEmpties() async {
        let exists = Counter()
        let cache = ThumbnailCache(maximumSize: ThumbnailCache.panelSize, countLimit: 10, now: Date.init) { _, _ in
            exists.value > 0 ? Self.pixel() : nil
        }
        let url = Self.url("saved.png")
        #expect(cache.image(for: url) == nil)
        await settle(url, in: cache)
        exists.increment()
        cache.forget(url)
        #expect(await load(url, from: cache) != nil)
        cache.removeAll()
        #expect(cache.image(for: url) == nil)
    }

    @Test func onlyAFewGenerateAtOnce() async {
        let active = Counter()
        let peak = Counter()
        let cache = ThumbnailCache(maximumSize: ThumbnailCache.panelSize, countLimit: 50, now: Date.init) { _, _ in
            peak.raise(to: active.increment())
            try? await Task.sleep(for: .milliseconds(10))
            active.decrement()
            return Self.pixel()
        }
        let urls = (0..<20).map { Self.url("\($0)") }
        for url in urls { _ = cache.image(for: url) }
        for url in urls { #expect(await load(url, from: cache) != nil) }
        #expect(peak.value == ThumbnailCache.maxConcurrent)
    }
}

/// A number the generator closures can change from off the main actor.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
    func decrement() { lock.withLock { count -= 1 } }
    func raise(to other: Int) { lock.withLock { count = max(count, other) } }
}
