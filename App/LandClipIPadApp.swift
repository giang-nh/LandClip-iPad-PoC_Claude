import SwiftUI

@main
struct LandClipIPadApp: App {
    var body: some Scene {
        WindowGroup {
            PackageCatalogView(model: PackageCatalogModel(scanner: DefaultPackageScanner()))
        }
    }
}
