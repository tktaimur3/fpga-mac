"""
Send a barebones broadcast Ethernet frame whose payload is "HELLO WORLD".

Requires scapy (`pip install scapy`). On Windows scapy also needs Npcap
(https://npcap.com/) installed for raw L2 send.

Usage:
    python send_hello.py                            # auto-pick default iface
    python send_hello.py -i "Ethernet"              # pick by friendly name (Windows)
    python send_hello.py -i "\\Device\\NPF_{...}"   # pick by NPF GUID
    python send_hello.py -l                         # list interfaces and exit
"""

import argparse
import sys

from scapy.all import Dot3, Raw, sendp, conf


BROADCAST = "ff:ff:ff:ff:ff:ff"
SRC_MAC   = "02:de:ad:be:ef:02"  # locally-administered, distinct from FPGA's 02:de:ad:be:ef:01


def list_interfaces() -> None:
    """Print friendly name + MAC + NPF device path for every iface scapy knows."""
    try:
        from scapy.arch.windows import get_windows_if_list
        ifaces = get_windows_if_list()
        header = f"{'NAME':<40} {'MAC':<20} DEVICE"
        print(header)
        print("-" * len(header))
        for i in ifaces:
            name = i.get("name", "")
            mac  = i.get("mac", "")
            guid = i.get("guid", "")
            dev  = f"\\Device\\NPF_{guid}" if guid else ""
            print(f"{name:<40} {mac:<20} {dev}")
    except ImportError:
        # non-Windows — just dump what scapy has
        from scapy.all import get_if_list
        for n in get_if_list():
            print(n)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--iface", help="interface (friendly name or NPF device)")
    parser.add_argument("-l", "--list", action="store_true", help="list interfaces and exit")
    parser.add_argument("-n", "--count", type=int, default=1, help="number of frames to send")
    args = parser.parse_args()

    if args.list:
        list_interfaces()
        return 0

    iface = args.iface or conf.iface
    payload = b"HELLO WORLD"
    length  = len(payload)

    # Pad payload so the full frame (14B header + payload) is >= 60 bytes
    # (minimum Ethernet frame size excluding FCS, which the NIC appends).
    MIN_FRAME = 60
    HEADER    = 14
    if len(payload) < MIN_FRAME - HEADER:
        payload = payload + b"\x00" * (MIN_FRAME - HEADER - len(payload))

    # IEEE 802.3: the 2 bytes after src MAC are a length field (= payload length),
    # not an ethertype. Values <= 0x05DC (1500) are interpreted as length.
    # The length field carries the *unpadded* payload length, per spec.
    frame = Dot3(dst=BROADCAST, src=SRC_MAC, len=length) / Raw(load=payload)

    print(f"iface   : {iface}")
    print(f"dst     : {BROADCAST}")
    print(f"src     : {SRC_MAC}")
    print(f"length  : {length}")
    print(f"payload : {payload!r} ({len(payload)} bytes, incl. pad)")
    print(f"frame   : {bytes(frame).hex()} ({len(bytes(frame))} bytes)")

    sendp(frame, iface=str(iface), count=args.count, verbose=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
