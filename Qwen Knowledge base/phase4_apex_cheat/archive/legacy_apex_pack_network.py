#!/usr/bin/env python3
"""
Apex Legends Pack Network Monitor (Non-Interactive)
Captures network traffic when opening Apex Packs (skins, hierlooms)
"""

import threading
import json
import logging
import sys
from datetime import datetime
from scapy.all import sniff, IP, UDP, Raw, wrpcap
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('apex_pack_monitor.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

# Apex Legends network configuration
APEX_UDP_PORTS = (27015, 27016, 8766, 443, 80)


class ApexPacket:
    """Represents a captured Apex network packet"""
    
    def __init__(self, timestamp, src_ip, src_port, dst_ip, dst_port, 
                 protocol, payload, packet_type=None):
        self.timestamp = timestamp
        self.src_ip = src_ip
        self.src_port = src_port
        self.dst_ip = dst_ip
        self.dst_port = dst_port
        self.protocol = protocol
        self.payload = payload
        self.packet_type = packet_type
        self.metadata = {
            'encryption_key': None,      # Encryption key used for this packet
            'packet_id': None,             # Unique packet identifier
            'session_token': None,         # Session authentication token
            'signature': None,             # Packet signature/hash
            'pack_identifier': None,       # Pack-specific ID (for dupe tracking)
        }
    
    def to_dict(self):
        return {
            'timestamp': self.timestamp.isoformat(),
            'src': f"{self.src_ip}:{self.src_port}",
            'dst': f"{self.dst_ip}:{self.dst_port}",
            'protocol': self.protocol,
            'type': self.packet_type,
            'payload_hex': self.payload.hex() if isinstance(self.payload, bytes) else str(self.payload),
            'metadata': self.metadata
        }
    
    def __repr__(self):
        return f"<ApexPacket {self.packet_type or 'UNKNOWN'} {self.src_ip}:{self.src_port} -> {self.dst_ip}:{self.dst_port}>"


class ApexPackMonitor:
    """Monitor network interactions when opening Apex Packs"""
    
    def __init__(self, output_dir=None):
        self.output_dir = output_dir or "."
        self.captured_packets = []
        self.pack_interactions = defaultdict(list)
        self.current_pack_session = None
        self.packet_counter = 0
        self.capture_thread = None
        self.is_capturing = False
        
        # Encryption and identifier tracking for dupe capability
        self.encryption_keys = {
            'xor_key': None,           # XOR encryption key for packet obfuscation
            'session_token': None,     # EA session authentication token
            'pack_signature': None,    # Pack-specific signature/hash
            'server_seed': None,       # Server seed for deterministic loot generation
        }
        
        self.pack_identifiers = []   # List of pack IDs seen (for dupe tracking)
        
        # Packet type detection patterns
        self._setup_packet_patterns()
    
    def _setup_packet_patterns(self):
        """Setup packet signature patterns for Apex Pack operations"""
        self.patterns = {
            'pack_open': [
                b'\x55\xAA\x55\xAA',      # Magic header
                b'\x01\x00\x00\x00',      # Pack open command
                b'\x41\x50\x4B\x4F\x58',  # "APEX" ASCII
            ],
            'pack_response': [
                b'\xAA\x55\xAA\x55',      # Response magic
                b'\x02\x00\x00\x00',      # Pack response command
                b'\x4C\x4F\x4F\x54',      # "LOOT" for loot table
            ],
            'heirloom': [
                b'\x48\x49\x45\x52',      # "HIER"
                b'\x03\x00\x00\x00',      # Heirloom marker
                b'\xFF\x00\xFF\x00',      # High rarity indicator
            ],
        }
    
    def detect_packet_type(self, payload):
        """Detect the type of Apex packet from payload"""
        if isinstance(payload, bytes):
            payload_str = payload[:256] if len(payload) > 256 else payload
            
            for pkt_type, patterns in self.patterns.items():
                for pattern in patterns:
                    if pattern in payload_str:
                        return pkt_type
        
        return 'unknown'
    
    def extract_encryption_data(self, payload):
        """Extract encryption-related data from packet payload"""
        if not isinstance(payload, bytes):
            return {}
        
        encryption_data = {}
        
        # Look for XOR key patterns (common in EA games)
        xor_patterns = [
            (b'\x55\xAA', 'xor_pattern_1'),
            (b'\xAA\x55', 'xor_pattern_2'),
            (b'\xFF\x00', 'xor_pattern_3'),
        ]
        
        for pattern, name in xor_patterns:
            if pattern in payload:
                encryption_data[f'{name}_offset'] = payload.find(pattern)
        
        # Extract potential session token (often 16-32 bytes after magic header)
        if len(payload) > 16:
            encryption_data['session_token_candidate'] = payload[8:24].hex()
        
        # Look for pack signature/hash (typically at end of packet)
        if len(payload) > 32:
            encryption_data['packet_hash'] = payload[-16:].hex()
        
        return encryption_data
    
    def extract_pack_identifier(self, payload):
        """Extract unique identifiers needed for pack dupe"""
        if not isinstance(payload, bytes):
            return {}
        
        identifier_data = {}
        
        # Pack ID - often a 32-bit or 64-bit value
        if len(payload) >= 12:
            # Try different byte positions for pack ID
            for offset in [4, 8, 12]:
                if offset + 4 <= len(payload):
                    identifier_data[f'pack_id_{offset}'] = payload[offset:offset+4].hex()
        
        # Server seed for deterministic loot (important for dupe)
        if len(payload) >= 24:
            identifier_data['server_seed'] = payload[16:24].hex()
        
        # Pack type identifier (Rare/Epic/Legendary/Heirloom)
        if len(payload) >= 5:
            pack_type_byte = payload[4]
            type_map = {
                0x01: 'Rare',
                0x02: 'Epic', 
                0x03: 'Legendary',
                0x04: 'Heirloom',
            }
            identifier_data['pack_type'] = type_map.get(pack_type_byte, f'Unknown_{pack_type_byte}')
        
        return identifier_data
    
    def capture_packet(self, packet):
        """Callback for scapy packet capture"""
        try:
            # Extract IP layer
            if IP in packet:
                ip_layer = packet[IP]
                src_ip = ip_layer.src
                dst_ip = ip_layer.dst
                
                # Extract transport layer
                if UDP in packet:
                    udp_layer = packet[UDP]
                    src_port = udp_layer.sport
                    dst_port = udp_layer.dport
                    protocol = 'UDP'
                    
                    # Get payload
                    if Raw in packet:
                        payload = bytes(packet[Raw].load)
                    else:
                        payload = b''
                    
                    # Detect packet type
                    packet_type = self.detect_packet_type(payload)
                    
                    # Extract encryption data (critical for dupe)
                    encryption_data = self.extract_encryption_data(payload)
                    
                    # Extract pack identifiers (critical for dupe)
                    identifier_data = self.extract_pack_identifier(payload)
                    
                    # Create packet object with full metadata
                    apex_packet = ApexPacket(
                        timestamp=datetime.now(),
                        src_ip=src_ip,
                        src_port=src_port,
                        dst_ip=dst_ip,
                        dst_port=dst_port,
                        protocol=protocol,
                        payload=payload,
                        packet_type=packet_type
                    )
                    
                    # Populate metadata with encryption and identifier data
                    apex_packet.metadata['encryption_key'] = encryption_data.get('session_token_candidate')
                    apex_packet.metadata['packet_id'] = identifier_data.get('pack_id_8')
                    apex_packet.metadata['session_token'] = encryption_data.get('session_token_candidate')
                    apex_packet.metadata['signature'] = encryption_data.get('packet_hash')
                    apex_packet.metadata['pack_identifier'] = identifier_data.get('server_seed')
                    apex_packet.metadata['encryption_data'] = encryption_data
                    apex_packet.metadata['identifier_data'] = identifier_data
                    
                    self.captured_packets.append(apex_packet)
                    self.packet_counter += 1
                    
                    # Track pack interactions
                    if packet_type in ['pack_open', 'pack_response', 'heirloom']:
                        self.pack_interactions[packet_type].append(apex_packet)
                        
                        # Update encryption keys if found
                        if encryption_data.get('session_token_candidate'):
                            self.encryption_keys['session_token'] = encryption_data['session_token_candidate']
                        
                        # Track pack identifiers for dupe
                        if identifier_data.get('server_seed'):
                            self.pack_identifiers.append(identifier_data['server_seed'])
                    
                    # Log summary (throttled to avoid spam)
                    if self.packet_counter % 10 == 0 or packet_type != 'unknown':
                        logger.info(f"[{self.packet_counter}] {apex_packet}")
                        if encryption_data:
                            logger.info(f"    Encryption: {encryption_data}")
                        if identifier_data:
                            logger.info(f"    Identifiers: {identifier_data}")
                    
        except Exception as e:
            logger.error(f"Error capturing packet: {e}")
    
    def start_capture(self, interface=None):
        """Start capturing network packets in a background thread"""
        if self.is_capturing:
            logger.info("Capture already running")
            return

        self.is_capturing = True
        logger.info("Starting Apex Pack network capture...")

        # Filter for Apex-related UDP ports (Windows-compatible BPF syntax)
        # Windows/WinPcap requires: udp and (port X or port Y or port Z) - no parentheses around entire expression
        port_str = ' or '.join(f'port {p}' for p in APEX_UDP_PORTS)
        filter_str = f'udp and ({port_str})'

        def capture_loop():
            try:
                sniff(
                    prn=self.capture_packet,
                    store=False,
                    filter=filter_str,
                    iface=interface,
                    stop_filter=lambda _: not self.is_capturing
                )
            except Exception as e:
                logger.error(f"Capture error: {e}")

        self.capture_thread = threading.Thread(target=capture_loop, daemon=True)
        self.capture_thread.start()
        logger.info(f"Packet capture thread started (filter: {filter_str})")
    
    def stop_capture(self):
        """Stop the packet capture"""
        if not self.is_capturing:
            return
        
        self.is_capturing = False
        if self.capture_thread:
            self.capture_thread.join(timeout=5)
        logger.info("Packet capture stopped")
    
    def start_pack_session(self, session_name=None):
        """Mark the start of a pack opening session"""
        session_name = session_name or f"pack_session_{len(self.pack_interactions['pack_open'])}"
        self.current_pack_session = {
            'name': session_name,
            'start_time': datetime.now(),
            'packets': []
        }
        logger.info(f"Starting new pack session: {session_name}")
        return session_name
    
    def end_pack_session(self):
        """Mark the end of a pack opening session"""
        if self.current_pack_session:
            self.current_pack_session['end_time'] = datetime.now()
            duration = (self.current_pack_session['end_time'] - 
                       self.current_pack_session['start_time']).total_seconds()
            
            logger.info(f"Ending pack session: {self.current_pack_session['name']} "
                       f"(duration: {duration:.2f}s)")
            
            # Save session data
            self._save_pack_session(self.current_pack_session)
            self.current_pack_session = None
    
    def _save_pack_session(self, session):
        """Save a pack session to file"""
        session_file = f"{self.output_dir}/pack_session_{session['name']}.json"
        
        session_data = {
            'name': session['name'],
            'start_time': session['start_time'].isoformat(),
            'end_time': session.get('end_time', datetime.now()).isoformat(),
            'duration_seconds': (session.get('end_time', datetime.now()) - 
                                session['start_time']).total_seconds(),
            'packets': [p.to_dict() for p in session.get('packets', [])],
            'packet_summary': {
                pkt_type: len(pkts) 
                for pkt_type, pkts in self.pack_interactions.items()
            }
        }
        
        with open(session_file, 'w') as f:
            json.dump(session_data, f, indent=2)
        
        logger.info(f"Saved pack session to {session_file}")
    
    def save_capture(self, filename=None):
        """Save all captured packets to file"""
        filename = filename or f"{self.output_dir}/apex_pack_capture_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        # Save as JSON
        json_file = f"{filename}.json"
        with open(json_file, 'w') as f:
            json.dump([p.to_dict() for p in self.captured_packets], f, indent=2)
        
        # Save as PCAP for Wireshark compatibility
        pcap_file = f"{filename}.pcap"
        
        # Convert to scapy packets for PCAP export
        scapy_packets = []
        for pkt in self.captured_packets:
            base_pkt = IP(src=pkt.src_ip, dst=pkt.dst_ip)
            
            if pkt.protocol == 'UDP':
                udp_pkt = UDP(sport=pkt.src_port, dport=pkt.dst_port)
                base_pkt /= udp_pkt
            
            if pkt.payload:
                base_pkt /= Raw(load=pkt.payload)
            
            scapy_packets.append(base_pkt)
        
        wrpcap(pcap_file, scapy_packets)
        
        logger.info(f"Saved {len(self.captured_packets)} packets to:")
        logger.info(f"  JSON: {json_file}")
        logger.info(f"  PCAP: {pcap_file}")
        
        return json_file, pcap_file
    
    def print_summary(self):
        """Print capture summary"""
        print("\n" + "="*60)
        print("APEX PACK NETWORK CAPTURE SUMMARY")
        print("="*60)
        
        print(f"\nTotal packets captured: {len(self.captured_packets)}")
        print(f"Packet counter: {self.packet_counter}")
        
        print("\nPacket types detected:")
        for pkt_type, packets in self.pack_interactions.items():
            print(f"  - {pkt_type}: {len(packets)} packets")
        
        print("\nSample packets (first 10):")
        for pkt in self.captured_packets[:10]:
            print(f"  {pkt}")
        
        print("\n" + "="*60)


def main():
    """Main entry point"""
    import time
    output_dir = r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat"

    # Create monitor
    monitor = ApexPackMonitor(output_dir=output_dir)

    # Start packet capture in background
    monitor.start_capture()

    logger.info("Network monitor is running and listening...")
    logger.info("=== READY: Open your Apex Pack now! ===")

    # Auto-stop delay to prevent premature termination (30 seconds buffer)
    auto_stop_delay = 30  # seconds to wait before auto-stopping if no manual trigger

    try:
        # Wait with periodic status updates
        start_time = time.time()
        while monitor.is_capturing:
            elapsed = time.time() - start_time

            # Status update every 5 seconds
            if int(elapsed) % 5 == 0 and int(elapsed) != int(elapsed - 0.1):
                logger.info(f"[{int(elapsed)}s] Still listening... Pack opened yet?")

            # Auto-stop after delay (30s buffer for pack opens)
            if elapsed >= auto_stop_delay:
                logger.info(f"[{int(elapsed)}s] Auto-stopping capture (delay: {auto_stop_delay}s)...")
                break

            time.sleep(0.5)

    except KeyboardInterrupt:
        logger.info("Manual stop triggered")
    except EOFError:
        logger.info("EOF encountered (stdin likely unavailable), continuing with auto-stop")

    finally:
        # Stop capture
        monitor.stop_capture()

        # Save final capture
        monitor.save_capture()
        monitor.print_summary()

        logger.info("=== PACK NETWORK MONITORING COMPLETE ===")


def start_pack_session(monitor, session_name=None):
    """Start a new pack opening session (can be called externally)"""
    return monitor.start_pack_session(session_name)


def end_pack_session(monitor):
    """End current pack session and save (can be called externally)"""
    monitor.end_pack_session()


if __name__ == "__main__":
    main()
