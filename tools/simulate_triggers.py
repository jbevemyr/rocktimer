#!/usr/bin/env python3
"""
Simulera sensortriggers för testning.
Skickar UDP-meddelanden direkt till servern.
"""

import socket
import time
import json
import argparse
from datetime import datetime

DEFAULT_SERVER = "192.168.50.1"
DEFAULT_PORT = 5000


def send_trigger(sock, server_addr, device_id: str):
    """Skicka en trigger-händelse."""
    payload = {
        'type': 'trigger',
        'device_id': device_id,
        'timestamp_ns': time.time_ns()
    }
    
    data = json.dumps(payload).encode('utf-8')
    sock.sendto(data, server_addr)
    print(f"[{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] Trigger skickad: {device_id}")


def simulate_stone_pass(sock, server_addr, delay_tee_hog: float = 3.1, delay_hog_hog: float = 10.3):
    """Simulera att en sten passerar alla tre sensorer."""
    print("\nSimulerar stenpassage...")
    print(f"  Tee → Hog (nära): {delay_tee_hog}s")
    print(f"  Hog (nära) → Hog (avlägsen): {delay_hog_hog}s")
    print()
    
    # Tee
    send_trigger(sock, server_addr, "tee")
    
    # Hog close
    time.sleep(delay_tee_hog)
    send_trigger(sock, server_addr, "hog_close")
    
    # Hog far
    time.sleep(delay_hog_hog)
    send_trigger(sock, server_addr, "hog_far")
    
    print("\nSimulering klar!")


def main():
    parser = argparse.ArgumentParser(description="Simulera RockTimer-triggers via UDP")
    parser.add_argument("--server", default=DEFAULT_SERVER, help="Server IP-adress")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Server UDP-port")
    parser.add_argument("--device", choices=["tee", "hog_close", "hog_far"], 
                       help="Skicka enskild trigger")
    parser.add_argument("--simulate", action="store_true", help="Simulera hel stenpassage")
    parser.add_argument("--tee-hog", type=float, default=3.1, 
                       help="Tid tee→hog i sekunder")
    parser.add_argument("--hog-hog", type=float, default=10.3,
                       help="Tid hog→hog i sekunder")
    
    args = parser.parse_args()
    
    server_addr = (args.server, args.port)
    print(f"Server: {server_addr[0]}:{server_addr[1]}")
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    if args.device:
        send_trigger(sock, server_addr, args.device)
    elif args.simulate:
        simulate_stone_pass(sock, server_addr, args.tee_hog, args.hog_hog)
    else:
        print("\nInget kommando angivet. Använd --help för hjälp.")
        print("\nExempel:")
        print("  python simulate_triggers.py --simulate")
        print("  python simulate_triggers.py --device tee")
    
    sock.close()


if __name__ == '__main__':
    main()
