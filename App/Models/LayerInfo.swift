import Foundation

struct LayerInfo: Identifiable, Equatable, Sendable {
    let id: String
    let geodatabase: String
    let name: String
    let geometryType: String
    let featureCount: Int?
    let crs: String?

    init(
        id: String,
        geodatabase: String,
        name: String,
        geometryType: String,
        featureCount: Int?,
        crs: String? = nil
    ) {
        self.id = id
        self.geodatabase = geodatabase
        self.name = name
        self.geometryType = geometryType
        self.featureCount = featureCount
        self.crs = crs
    }
}

struct PackageCatalog: Equatable, Sendable {
    let packageName: String
    let packageSize: Int64
    let layers: [LayerInfo]
}
