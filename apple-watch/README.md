# RockTimer Apple Watch App

Apple Watch-app för att visa curling-tider och arma tidtagningssystemet.

## Bygga appen

### Förutsättningar
- macOS med Xcode 15+
- Apple Developer-konto (för att köra på fysisk klocka)

### Steg

1. Öppna `RockTimer.xcodeproj` i Xcode

2. Konfigurera server-adressen i `TimerViewModel.swift`:
   ```swift
   private let serverURL = "http://192.168.50.1:8080"
   ```

3. Välj "RockTimer WatchKit App" som target

4. Kör på simulator eller fysisk Apple Watch

## Funktioner

- **Visa tider**: Total tid, Tee→Hog, Hog→Hog
- **Arma system**: Starta en ny mätning
- **Avbryt**: Avbryt pågående mätning
- **Haptisk feedback**: Vibration vid nya tider

## Nätverkskonfiguration

Apple Watch kommunicerar via iPhone när den inte är på samma WiFi.
För bästa resultat, se till att iPhone är ansluten till samma WiFi (192.168.50.x).

### Alternativ: WatchConnectivity

För en mer robust lösning kan appen modifieras att använda WatchConnectivity
för att kommunicera via den parade iPhonen. Detta kräver en kompletterande
iOS-app.

## Felsökning

### Appen kan inte ansluta
1. Kontrollera att Pi 4 är igång och nåbar
2. Verifiera att iPhone är på samma WiFi-nätverk
3. Testa att öppna http://192.168.50.1:8080 i Safari på iPhone

### Tider uppdateras inte
- Appen pollar servern var sekund
- Kontrollera nätverksanslutningen

