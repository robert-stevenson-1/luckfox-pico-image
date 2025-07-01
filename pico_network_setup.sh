#!/bin/bash

# Luckfox Pico Plus Network Configuration Script
# This script configures USB networking, DNS, and time sync for Alpine Linux
# Run this after flashing to restore network connectivity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

backup_existing_config() {
    log "Backing up existing network configuration..."
    
    if [ -f /etc/network/interfaces ]; then
        cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)
        log "Backup created: /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
        log "Backup created: /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

configure_network_interfaces() {
    log "Configuring network interfaces..."
    
    cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    pre-up ip link set eth0 address ca:0e:f6:67:6e:cb
    udhcpc_opts -t 1
    metric 100

auto usb0
iface usb0 inet dhcp
    metric 200

auto usb0:1
iface usb0:1 inet static
    address 192.168.137.254
    netmask 255.255.255.0
    gateway 192.168.137.1
    post-up ip route add 192.168.137.0/24 via 192.168.137.1 dev usb0 || true
    pre-down ip route del 192.168.137.0/24 via 192.168.137.1 dev usb0 || true

auto usb0:2
iface usb0:2 inet static
    address 10.1.1.1
    netmask 255.255.255.0

# necessary for dnsmasq
auto usb0:3
iface usb0:3 inet static
    address 192.168.160.1
    netmask 255.255.255.0
EOF

    log "Network interfaces configured"
}

configure_dns() {
    log "Configuring DNS..."
    
    # Remove immutable flag if it exists
    chattr -i /etc/resolv.conf 2>/dev/null || true
    
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

    # Make it immutable to prevent overwriting
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    log "DNS configured (Google DNS: 8.8.8.8, Cloudflare DNS: 1.1.1.1, 1.0.0.1)"
}

restart_networking() {
    log "Restarting network services..."
    
    service networking restart || {
        warn "Service restart failed, trying manual interface restart..."
        ifdown usb0 2>/dev/null || true
        ifup usb0 2>/dev/null || true
        ifup usb0:1 2>/dev/null || true
        ifup usb0:2 2>/dev/null || true
        ifup usb0:3 2>/dev/null || true
    }
    
    # Ensure default route is present
    if ! ip route show | grep -q "default"; then
        log "Adding default route..."
        ip route add default via 192.168.137.1 dev usb0 2>/dev/null || true
    fi
}

test_connectivity() {
    log "Testing network connectivity..."
    
    # Test host connectivity (try HTTP first, fallback to ping)
    if curl -s --connect-timeout 3 --max-time 5 http://192.168.137.1 >/dev/null 2>&1; then
        log "✓ Host connection successful (192.168.137.1) via HTTP"
    elif ping -c 2 -W 2 192.168.137.1 >/dev/null 2>&1; then
        log "✓ Host connection successful (192.168.137.1) via ping"
    else
        warn "✗ Cannot reach host at 192.168.137.1"
        return 1
    fi
    
    # Test internet connectivity using HTTP instead of ping
    log "Testing internet connectivity (HTTP-based)..."
    
    # Try multiple reliable HTTP endpoints
    internet_working=false
    
    # Test Cloudflare (usually very reliable)
    if curl -s --connect-timeout 5 --max-time 10 -I http://1.1.1.1 >/dev/null 2>&1; then
        log "✓ Internet connectivity working (Cloudflare)"
        internet_working=true
    # Test Google
    elif curl -s --connect-timeout 5 --max-time 10 -I http://google.com >/dev/null 2>&1; then
        log "✓ Internet connectivity working (Google)"
        internet_working=true
    # Test a different approach - try to connect to a common port
    elif timeout 5 nc -z 8.8.8.8 53 2>/dev/null; then
        log "✓ Internet connectivity working (DNS port check)"
        internet_working=true
    # Fallback to ping if HTTP is blocked but ICMP works
    elif ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log "✓ Internet connectivity working (ping fallback)"
        internet_working=true
    fi
    
    if [ "$internet_working" = false ]; then
        warn "✗ No internet connectivity detected"
        return 1
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log "✓ DNS resolution working"
    elif host google.com >/dev/null 2>&1; then
        log "✓ DNS resolution working (host command)"
    else
        warn "✗ DNS resolution failed"
        return 1
    fi
    
    return 0
}

sync_time() {
    log "Synchronizing time..."
    
    # Get current year to check if time is way off
    current_year=$(date +%Y)
    
    if [ "$current_year" -lt 2020 ]; then
        log "Clock is way off (year: $current_year), getting time via HTTP first..."
        
        # Get time from HTTP headers
        DATE=$(curl -sI http://1.1.1.1 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
        if [ -n "$DATE" ]; then
            date -s "$DATE" 2>/dev/null && log "Time set via HTTP: $(date)"
        else
            warn "Could not get time via HTTP, trying manual approach..."
            date -s "2025-07-01 12:00:00" && log "Time set manually to: $(date)"
        fi
    fi
    
    # Try NTP sync
    if ntpd -n -q -p pool.ntp.org 2>/dev/null; then
        log "✓ Time synchronized via NTP: $(date)"
    elif ntpd -n -q -p 129.6.15.28 2>/dev/null; then  # time.nist.gov
        log "✓ Time synchronized via NIST: $(date)"
    else
        warn "✗ NTP synchronization failed, but time should be approximately correct"
    fi
}

create_time_sync_service() {
    log "Creating persistent time sync service..."
    
    cat > /etc/init.d/timesync << 'EOF'
#!/sbin/openrc-run

description="Time synchronization via HTTP and NTP"

start() {
    ebegin "Synchronizing time"
    
    # Ensure DNS is configured
    if [ ! -s /etc/resolv.conf ] || ! grep -q "nameserver" /etc/resolv.conf; then
        chattr -i /etc/resolv.conf 2>/dev/null || true
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        chattr +i /etc/resolv.conf 2>/dev/null || true
    fi
    
    # Wait for network to be ready (try HTTP first, fallback to ping)
    timeout=30
    network_ready=false
    while [ $timeout -gt 0 ] && [ "$network_ready" = false ]; do
        if curl -s --connect-timeout 2 --max-time 3 http://192.168.137.1 >/dev/null 2>&1; then
            network_ready=true
        elif ping -c 1 -W 1 192.168.137.1 >/dev/null 2>&1; then
            network_ready=true
        else
            sleep 1
            timeout=$((timeout - 1))
        fi
    done
    
    if [ "$network_ready" = false ]; then
        ewarn "Network not ready, skipping time sync"
        return 1
    fi
    
    # Get approximate time via HTTP if clock is way off
    current_year=$(date +%Y)
    if [ "$current_year" -lt 2020 ]; then
        DATE=$(curl -sI http://1.1.1.1 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
        if [ -n "$DATE" ]; then
            date -s "$DATE" 2>/dev/null || true
        fi
    fi
    
    # Try NTP sync
    ntpd -n -q -p pool.ntp.org 2>/dev/null || ntpd -n -q -p 129.6.15.28 2>/dev/null || true
    
    eend $?
}
EOF

    chmod +x /etc/init.d/timesync
    rc-update add timesync default 2>/dev/null || true
    
    log "Time sync service created and enabled"
}

show_status() {
    echo ""
    echo -e "${BLUE}=== Configuration Status ===${NC}"
    echo -e "Current time: ${GREEN}$(date)${NC}"
    echo ""
    echo -e "${BLUE}=== Network Interfaces ===${NC}"
    ip addr show usb0 2>/dev/null || echo "usb0 interface not found"
    echo ""
    echo -e "${BLUE}=== Routing Table ===${NC}"
    ip route show
    echo ""
    echo -e "${BLUE}=== DNS Configuration ===${NC}"
    cat /etc/resolv.conf
    echo ""
}

run_final_tests() {
    log "Running final connectivity tests..."
    
    echo ""
    echo -e "${BLUE}Testing HTTP connectivity:${NC}"
    if curl -I http://1.1.1.1 2>/dev/null | head -1; then
        log "✓ HTTP connectivity working"
    else
        warn "✗ HTTP connectivity failed"
    fi
    
    echo ""
    echo -e "${BLUE}Testing package manager:${NC}"
    if timeout 10 apk update >/dev/null 2>&1; then
        log "✓ Package manager working (apk update successful)"
    else
        warn "✗ Package manager failed (apk update failed)"
    fi
}

main() {
    echo -e "${BLUE}Luckfox Pico Plus Network Configuration Script${NC}"
    echo "This script will configure USB networking, DNS, and time sync"
    echo ""
    
    check_root
    
    # Ask for confirmation
    read -p "Continue with configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled."
        exit 0
    fi
    
    log "Starting network configuration..."
    
    backup_existing_config
    configure_network_interfaces
    configure_dns
    restart_networking
    
    # Wait a moment for network to settle
    sleep 3
    
    if test_connectivity; then
        sync_time
        create_time_sync_service
        run_final_tests
        show_status
        
        echo ""
        log "✓ Configuration completed successfully!"
        echo -e "${GREEN}Your Pico should now have working internet connectivity and time sync.${NC}"
        echo -e "${GREEN}The configuration will persist across reboots.${NC}"
    else
        error "Network connectivity test failed. Please check your host computer's USB sharing setup."
    fi
}

main "$@"