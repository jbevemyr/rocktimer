//
//  ContentView.swift
//  RockTimer Watch App
//
//  Created by Katrin Boberg Bevemyr on 24/2/2026.
//


import SwiftUI
import WatchKit

struct WatchContentView: View {
    @EnvironmentObject var state: RockTimerState

    var body: some View {
        TabView {
            VStack(spacing: 3) {
                WatchTimesView()
                WatchControlView()
            }
        }
        .tabViewStyle(.carousel)
    }
}

// MARK: - Times View

struct WatchTimesView: View {
    @EnvironmentObject var state: RockTimerState

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(state.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(state.isConnected ? "Connected" : "Offline")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            //WatchStatusBadge(state: state.systemState)

            HStack(spacing: 8) {
                WatchTimeBlock(label: "T→H", value: state.teeHogFormatted, color: Color.tee)
                WatchTimeBlock(label: "H→H", value: state.hogHogFormatted, color: Color.hog)
            }
        }
        .padding(8)
    }
}

// MARK: - Control View

struct WatchControlView: View {
    @EnvironmentObject var state: RockTimerState
    @EnvironmentObject var client: RockTimerClient

    var body: some View {
        VStack(spacing: 12) {

            if state.systemState == .measuring {
                Button {
                    Task {
                        await client.disarm()
                        WKInterfaceDevice.current().play(.failure)
                    }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    Task {
                        await client.arm()
                        WKInterfaceDevice.current().play(.click)
                    }
                } label: {
                    Label("Rearm", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            WatchStatusBadge(state: state.systemState)
        }
        .padding(8)
    }
}

// MARK: - Supporting Views

struct WatchStatusBadge: View {
    let state: SystemState

    var body: some View {
        Text(state.displayText)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(state.color.opacity(0.25))
            .foregroundColor(state.color)
            .clipShape(Capsule())
    }
}

struct WatchTimeBlock: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 20) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.boxText)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Color.boxText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    WatchContentView()
        .environmentObject(RockTimerState())
        .environmentObject(RockTimerClient(state: RockTimerState(), usePolling: true))
}
