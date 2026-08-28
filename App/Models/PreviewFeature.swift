import Foundation
import CoreLocation
import MapKit

/// A single feature decoded from a GeoJSON FeatureCollection, ready for SwiftUI
/// `Map` content and an attribute table.
struct PreviewFeature: Identifiable {
    enum Shape {
        case point(CLLocationCoordinate2D)
        case line([CLLocationCoordinate2D])
        case polygon([CLLocationCoordinate2D])
    }

    let id: Int
    let attributes: [(key: String, value: String)]
    let shapes: [Shape]

    var boundingRegion: MKCoordinateRegion? {
        let coordinates: [CLLocationCoordinate2D] = shapes.flatMap { shape -> [CLLocationCoordinate2D] in
            switch shape {
            case let .point(coordinate): return [coordinate]
            case let .line(coordinates): return coordinates
            case let .polygon(coordinates): return coordinates
            }
        }
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.0005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.0005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    static func decodeCollection(_ data: Data) -> [PreviewFeature] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawFeatures = object["features"] as? [[String: Any]]
        else { return [] }

        return rawFeatures.enumerated().map { index, raw in
            let properties = (raw["properties"] as? [String: Any]) ?? [:]
            let attributes = properties
                .map { (key: $0.key, value: stringify($0.value)) }
                .sorted { $0.key < $1.key }
            let shapes = (raw["geometry"] as? [String: Any]).map(decodeGeometry) ?? []
            return PreviewFeature(id: index, attributes: attributes, shapes: shapes)
        }
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case is NSNull: return ""
        default: return String(describing: value)
        }
    }

    private static func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
        guard pair.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
    }

    private static func decodeGeometry(_ geometry: [String: Any]) -> [Shape] {
        guard let type = geometry["type"] as? String else { return [] }
        let coordinates = geometry["coordinates"]
        switch type {
        case "Point":
            if let pair = coordinates as? [Double], let point = coordinate(pair) { return [.point(point)] }
        case "MultiPoint":
            if let pairs = coordinates as? [[Double]] {
                return pairs.compactMap { coordinate($0).map(Shape.point) }
            }
        case "LineString":
            if let pairs = coordinates as? [[Double]] {
                return [.line(pairs.compactMap(coordinate))]
            }
        case "MultiLineString":
            if let lines = coordinates as? [[[Double]]] {
                return lines.map { .line($0.compactMap(coordinate)) }
            }
        case "Polygon":
            if let rings = coordinates as? [[[Double]]], let exterior = rings.first {
                return [.polygon(exterior.compactMap(coordinate))]
            }
        case "MultiPolygon":
            if let polygons = coordinates as? [[[[Double]]]] {
                return polygons.compactMap { $0.first.map { .polygon($0.compactMap(coordinate)) } }
            }
        case "GeometryCollection":
            if let geometries = geometry["geometries"] as? [[String: Any]] {
                return geometries.flatMap(decodeGeometry)
            }
        default:
            break
        }
        return []
    }
}
