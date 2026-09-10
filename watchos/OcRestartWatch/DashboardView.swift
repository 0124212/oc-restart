import SwiftUI

struct DashboardView: View {
    @StateObject private var sync = SyncService()
    @State private var showingServices = false
    
    var body: some View {
        NavigationView {
            List {
                // Connection status
                HStack {
                    Circle()
                        .fill(sync.connected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(sync.connected ? "Connected" : "Disconnected")
                        .font(.caption)
                }
                
                // Server status
                if let status = sync.status {
                    Section("Server") {
                        StatusRow(label: "Uptime", value: status.uptime)
                        StatusRow(label: "CPU", value: status.cpu)
                        StatusRow(label: "Memory", value: status.memory)
                        StatusRow(label: "Disk", value: status.disk)
                        StatusRow(label: "OpenCode", value: status.opencode)
                    }
                }
                
                // Quick restart
                Section {
                    Button(action: { sync.restart("opencode") }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Restart OpenCode")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
                
                // Services summary
                if !sync.services.isEmpty {
                    Section("Services") {
                        let running = sync.services.filter { $0.isRunning }.count
                        let total = sync.services.count
                        
                        HStack {
                            Text("\(running)/\(total) up")
                                .font(.caption)
                            Spacer()
                            Button("Details") { showingServices = true }
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("ak")
            .sheet(isPresented: $showingServices) {
                ServicesListView(services: sync.services, sync: sync)
            }
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            if value == "active" || value == "running" {
                Text(value)
                    .foregroundColor(.green)
                    .font(.caption)
            } else if value == "inactive" || value == "failed" {
                Text(value)
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                Text(value)
                    .font(.caption)
            }
        }
    }
}

struct ServicesListView: View {
    let services: [Service]
    let sync: SyncService
    
    var body: some View {
        List(services) { service in
            HStack {
                Circle()
                    .fill(service.isRunning ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading) {
                    Text(service.name)
                        .font(.caption)
                    Text(service.status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { sync.restart(service.name) }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle("Services")
    }
}

#Preview {
    DashboardView()
}
