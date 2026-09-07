#if DEBUG && targetEnvironment(simulator)
import Foundation

extension AppState {
    /// Real local artifacts, imported through production services into an isolated test session.
    /// This entry point is absent from device and Release builds.
    func prepareUITestFixtures() async throws {
        guard AppPaths.testSession != nil,
              let path = ProcessInfo.processInfo.environment["THIMVALE_UI_FIXTURES"] else { return }
        let marker = AppPaths.root.appendingPathComponent("fixtures-ready")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let source = URL(fileURLWithPath: path, isDirectory: true)
        await importModel(source.appendingPathComponent("Vendor/smoke-model.gguf"))
        if let error { throw PocketError.message(error) }
        await importArchive(source.appendingPathComponent("Vendor/smoke-wikipedia.zim"))
        if let error { throw PocketError.message(error) }
        _ = try await knowledge.importURL(source.appendingPathComponent("Tests/Fixtures/Field notes.md")) { _ in }
        await refreshKnowledge()
        try Data().write(to: marker, options: .atomic)
    }
}
#endif
