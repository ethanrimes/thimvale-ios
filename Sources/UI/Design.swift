import SwiftUI

enum Palette {
    static let ink = Color.primary
    static let accent = Color(light: UIColor(red: 0.18, green: 0.34, blue: 0.29, alpha: 1), dark: UIColor(red: 0.58, green: 0.79, blue: 0.67, alpha: 1))
    static let background = Color(light: UIColor(red: 0.97, green: 0.965, blue: 0.945, alpha: 1), dark: UIColor(red: 0.065, green: 0.08, blue: 0.075, alpha: 1))
    static let surface = Color(light: .white, dark: UIColor(red: 0.115, green: 0.135, blue: 0.12, alpha: 1))
    static let muted = Color.secondary
    static let tint = accent.opacity(0.09)
    static let line = Color.primary.opacity(0.08)
}
private extension Color {
    init(light: UIColor, dark: UIColor) { self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}

struct BrandMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.57, weight: .medium))
            .foregroundStyle(Palette.accent)
            .frame(width: size, height: size)
            .background(Palette.tint, in: RoundedRectangle(cornerRadius: size * 0.32))
            .accessibilityHidden(true)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 1))
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(Palette.background)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FamilyIcon: View {
    let family: String
    var body: some View {
        Text(String(family.prefix(1))).font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(Palette.accent).frame(width: 44, height: 44)
            .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SectionHeading: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Palette.muted) }
        }.padding(.top, 6)
    }
}

struct RootView: View {
    @Bindable var state: AppState
    @State private var settings = false
    var body: some View {
        TabView(selection: $state.selectedTab) {
            ChatView(state: state).tag(0).tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            ModelsView(state: state).tag(1).tabItem { Label("Models", systemImage: "square.stack.3d.up") }
            KnowledgeView(state: state).tag(2).tabItem { Label("Knowledge", systemImage: "books.vertical") }
            PermissionsView(state: state).tag(3).tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
        .tint(Palette.accent)
        .sheet(item: $state.approval, onDismiss: { state.approve(false) }) { request in
            ApprovalView(state: state, request: request).interactiveDismissDisabled()
        }
        .alert("PocketMind", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .alert("Library update", isPresented: Binding(get: { state.notice != nil }, set: { if !$0 { state.notice = nil } })) {
            Button("OK") { state.notice = nil }
        } message: { Text(state.notice ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in state.stop(); state.save() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in state.stop() }
    }
}
