import Foundation

@MainActor
final class PackageCatalogModel: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning(String)
        case ready(PackageCatalog)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private let scanner: any PackageScanning

    init(scanner: any PackageScanning) {
        self.scanner = scanner
    }

    func scan(_ url: URL) async {
        state = .scanning(url.lastPathComponent)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            state = .ready(try await scanner.scan(packageURL: url))
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
