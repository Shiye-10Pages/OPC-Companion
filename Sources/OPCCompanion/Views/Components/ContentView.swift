import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        MainTabView()
            .frame(width: 760, height: 520)
            .overlay(alignment: .top) {
                if let banner = state.banner {
                    BannerView(message: banner)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(banner.id)
                }
            }
            .animation(AppAnimations.smooth, value: state.banner?.id)
    }
}
