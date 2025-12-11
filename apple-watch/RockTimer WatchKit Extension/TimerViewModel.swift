//
//  TimerViewModel.swift
//  RockTimer WatchKit Extension
//
//  ViewModel för att hantera kommunikation med RockTimer-servern
//

import Foundation
import Combine
import WatchKit

class TimerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var systemState: SystemState = .idle
    @Published var teeToHogMs: Double?
    @Published var hogToHogMs: Double?
    @Published var totalMs: Double?
    @Published var isConnected: Bool = false
    
    // MARK: - Configuration
    /// Ändra denna till din Pi 4:s IP-adress
    private let serverURL = "http://192.168.50.1:8080"
    
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var totalTimeFormatted: String {
        guard let ms = totalMs else { return "--" }
        let seconds = ms / 1000.0
        return String(format: "%.2fs", seconds)
    }
    
    var teeToHogFormatted: String {
        guard let ms = teeToHogMs else { return "--" }
        return String(format: "%.0f", ms)
    }
    
    var hogToHogFormatted: String {
        guard let ms = hogToHogMs else { return "--" }
        let seconds = ms / 1000.0
        return String(format: "%.2f", seconds)
    }
    
    // MARK: - Initialization
    init() {
        startPolling()
    }
    
    deinit {
        stopPolling()
    }
    
    // MARK: - Polling
    private func startPolling() {
        // Polla servern var sekund
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchStatus()
        }
        
        // Hämta status direkt
        fetchStatus()
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - API Calls
    func fetchStatus() {
        guard let url = URL(string: "\(serverURL)/api/status") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Fel vid hämtning av status: \(error)")
                    self?.isConnected = false
                    return
                }
                
                guard let data = data else {
                    self?.isConnected = false
                    return
                }
                
                self?.isConnected = true
                self?.parseStatusResponse(data)
            }
        }.resume()
    }
    
    private func parseStatusResponse(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(StatusResponse.self, from: data)
            
            // Uppdatera state
            if let state = SystemState(rawValue: response.state) {
                systemState = state
            }
            
            // Uppdatera tider
            teeToHogMs = response.session.tee_to_hog_close_ms
            hogToHogMs = response.session.hog_to_hog_ms
            totalMs = response.session.total_ms
            
            // Vibrera vid ny tid
            if response.session.is_complete && systemState != .completed {
                WKInterfaceDevice.current().play(.success)
            }
            
        } catch {
            print("Fel vid parsning av status: \(error)")
        }
    }
    
    func armSystem() {
        guard let url = URL(string: "\(serverURL)/api/arm") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if error == nil {
                    // Haptisk feedback
                    WKInterfaceDevice.current().play(.click)
                    self?.fetchStatus()
                }
            }
        }.resume()
    }
    
    func disarmSystem() {
        guard let url = URL(string: "\(serverURL)/api/disarm") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if error == nil {
                    WKInterfaceDevice.current().play(.click)
                    self?.fetchStatus()
                }
            }
        }.resume()
    }
}

// MARK: - API Response Models
struct StatusResponse: Codable {
    let state: String
    let session: SessionData
    let sensors: [String: SensorStatus]
}

struct SessionData: Codable {
    let tee_to_hog_close_ms: Double?
    let hog_to_hog_ms: Double?
    let total_ms: Double?
    let is_complete: Bool
}

struct SensorStatus: Codable {
    let online: Bool
    let last_seen: String?
}

