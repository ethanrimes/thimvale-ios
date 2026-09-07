import SwiftUI

/// Expanding a row reveals plain text; it never grants permission or executes it.
struct AgentEventView: View {
    let event: AgentEvent
    @State private var expanded = false
    private var color: Color {
        switch event.state {
        case .failed: .red
        case .awaitingApproval: .orange
        case .cancelled: Palette.muted
        default: Palette.accent
        }
    }
    private var stateLabel: String {
        if event.kind == .generation, event.state == .running {
            return event.text.isEmpty ? "Reading prompt" : "Streaming"
        }
        return event.state.rawValue
    }
    private var target: String {
        guard let call = event.call else { return "" }
        switch call.tool {
        case .searchKnowledge, .webSearch: return call.query ?? ""
        case .listFiles, .readFile, .writeFile: return call.path?.isEmpty == false ? call.path! : (call.folder ?? ".")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() } } label: {
                HStack(alignment: .top, spacing: 10) {
                    statusIcon.frame(width: 16, height: 18).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { command; argument }
                            VStack(alignment: .leading, spacing: 4) { command; argument }
                        }
                        HStack(spacing: 6) {
                            Text(stateLabel).foregroundStyle(event.state == .awaitingApproval || event.state == .failed ? color : Palette.muted)
                            if let end = event.finishedAt {
                                Text("· \(max(0, end.timeIntervalSince(event.startedAt)), specifier: "%.1f")s").foregroundStyle(Palette.muted)
                            }
                        }.font(.system(size: 11, design: .monospaced))
                        if event.state == .failed, !event.text.isEmpty {
                            Text(event.text).font(.caption).foregroundStyle(Palette.muted).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted).padding(.top, 5)
                }.padding(.vertical, 9).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(event.kind == .tool ? "toolEvent_" + (event.call?.tool.rawValue ?? "unknown") : "generationEvent")
            .accessibilityValue(expanded ? "\(stateLabel), expanded" : "\(stateLabel), collapsed")
            .accessibilityHint("Show or hide inputs and output")
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let call = event.call { detail("INPUT", text: call.preview) }
                    if !event.text.isEmpty { detail(event.kind == .tool ? "OUTPUT" : "TRANSCRIPT", text: event.text) }
                    else { Text("No output yet.").font(.caption).foregroundStyle(Palette.muted) }
                }
                .padding(.leading, 14).padding(.vertical, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 1) }
                .padding(.leading, 7).padding(.bottom, 6)
            }
        }
    }
    private var command: some View {
        Text(event.call?.tool.rawValue ?? event.title)
            .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.ink).fixedSize(horizontal: true, vertical: false)
    }
    private var argument: some View {
        Text(target).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
    }
    @ViewBuilder private var statusIcon: some View {
        if event.state == .running || event.state == .pending {
            ProgressView().controlSize(.mini).tint(color)
        } else {
            Image(systemName: event.state == .completed ? "checkmark" : event.state == .awaitingApproval ? "pause" : event.state == .cancelled ? "stop" : "xmark")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
        }
    }
    private func detail(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
            ScrollView {
                Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.ink)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(title == "INPUT" ? "eventInput" : "eventOutput")
            }.frame(maxHeight: 220)
        }
    }
}
