import XCTest
import CoreLocation
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

    private struct ExpectedClip: Decodable {
        struct Layer: Decodable {
            let sourceLayer: String
            let status: String
            let candidateCount: Int
            let outputCount: Int
        }
        let writtenLayerCount: Int
        let layers: [Layer]
    }

    func testWriteAOIClosesRingAndUsesLonLat() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aoi-\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: url) }

        try LandClipViewModel.writeAOI([
            CLLocationCoordinate2D(latitude: 10, longitude: 106),
            CLLocationCoordinate2D(latitude: 10, longitude: 107),
            CLLocationCoordinate2D(latitude: 11, longitude: 107),
        ], to: url)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let json = try XCTUnwrap(object as? [String: Any])
        let features = try XCTUnwrap(json["features"] as? [[String: Any]])
        let geometry = try XCTUnwrap(features.first?["geometry"] as? [String: Any])
        let ring = try XCTUnwrap((geometry["coordinates"] as? [[[Double]]])?.first)

        XCTAssertEqual(ring.count, 4, "ring should be closed")
        XCTAssertEqual(ring.first, ring.last)
        XCTAssertEqual(ring.first, [106, 10], "GeoJSON is [lon, lat]")
    }

    func testNativeClipPipeline() throws {
        let engine = NativeClipEngine()
        guard engine.isAvailable else {
            throw XCTSkip("Native GDAL is only enabled by project-native.yml")
        }
        let bundle = Bundle(for: Self.self)
        guard
            let gdbURL = bundle.url(forResource: "sample", withExtension: "gdb", subdirectory: "public")
                ?? bundle.url(forResource: "sample", withExtension: "gdb"),
            let aoiURL = bundle.url(forResource: "sample-aoi", withExtension: "geojson", subdirectory: "public")
                ?? bundle.url(forResource: "sample-aoi", withExtension: "geojson"),
            let expectedURL = bundle.url(forResource: "expected-clip", withExtension: "json", subdirectory: "public")
                ?? bundle.url(forResource: "expected-clip", withExtension: "json")
        else {
            return XCTFail("Clip fixtures are missing from the test bundle")
        }

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let events = NSMutableArray()
        let result = try engine.clip(gdbURLs: [gdbURL], aoiURL: aoiURL, outputDirectory: outputDirectory) { json in
            if let event = GISProgressEvent.decode(json) { events.add(event.event) }
            return false
        }

        let expected = try JSONDecoder().decode(ExpectedClip.self, from: Data(contentsOf: expectedURL))
        XCTAssertEqual(result.writtenLayerCount, expected.writtenLayerCount)
        for expectedLayer in expected.layers {
            guard let actual = result.layers.first(where: { $0.sourceLayer == expectedLayer.sourceLayer }) else {
                return XCTFail("Missing result for \(expectedLayer.sourceLayer)")
            }
            XCTAssertEqual(actual.status, expectedLayer.status, expectedLayer.sourceLayer)
            XCTAssertEqual(actual.candidateCount, expectedLayer.candidateCount, expectedLayer.sourceLayer)
            XCTAssertEqual(actual.outputCount, expectedLayer.outputCount, expectedLayer.sourceLayer)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputGeoPackage))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.summaryCsv))
        let gpkgSize = (try FileManager.default.attributesOfItem(atPath: result.outputGeoPackage)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(gpkgSize, 0)
        XCTAssertTrue(events.contains("complete"))
        XCTAssertTrue(events.contains("layer_done"))
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
