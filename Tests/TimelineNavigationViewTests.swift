import SwiftUI
import UIKit
import XCTest
@testable import ImmichApp

@MainActor
final class TimelineNavigationViewTests: XCTestCase {
    private var window: UIWindow?
    private var host: UIHostingController<AnyView>?
    private var previousKeyWindow: UIWindow?
    private var cachedKeys: [String] = []

    override func tearDown() async throws {
        closeHost()
        for key in cachedKeys { ImageMemoryCache.shared.remove(for: key) }
        cachedKeys.removeAll()
        try await super.tearDown()
    }

    func testMonthlyMosaicsLayOutOneTwoAndThreeDistinctDates() async throws {
        for count in 1...3 {
            let item = makeMonth(year: 2026, month: 9, highlightCount: count)
            let position = TimelineOverviewPosition()
            position.itemID = item.id
            show(TimelineNavigatorView(
                mode: .months,
                items: [item],
                position: position,
                isActive: true,
                returnToNewestRequest: 0,
                onSelect: { _ in }))

            await waitForLayout("All \(count) date cards should have visible frames") {
                position.viewport.width > 0
                    && position.cardFrames.count == count
                    && position.cardFrames.values.allSatisfy {
                        $0.width > 0 && $0.height > 0
                            && position.viewport.contains($0)
                    }
            }

            XCTAssertEqual(
                Set(position.cardFrames.keys),
                Set(item.highlights.map(\.targetAssetID)))
            let frames = try item.highlights.map {
                try XCTUnwrap(position.cardFrames[$0.targetAssetID])
            }
            let mosaicWidth = min(position.viewport.width, 900) - 40
            let mosaicHeight = mosaicWidth / 1.5
            XCTAssertEqual(frames[0].height, mosaicHeight, accuracy: 1)

            switch count {
            case 1:
                XCTAssertEqual(frames[0].width, mosaicWidth, accuracy: 1)
            case 2:
                XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 1)
                XCTAssertEqual(frames[1].height, mosaicHeight, accuracy: 1)
                XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1)
                XCTAssertEqual(frames[1].minX - frames[0].maxX, 6, accuracy: 1)
                XCTAssertEqual(frames[1].maxX - frames[0].minX, mosaicWidth, accuracy: 1)
            default:
                XCTAssertEqual(frames[0].width, (mosaicWidth - 6) * 2 / 3, accuracy: 1)
                XCTAssertEqual(frames[1].width, frames[2].width, accuracy: 1)
                XCTAssertEqual(frames[1].height, (mosaicHeight - 6) / 2, accuracy: 1)
                XCTAssertEqual(frames[1].height, frames[2].height, accuracy: 1)
                XCTAssertEqual(frames[1].minX - frames[0].maxX, 6, accuracy: 1)
                XCTAssertEqual(frames[1].minY, frames[0].minY, accuracy: 1)
                XCTAssertEqual(frames[2].minY - frames[1].maxY, 6, accuracy: 1)
                XCTAssertEqual(frames[2].maxY, frames[0].maxY, accuracy: 1)
                XCTAssertEqual(frames[1].maxX - frames[0].minX, mosaicWidth, accuracy: 1)
                attachSnapshot(named: "Months — three date highlights")
            }
            closeHost()
        }
    }

    func testSwitchingMonthAndYearPanesRetainsTheirScrollPositions() async throws {
        let fixture = makeOverviewFixture()
        show(fixture)
        await waitForLayout("Both overviews should restore their requested middle periods") {
            self.isVisible(fixture.months[10].cover.id, in: fixture.monthPosition)
                && self.isVisible(fixture.years[3].cover.id, in: fixture.yearPosition)
                && fixture.monthPosition.itemID == "2024-06"
                && fixture.yearPosition.itemID == "2024"
        }
        let monthFrames = fixture.monthPosition.cardFrames
        let yearFrames = fixture.yearPosition.cardFrames

        fixture.navigation.mode = .years
        await settleLayout()
        XCTAssertEqual(fixture.monthPosition.itemID, "2024-06")
        XCTAssertEqual(fixture.yearPosition.itemID, "2024")
        assertFrameUnchanged(
            for: fixture.years[3].cover.id,
            before: yearFrames,
            after: fixture.yearPosition.cardFrames)

        fixture.navigation.mode = .months
        await settleLayout()
        XCTAssertEqual(fixture.monthPosition.itemID, "2024-06")
        XCTAssertEqual(fixture.yearPosition.itemID, "2024")
        assertFrameUnchanged(
            for: fixture.months[10].cover.id,
            before: monthFrames,
            after: fixture.monthPosition.cardFrames)
    }

    func testReselectingYearsReturnsOnlyActivePaneToNewest() async throws {
        let fixture = makeOverviewFixture()
        fixture.navigation.mode = .years
        show(fixture)
        await waitForLayout("Initial overview positions should be ready") {
            fixture.monthPosition.itemID == "2024-06"
                && fixture.yearPosition.itemID == "2024"
                && self.isVisible(fixture.months[10].cover.id, in: fixture.monthPosition)
                && self.isVisible(fixture.years[3].cover.id, in: fixture.yearPosition)
        }
        let monthFrames = fixture.monthPosition.cardFrames
        let newest = try XCTUnwrap(fixture.years.last)

        fixture.navigation.tap(.years)
        await waitForLayout("Reselect should reveal the latest year without resetting Months") {
            guard let frame = fixture.yearPosition.cardFrames[newest.cover.id] else { return false }
            return frame.height > 0 && fixture.yearPosition.viewport.contains(frame)
        }
        await settleLayout()

        XCTAssertEqual(fixture.navigation.returnToNewestRequest, 1)
        XCTAssertEqual(fixture.monthPosition.itemID, "2024-06")
        assertFrameUnchanged(
            for: fixture.months[10].cover.id,
            before: monthFrames,
            after: fixture.monthPosition.cardFrames)
    }

    private func makeOverviewFixture() -> OverviewFixture {
        let months = (2021...2026).flatMap { year in
            [1, 6, 9].map { month in
                makeMonth(year: year, month: month, highlightCount: 1)
            }
        }
        let years = stride(from: 0, to: months.count, by: 3).map { index in
            let month = months[index]
            let year = String(month.id.prefix(4))
            return TimelineNavigationItem(id: year, title: year, cover: month.cover)
        }
        let monthPosition = TimelineOverviewPosition()
        monthPosition.itemID = "2024-06"
        let yearPosition = TimelineOverviewPosition()
        yearPosition.itemID = "2024"
        let navigation = TimelineNavigationState()
        navigation.mode = .months
        return OverviewFixture(
            months: months,
            years: years,
            monthPosition: monthPosition,
            yearPosition: yearPosition,
            navigation: navigation)
    }

    private func makeMonth(year: Int, month: Int, highlightCount: Int) -> TimelineNavigationItem {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let colors: [UIColor] = [.systemIndigo, .systemOrange, .systemTeal]
        let monthID = String(format: "%04d-%02d", year, month)
        let highlights = (0..<highlightCount).map { index in
            let day = [14, 15, 20][index]
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
            let asset = AssetLite(
                id: "navigation-view-test-\(UUID().uuidString)",
                isVideo: false,
                ratio: 1,
                thumbhash: nil,
                createdAt: date,
                isFavorite: false)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
                .image { context in
                    colors[index].setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                }
            let key = ImageCache.memoryKey(
                "\(asset.id)-thumbnail", PhotoThumbnailLoader.maxPixelSize)
            ImageMemoryCache.shared.insert(image, for: key)
            cachedKeys.append(key)
            return TimelineDayHighlight(
                id: "\(monthID)-\(day)",
                date: date,
                title: String(day),
                count: 4 - index,
                cover: asset)
        }
        return TimelineNavigationItem(
            id: monthID,
            title: month == 9 ? "Sep \(year)" : monthID,
            cover: highlights[0].cover,
            highlights: highlights)
    }

    private func show<Content: View>(_ content: Content) {
        closeHost()
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        previousKeyWindow = scene?.windows.first(where: \.isKeyWindow)
        let controller = UIHostingController(rootView: AnyView(
            content
                .environment(SessionManager())
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()))
        guard let scene else {
            XCTFail("The app test host should have a window scene")
            return
        }
        let testWindow = UIWindow(windowScene: scene)
        testWindow.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        testWindow.rootViewController = controller
        testWindow.makeKeyAndVisible()
        controller.view.frame = testWindow.bounds
        host = controller
        window = testWindow
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    private func closeHost() {
        window?.isHidden = true
        window?.rootViewController = nil
        host = nil
        window = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    /// Wait for actual geometry rather than sleeping for an assumed animation duration.
    private func waitForLayout(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        until predicate: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            await settleLayout()
            if predicate() { return }
        } while Date() < deadline
        XCTFail(message, file: file, line: line)
    }

    private func settleLayout() async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    self.window?.layoutIfNeeded()
                    self.host?.view.setNeedsLayout()
                    self.host?.view.layoutIfNeeded()
                    continuation.resume()
                }
            }
        }
    }

    private func isVisible(_ assetID: String, in position: TimelineOverviewPosition) -> Bool {
        guard let frame = position.cardFrames[assetID] else { return false }
        return frame.width > 0 && frame.height > 0 && frame.intersects(position.viewport)
    }

    private func assertFrameUnchanged(
        for assetID: String,
        before: [String: CGRect],
        after: [String: CGRect],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let old = before[assetID], let new = after[assetID] else {
            XCTFail("Expected the same date card to remain mounted", file: file, line: line)
            return
        }
        XCTAssertEqual(old.minY, new.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(old.height, new.height, accuracy: 1, file: file, line: line)
    }

    private func attachSnapshot(named name: String) {
        guard let host else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private struct OverviewFixture: View {
    let months: [TimelineNavigationItem]
    let years: [TimelineNavigationItem]
    let monthPosition: TimelineOverviewPosition
    let yearPosition: TimelineOverviewPosition
    let navigation: TimelineNavigationState

    var body: some View {
        ZStack {
            TimelineNavigatorView(
                mode: .months,
                items: months,
                position: monthPosition,
                isActive: navigation.mode == .months,
                returnToNewestRequest: navigation.returnToNewestRequest,
                onSelect: { _ in })
                .opacity(navigation.mode == .months ? 1 : 0)
            TimelineNavigatorView(
                mode: .years,
                items: years,
                position: yearPosition,
                isActive: navigation.mode == .years,
                returnToNewestRequest: navigation.returnToNewestRequest,
                onSelect: { _ in })
                .opacity(navigation.mode == .years ? 1 : 0)
        }
    }
}
