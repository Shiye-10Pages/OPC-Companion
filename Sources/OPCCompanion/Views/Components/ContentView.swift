import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        MainTabView()
            .frame(width: 760, height: 520)
    }
}