import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import DyNotch

struct ShelfDropTests {
    /// Finder drops reach SwiftUI as an open-in-place file representation without public.file-url.
    @Test func resolvesInPlaceFileRepresentation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DyNotchTests-\(UUID().uuidString).md")
        try Data("# Notes".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = NSItemProvider()
        provider.registerFileRepresentation(for: try #require(UTType(filenameExtension: "md")), openInPlace: true) { completion in
            completion(url, true, nil)
            return nil
        }
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        #expect(await ShelfStore.fileURL(from: provider) == url)
    }

    @Test func resolvesFileURLRepresentation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DyNotchTests-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = try #require(NSItemProvider(contentsOf: url))
        #expect(await ShelfStore.fileURL(from: provider)?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
    }

    @Test func textWithoutAFileHasNoURL() async {
        #expect(await ShelfStore.fileURL(from: NSItemProvider(object: "hello" as NSString)) == nil)
    }
}

struct ShelfSelectionTests {
    let ids = (0..<5).map { _ in UUID() }

    @Test func clickSelectsJustThatItem() {
        var selection = ShelfSelection()
        selection.click(ids[1], in: ids)
        selection.click(ids[3], in: ids)
        #expect(selection.ids == [ids[3]])
    }

    @Test func commandClickAddsAndRemovesItems() {
        var selection = ShelfSelection()
        selection.click(ids[1], in: ids)
        selection.click(ids[3], in: ids, toggling: true)
        #expect(selection.ids == [ids[1], ids[3]])
        selection.click(ids[1], in: ids, toggling: true)
        #expect(selection.ids == [ids[3]])
    }

    @Test func shiftClickAddsTheItemsFromTheLastOneClicked() {
        var selection = ShelfSelection()
        selection.click(ids[0], in: ids)
        selection.click(ids[3], in: ids, toggling: true)
        selection.click(ids[1], in: ids, extending: true)
        #expect(selection.ordered(ids) == [ids[0], ids[1], ids[2], ids[3]])
    }

    @Test func arrowsMoveAndShiftArrowsSpanFromWhereTheyStarted() {
        var selection = ShelfSelection()
        // Nothing selected: → starts at the first item, ← at the last.
        selection.move(by: 1, in: ids)
        #expect(selection.ids == [ids[0]])
        selection.move(by: 1, in: ids)
        selection.move(by: 1, in: ids, extending: true)
        selection.move(by: 1, in: ids, extending: true)
        #expect(selection.ordered(ids) == [ids[1], ids[2], ids[3]])
        selection.move(by: -1, in: ids, extending: true)
        #expect(selection.ordered(ids) == [ids[1], ids[2]])
        selection.move(by: -1, in: ids)
        selection.move(by: -1, in: ids)
        #expect(selection.ids == [ids[0]])

        var fresh = ShelfSelection()
        fresh.move(by: -1, in: ids)
        #expect(fresh.ids == [ids[4]])
    }

    @Test func selectAllKeepsTheArrowsWhereTheyWere() {
        var selection = ShelfSelection()
        selection.click(ids[2], in: ids)
        selection.selectAll(ids)
        #expect(selection.ids == Set(ids))
        #expect(selection.cursor == ids[2])
    }

    @Test func menuCommandsActOnTheSelectionOnlyWhenTheItemIsInIt() {
        var selection = ShelfSelection()
        selection.click(ids[3], in: ids)
        selection.click(ids[1], in: ids, toggling: true)
        #expect(selection.targets(for: ids[3], in: ids) == [ids[1], ids[3]])
        #expect(selection.targets(for: ids[2], in: ids) == [ids[2]])
    }

    @Test func forgetsItemsThatLeftTheShelf() {
        var selection = ShelfSelection()
        selection.click(ids[4], in: ids)
        selection.selectAll(ids)
        selection.keep(only: Array(ids.prefix(2)))
        #expect(selection.ids == [ids[0], ids[1]])
        #expect(selection.cursor == nil)
    }
}

struct ShelfStoreTests {
    /// A store in a folder of its own, next to `count` new files.
    private func makeStore(files count: Int) throws -> (store: ShelfStore, files: [URL], folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DyNotchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try (0..<count).map { n in
            let url = folder.appendingPathComponent("File \(n).txt")
            try Data("\(n)".utf8).write(to: url)
            return url
        }
        return (ShelfStore(directory: folder), files, folder)
    }

    @Test func movesItemsKeepingTheirOrder() throws {
        let (store, files, folder) = try makeStore(files: 5)
        defer { try? FileManager.default.removeItem(at: folder) }
        store.add(files)
        let ids = store.items.map(\.id)
        store.move([ids[3], ids[1]], to: 0)
        #expect(store.items.map(\.id) == [ids[1], ids[3], ids[0], ids[2], ids[4]])
        store.move([ids[1]], to: 5)
        #expect(store.items.map(\.id) == [ids[3], ids[0], ids[2], ids[4], ids[1]])
        // Dropped back where it already is.
        store.move([ids[2]], to: 3)
        #expect(store.items.map(\.id) == [ids[3], ids[0], ids[2], ids[4], ids[1]])
    }

    @Test func addsFilesWhereTheyAreDroppedAndKeepsTheOrder() throws {
        let (store, files, folder) = try makeStore(files: 3)
        defer { try? FileManager.default.removeItem(at: folder) }
        store.add(Array(files.prefix(2)))
        // File 0 is on the shelf already, so only File 2 goes in, before File 1.
        store.add([files[2], files[0]], at: 1)
        #expect(store.items.map(\.name) == ["File 0.txt", "File 2.txt", "File 1.txt"])
        #expect(store.takeRecentlyAdded() == [store.items[1].id])
        #expect(store.takeRecentlyAdded().isEmpty)

        store.remove([store.items[0].id])
        let reloaded = ShelfStore(directory: folder)
        #expect(reloaded.items.map(\.name) == ["File 2.txt", "File 1.txt"])
    }
}
