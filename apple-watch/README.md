# SplitStone – iOS & watchOS App

SwiftUI-app för att visa och styra SplitStone från iPhone och Apple Watch.

## Struktur

```
apple-watch/
  Shared/
    Models/
      SplitStoneModels.swift     – Gemensamma modeller (SystemState, TimerState m.m.)
    Networking/
      SplitStoneClient.swift     – REST + WebSocket-klient
  SplitStoneIOS/
    SplitStoneIOSApp.swift       – App entry point
    ContentView.swift           – Portrait + Landscape views
  SplitStoneWatch/
    SplitStoneWatchApp.swift     – Watch App entry point
    WatchContentView.swift      – Tider + kontroller
```

## Skapa Xcode-projekt

1. Öppna Xcode → **File → New → Project**
2. Välj **iOS → App**
   - Product Name: `SplitStone`
   - Bundle ID: `com.yourname.splitstone`
   - Interface: SwiftUI
   - Deployment Target: **iOS 26**
3. Lägg till watchOS-target: **File → New → Target → watchOS → Watch App**
   - Product Name: `SplitStoneWatch`
   - Deployment Target: **watchOS 11**
   - Kryssa i "Include Notification Scene": nej

## Lägg till källfiler

Drag-och-släpp filerna till rätt targets i Xcode:

| Fil | Target |
|-----|--------|
| `Shared/Models/SplitStoneModels.swift` | iOS + watchOS |
| `Shared/Networking/SplitStoneClient.swift` | iOS + watchOS |
| `SplitStoneIOS/SplitStoneIOSApp.swift` | iOS |
| `SplitStoneIOS/ContentView.swift` | iOS |
| `SplitStoneWatch/SplitStoneWatchApp.swift` | watchOS |
| `SplitStoneWatch/WatchContentView.swift` | watchOS |

> Välj båda targets för Shared-filerna (kryssa i checkboxarna i "Target Membership").

## Orientering (iOS)

I Xcode → Targets → SplitStone → General → Device Orientation:
- ✅ Portrait
- ✅ Landscape Left
- ✅ Landscape Right

## Info.plist – tillåt HTTP

Lägg till i iOS targets `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

Eller mer specifikt:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>192.168.50.1</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

## Byt server-IP

Om Pi:n har annan IP, ändra i `SplitStoneIOSApp.swift`:

```swift
_client = StateObject(wrappedValue: SplitStoneClient(state: s, serverBase: "http://192.168.50.1:8080"))
```

## Funktioner

### iOS
- **Portrait**: tidskort staplade + Rearm-knapp + historik
- **Landscape**: tidskort + Rearm till vänster, historik till höger
- **WebSocket** för realtidsuppdateringar
- Timglas-logotyp i rosa/orange

### watchOS
- Tider-tab + Kontroll-tab (carousel)
- **Polling** var 1.5s (WebSocket stöds inte fullt ut på watchOS)
- Haptic feedback vid Rearm/Cancel
