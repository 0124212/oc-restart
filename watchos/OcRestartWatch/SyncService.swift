import Foundation
import SwiftUI

class SyncService: ObservableObject {
    private let token = "d204f2016b28c0c50c793df833c9be3d370662a5dcfc5c8ebedf110e034388a9"
    private let wsURL = "ws://100.115.178.90:4099"
    
    @Published var status: ServerStatus?
    @Published var services: [Service] = []
    @Published var connected = false
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession
    private var reconnectTimer: Timer?
    
    init() {
        session = URLSession(configuration: .default)
        connect()
    }
    
    func connect() {
        guard let url = URL(string: "\(wsURL)?token=\(token)") else { return }
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        send(token)
        listen()
    }
    
    func send(_ text: String) {
        webSocket?.send(.string(text)) { _ in }
    }
    
    func restart(_ target: String) {
        let msg = ["type": "restart", "target": target]
        if let data = try? JSONSerialization.data(withJSONObject: msg),
           let text = String(data: data, encoding: .utf8) {
            send(text)
        }
    }
    
    private func listen() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleMessage(text)
                }
                self?.listen()
            case .failure:
                DispatchQueue.main.async {
                    self?.connected = false
                }
                self?.scheduleReconnect()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.connected = true
            
            if json["type"] as? String == "snapshot",
               let statusDict = json["status"] as? [String: Any] {
                self?.status = ServerStatus(
                    uptime: statusDict["uptime"] as? String ?? "—",
                    cpu: "\(statusDict["load"] ?? "—") · \(statusDict["temp"] ?? "—")",
                    memory: statusDict["mem"] as? String ?? "—",
                    disk: statusDict["disk"] as? String ?? "—",
                    opencode: statusDict["opencode"] as? String ?? "—"
                )
                
                if let servicesArray = json["services"] as? [[String: Any]] {
                    self?.services = servicesArray.map { dict in
                        Service(
                            name: dict["name"] as? String ?? "?",
                            state: dict["state"] as? String ?? "unknown",
                            status: dict["status"] as? String ?? ""
                        )
                    }
                }
            } else if json["type"] as? String == "restarted" {
                // Show restart confirmation
                break
            }
        }
    }
    
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}

struct ServerStatus {
    let uptime: String
    let cpu: String
    let memory: String
    let disk: String
    let opencode: String
}

struct Service: Identifiable {
    let id = UUID()
    let name: String
    let state: String
    let status: String
    
    var isRunning: Bool { state == "running" }
}
