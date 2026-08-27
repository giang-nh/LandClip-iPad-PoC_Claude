import XCTest
@testable import LandClipIPad

private struct SuccessfulScanner: PackageScanning {
    func scan(packageURL: URL) async throws -> PackageCatalog {
        PackageCatalog(
            packageName: packageURL.lastPathComponent,
            packageSize: 42,
            layers: [LayerInfo(id: "main/roads", geodatabase: "main.gdb", name: "roads", geometryType: "LineString", featureCount: 3)]
        )
    }
}

@MainActor
final class PackageCatalogModelTests: XCTestCase {
    private struct ExpectedCatalog: Decodable {
        struct Layer: Decodable {
            let name: String
            let geometryType: String
            let featureCount: Int
        }

        let crs: String
        let layers: [Layer]
    }

    func testNativeBridgeReportsBuildConfiguration() {
        let reader = NativeGeodatabaseReader()

        if reader.isAvailable {
            XCTAssertNotEqual(reader.engineVersion, "poc-no-gdal")
        } else {
            XCTAssertEqual(reader.engineVersion, "poc-no-gdal")
            XCTAssertThrowsError(try reader.read(gdbURL: URL(fileURLWithPath: "/tmp/sample.gdb"))) { error in
                guard let nativeError = error as? NativeGeodatabaseError,
                      case .unavailable = nativeError else {
                    return XCTFail("Expected native engine unavailable error")
                }
            }
        }
    }

    func testScanPublishesCatalog() async {
        let model = PackageCatalogModel(scanner: SuccessfulScanner())
        await model.scan(URL(fileURLWithPath: "/tmp/sample.ppkx"))

        guard case let .ready(catalog) = model.state else {
            return XCTFail("Expected ready state")
        }
        XCTAssertEqual(catalog.packageName, "sample.ppkx")
        XCTAssertEqual(catalog.layers.first?.name, "roads")
    }

    func testNativeOpenFileGDBCatalog() throws {
        let reader = NativeGeodatabaseReader()
        guard reader.isAvailable else {
            throw XCTSkip("Native GDAL is only enabled by project-native.yml")
        }
        let bundle = Bundle(for: Self.self)
        let gdbURL = bundle.url(
            forResource: "sample",
            withExtension: "gdb",
            subdirectory: "public"
        ) ?? bundle.url(forResource: "sample", withExtension: "gdb")
        let expectedURL = bundle.url(
            forResource: "expected-catalog",
            withExtension: "json",
            subdirectory: "public"
        ) ?? bundle.url(forResource: "expected-catalog", withExtension: "json")
        guard let gdbURL, let expectedURL else {
            return XCTFail("Public OpenFileGDB fixture is missing from the test bundle")
        }

        let expected = try JSONDecoder().decode(
            ExpectedCatalog.self,
            from: Data(contentsOf: expectedURL)
        )
        let actual = try reader.read(gdbURL: gdbURL)

        XCTAssertEqual(actual.map(\.name), expected.layers.map(\.name))
        XCTAssertEqual(actual.map(\.geometryType), expected.layers.map(\.geometryType))
        XCTAssertEqual(actual.map(\.featureCount), expected.layers.map { Optional($0.featureCount) })
        XCTAssertTrue(actual.allSatisfy { $0.crs?.isEmpty == false })
        XCTAssertEqual(expected.crs, "EPSG:9210")
    }

    func testNativePPKXEndToEnd() async throws {
        guard NativeGeodatabaseReader().isAvailable else {
            throw XCTSkip("Native GDAL is only enabled by project-native.yml")
        }
        let bundle = Bundle(for: Self.self)
        let packageURL = bundle.url(
            forResource: "sample",
            withExtension: "ppkx",
            subdirectory: "public"
        ) ?? bundle.url(forResource: "sample", withExtension: "ppkx")
        guard let packageURL else {
            return XCTFail("Synthetic PPKX fixture is missing from the test bundle")
        }

        let catalog = try await NativePackageScanner().scan(packageURL: packageURL)

        XCTAssertEqual(catalog.packageName, "sample.ppkx")
        XCTAssertEqual(Set(catalog.layers.map(\.name)), Set([
            "sample_lines",
            "sample_points",
            "sample_polygons",
        ]))
        XCTAssertEqual(catalog.layers.compactMap(\.featureCount).reduce(0, +), 6)
    }
}
