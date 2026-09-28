#!/usr/bin/env python3
"""
Network scanner: discover live hosts on local subnets, then scan their open ports.
Usage: python network_scan.py [--ports 22,80,443] [--top-ports 100] [--timeout 1.0]
"""

import argparse
import ipaddress
import platform
import socket
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field

# fmt: off
TOP_1000_PORTS = [
    21, 22, 23, 25, 53, 80, 110, 111, 119, 135, 139, 143, 194, 389, 443, 445,
    465, 500, 514, 515, 587, 631, 636, 873, 902, 990, 993, 995, 1080, 1194,
    1433, 1434, 1521, 1723, 2049, 2082, 2083, 2100, 2222, 2375, 2376, 3000,
    3306, 3389, 3690, 4444, 4848, 5000, 5432, 5900, 5985, 5986, 6379, 6443,
    6881, 7070, 7443, 8000, 8008, 8080, 8081, 8443, 8888, 9000, 9090, 9200,
    9300, 9418, 9999, 10000, 11211, 27017, 27018, 50000,
]
# fmt: on

SERVICE_NAMES = {
    21: "ftp", 22: "ssh", 23: "telnet", 25: "smtp", 53: "dns", 80: "http",
    110: "pop3", 111: "rpcbind", 135: "msrpc", 139: "netbios-ssn", 143: "imap",
    389: "ldap", 443: "https", 445: "smb", 465: "smtps", 587: "submission",
    636: "ldaps", 993: "imaps", 995: "pop3s", 1433: "mssql", 1521: "oracle",
    2049: "nfs", 2375: "docker", 2376: "docker-tls", 3306: "mysql",
    3389: "rdp", 5432: "postgresql", 5900: "vnc", 5985: "winrm",
    5986: "winrm-https", 6379: "redis", 8080: "http-alt", 8443: "https-alt",
    9200: "elasticsearch", 9300: "elasticsearch-cluster", 27017: "mongodb",
}


@dataclass
class Host:
    ip: str
    open_ports: list[int] = field(default_factory=list)
    hostname: str = ""


def get_local_interfaces() -> list[dict]:
    """Return list of {interface, ip, prefix_len} dicts for non-loopback IPv4 interfaces."""
    interfaces = []
    try:
        import socket
        import struct
        import fcntl  # Linux/macOS only

        # Fallback handled below for Windows
    except ImportError:
        pass

    if platform.system() == "Windows":
        interfaces = _get_interfaces_windows()
    else:
        interfaces = _get_interfaces_unix()

    return interfaces


def _get_interfaces_windows() -> list[dict]:
    try:
        import subprocess
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-NetIPAddress -AddressFamily IPv4 | "
             "Where-Object {$_.InterfaceAlias -notlike '*Loopback*'} | "
             "Select-Object InterfaceAlias,IPAddress,PrefixLength | "
             "ConvertTo-Json"],
            capture_output=True, text=True, timeout=10
        )
        import json
        data = json.loads(result.stdout)
        if isinstance(data, dict):
            data = [data]
        return [
            {"interface": d["InterfaceAlias"], "ip": d["IPAddress"], "prefix_len": d["PrefixLength"]}
            for d in data
            if not d["IPAddress"].startswith("169.254")  # exclude APIPA
        ]
    except Exception as e:
        print(f"[!] Could not enumerate interfaces: {e}", file=sys.stderr)
        return []


def _get_interfaces_unix() -> list[dict]:
    try:
        import netifaces
        results = []
        for iface in netifaces.interfaces():
            addrs = netifaces.ifaddresses(iface)
            if netifaces.AF_INET not in addrs:
                continue
            for addr in addrs[netifaces.AF_INET]:
                ip = addr.get("addr", "")
                netmask = addr.get("netmask", "255.255.255.0")
                if ip.startswith("127.") or ip.startswith("169.254"):
                    continue
                # Convert netmask to prefix length
                prefix_len = sum(bin(int(x)).count("1") for x in netmask.split("."))
                results.append({"interface": iface, "ip": ip, "prefix_len": prefix_len})
        return results
    except ImportError:
        pass

    # Fallback: parse `ip addr`
    try:
        out = subprocess.check_output(["ip", "-4", "addr"], text=True)
        results = []
        current_iface = ""
        for line in out.splitlines():
            line = line.strip()
            if line and not line.startswith(" ") and not line.startswith("inet"):
                current_iface = line.split(":")[1].strip() if ":" in line else ""
            if line.startswith("inet ") and "scope global" in line:
                parts = line.split()
                cidr = parts[1]
                ip, prefix_len = cidr.split("/")
                if not ip.startswith("127.") and not ip.startswith("169.254"):
                    results.append({"interface": current_iface, "ip": ip, "prefix_len": int(prefix_len)})
        return results
    except Exception:
        return []


def ping_host(ip: str, timeout: float = 1.0) -> bool:
    """Return True if the host responds to ping."""
    param = "-n" if platform.system() == "Windows" else "-c"
    timeout_param = ["-w", str(int(timeout * 1000))] if platform.system() == "Windows" else ["-W", str(int(timeout))]
    try:
        result = subprocess.run(
            ["ping", param, "1"] + timeout_param + [ip],
            capture_output=True, timeout=timeout + 2
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def resolve_hostname(ip: str) -> str:
    try:
        return socket.gethostbyaddr(ip)[0]
    except (socket.herror, socket.gaierror):
        return ""


def scan_port(ip: str, port: int, timeout: float) -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            return s.connect_ex((ip, port)) == 0
    except (socket.error, OSError):
        return False


def discover_hosts(subnet: ipaddress.IPv4Network, timeout: float, workers: int) -> list[str]:
    hosts = [str(ip) for ip in subnet.hosts()]
    live = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(ping_host, ip, timeout): ip for ip in hosts}
        for f in as_completed(futures):
            ip = futures[f]
            if f.result():
                live.append(ip)
    return sorted(live, key=lambda x: ipaddress.IPv4Address(x))


def scan_ports(ip: str, ports: list[int], timeout: float, workers: int) -> list[int]:
    open_ports = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(scan_port, ip, p, timeout): p for p in ports}
        for f in as_completed(futures):
            if f.result():
                open_ports.append(futures[f])
    return sorted(open_ports)


def print_banner():
    print("=" * 60)
    print("  Network Scanner — host discovery + port scan")
    print("=" * 60)


def print_host_result(host: Host):
    name = f"  ({host.hostname})" if host.hostname else ""
    print(f"\n[+] {host.ip}{name}")
    if host.open_ports:
        for port in host.open_ports:
            svc = SERVICE_NAMES.get(port, "unknown")
            print(f"    {port:<7} {svc}")
    else:
        print("    (no open ports found)")


def main():
    parser = argparse.ArgumentParser(description="Discover hosts and scan open ports on local subnets.")
    parser.add_argument("--ports", help="Comma-separated port list (e.g. 22,80,443)")
    parser.add_argument("--top-ports", type=int, default=100, metavar="N",
                        help="Scan top N common ports (default: 100, max: %(default)s available)")
    parser.add_argument("--timeout", type=float, default=1.0, help="Socket/ping timeout in seconds (default: 1.0)")
    parser.add_argument("--ping-workers", type=int, default=100, help="Threads for host discovery (default: 100)")
    parser.add_argument("--port-workers", type=int, default=200, help="Threads for port scanning (default: 200)")
    parser.add_argument("--no-ping", action="store_true", help="Skip ping, scan all IPs directly")
    parser.add_argument("--subnet", help="Override: scan a specific subnet (e.g. 192.168.1.0/24)")
    args = parser.parse_args()

    if args.ports:
        ports = [int(p.strip()) for p in args.ports.split(",")]
    else:
        n = min(args.top_ports, len(TOP_1000_PORTS))
        ports = TOP_1000_PORTS[:n]

    print_banner()
    print(f"[*] Ports to scan : {len(ports)} ({ports[0]}..{ports[-1]})")
    print(f"[*] Timeout       : {args.timeout}s")
    print()

    # Determine subnets to scan
    if args.subnet:
        subnets = [{"interface": "manual", "ip": args.subnet.split("/")[0], "prefix_len": int(args.subnet.split("/")[1])}]
    else:
        subnets = get_local_interfaces()

    if not subnets:
        print("[!] No usable network interfaces found. Use --subnet to specify one.")
        sys.exit(1)

    for iface in subnets:
        ip = iface["ip"]
        prefix_len = int(iface["prefix_len"])
        network = ipaddress.IPv4Network(f"{ip}/{prefix_len}", strict=False)

        if prefix_len < 16:
            print(f"[!] Skipping {network} on {iface['interface']} — subnet too large (/{prefix_len})")
            continue

        print(f"[*] Interface: {iface['interface']}  |  {ip}/{prefix_len}  |  {network.num_addresses - 2} hosts")

        # Host discovery
        if args.no_ping:
            print("[*] Skipping ping, scanning all hosts...")
            live_ips = [str(h) for h in network.hosts()]
        else:
            print("[*] Discovering live hosts via ping...")
            live_ips = discover_hosts(network, args.timeout, args.ping_workers)
            print(f"[*] {len(live_ips)} host(s) alive")

        if not live_ips:
            print("    (none reachable)\n")
            continue

        # Port scan each live host
        print("[*] Scanning ports...\n")
        for ip_str in live_ips:
            host = Host(ip=ip_str)
            host.hostname = resolve_hostname(ip_str)
            host.open_ports = scan_ports(ip_str, ports, args.timeout, args.port_workers)
            print_host_result(host)

        print()

    print("\n[*] Scan complete.")


if __name__ == "__main__":
    main()
