import SwiftUI

@main
struct LandClipIPadApp: App {
    @StateObject private var profile = UserProfile()
    @StateObject private var ratings = RatingStore()

    var body: some Scene {
        WindowGroup {
            LandClipView()
                .environmentObject(profile)
                .environmentObject(ratings)
        }
    }
}
