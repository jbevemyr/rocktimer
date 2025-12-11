#!/usr/bin/env python3
"""
Simulera sensortriggers för testning.
Skickar UDP-meddelanden direkt till servern.
"""

import socket
import time
import json
import argparse
import random
from datetime import datetime

DEFAULT_SERVER = "192.168.50.1"
DEFAULT_PORT = 5000

# Realistiska tidsintervall (sekunder)
TEE_HOG_MIN = 2.80
TEE_HOG_MAX = 3.30
HOG_HOG_MIN = 8.0
HOG_HOG_MAX = 14.0


def send_trigger(sock, server_addr, device_id: str):
    """Skicka en trigger-händelse."""
    payload = {
        'type': 'trigger',
        'device_id': device_id,
        'timestamp_ns': time.time_ns()
    }
    
    data = json.dumps(payload).encode('utf-8')
    sock.sendto(data, server_addr)
    print(f"[{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] Trigger: {device_id}")


def simulate_stone_pass(sock, server_addr, delay_tee_hog: float = None, delay_hog_hog: float = None, skip_far: bool = False):
    """Simulera att en sten passerar sensorer."""
    
    # Slumpa tider om inte angivna
    if delay_tee_hog is None:
        delay_tee_hog = random.uniform(TEE_HOG_MIN, TEE_HOG_MAX)
    if delay_hog_hog is None:
        delay_hog_hog = random.uniform(HOG_HOG_MIN, HOG_HOG_MAX)
    
    print(f"\n🥌 Simulerar stenpassage...")
    print(f"   Tee → Hog: {delay_tee_hog:.2f}s")
    if not skip_far:
        print(f"   Hog → Hog: {delay_hog_hog:.2f}s")
    else:
        print(f"   (Stenen når inte bortre hog)")
    print()
    
    # Tee
    send_trigger(sock, server_addr, "tee")
    
    # Hog close
    time.sleep(delay_tee_hog)
    send_trigger(sock, server_addr, "hog_close")
    
    # Hog far (om stenen når dit)
    if not skip_far:
        time.sleep(delay_hog_hog)
        send_trigger(sock, server_addr, "hog_far")
    
    print("\n✓ Klar!")


def main():
    parser = argparse.ArgumentParser(description="Simulera RockTimer-triggers via UDP")
    parser.add_argument("--server", default=DEFAULT_SERVER, help="Server IP-adress")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Server UDP-port")
    parser.add_argument("--device", choices=["tee", "hog_close", "hog_far"], 
                       help="Skicka enskild trigger")
    parser.add_argument("--simulate", action="store_true", help="Simulera hel stenpassage")
    parser.add_argument("--tee-hog", type=float, default=None, 
                       help=f"Tid tee→hog i sekunder (default: slump {TEE_HOG_MIN}-{TEE_HOG_MAX})")
    parser.add_argument("--hog-hog", type=float, default=None,
                       help=f"Tid hog→hog i sekunder (default: slump {HOG_HOG_MIN}-{HOG_HOG_MAX})")
    parser.add_argument("--skip-far", action="store_true", 
                       help="Simulera att stenen inte når bortre hog")
    parser.add_argument("--loop", type=int, default=1,
                       help="Antal stenpassager att simulera")
    parser.add_argument("--delay", type=float, default=3.0,
                       help="Sekunder mellan stenpassager vid --loop")
    
    args = parser.parse_args()
    
    server_addr = (args.server, args.port)
    print(f"Server: {server_addr[0]}:{server_addr[1]}")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    if args.device:
        send_trigger(sock, server_addr, args.device)
    elif args.simulate:
        for i in range(args.loop):
            if args.loop > 1:
                print(f"\n{'='*40}")
                print(f"Sten {i+1} av {args.loop}")
                print(f"{'='*40}")
            
            simulate_stone_pass(
                sock, server_addr, 
                args.tee_hog, args.hog_hog,
                args.skip_far
            )
            
            if i < args.loop - 1:
                print(f"\nVäntar {args.delay}s innan nästa sten...")
                time.sleep(args.delay)
    else:
        print("\nInget kommando angivet. Använd --help för hjälp.")
        print("\nExempel:")
        print("  python simulate_triggers.py --simulate              # En sten, slumpade tider")
        print("  python simulate_triggers.py --simulate --loop 5     # 5 stenar")
        print("  python simulate_triggers.py --simulate --skip-far   # Sten som inte når dit")
        print("  python simulate_triggers.py --device tee            # Enskild trigger")
    
    sock.close()


if __name__ == '__main__':
    main()
