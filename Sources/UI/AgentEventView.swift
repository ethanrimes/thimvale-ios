import SwiftUI

/// Raw model output is a transcript, not an executable tool call. Only the
/// permission-checked executor creates a separate tool event.
struct AgentEventView: View {
    let event: AgentEvent
    @State private var expanded = false
    private var open: Bool { expanded || event.state.isActive }
    private var stateLabel: String {
        if event.kind == .generation, event.state == .running {
            return event.text.isEmpty ? "Reading prompt" : "Streaming"
        }
        return event.state.rawValue
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    if event.state.isActive { ProgressView().controlSize(.mini) }
                    else { Image(systemName: event.state == .completed ? "checkmark.circle" : "exclamationmark.circle") }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                        HStack(spacing: 5) {
                            Text(stateLabel)
                            if let end = event.finishedAt { Text("· \(max(0, end.timeIntervalSince(event.startedAt)), specifier: "%.1f")s") }
                        }.font(.caption2).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(event.kind == .tool ? "toolEvent_" + (event.call?.tool.rawValue ?? "unknown") : "generationEvent")
            if let call = event.call {
                Text(call.tool.rawValue).font(.caption2.monospaced()).foregroundStyle(Palette.accent)
                Text(call.preview).font(.caption).lineLimit(open ? nil : 2).textSelection(.enabled)
            }
            if open, !event.text.isEmpty {
                if event.kind == .tool { Text(event.state == .completed ? "Result" : "Details").font(.caption2.weight(.semibold)) }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Plain text: retrieved instructions and model JSON cannot
                            // acquire UI actions, links, or execution privileges.
                            Text(event.text).font(event.kind == .generation ? .system(size: 15) : .caption.monospaced())
                                .foregroundStyle(Palette.ink)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier(event.kind == .generation && event.state.isActive ? "liveModelOutput" : "eventOutput")
                            Color.clear.frame(height: 1).id("tail")
                        }
                    }.frame(maxHeight: 220)
                        .onChange(of: event.text) { _, _ in if event.state.isActive { proxy.scrollTo("tail", anchor: .bottom) } }
                }
            }
        }.padding(12).foregroundStyle(Palette.muted)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }
}
