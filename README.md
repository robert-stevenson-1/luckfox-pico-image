# luckfox-pico

Linux systems for LuckFox Pico series, including
Pico Mini b, Pico Plus and Pico Pro Max (all models with SPI flash).

Currently only [Alpine Linux](https://alpinelinux.org/) is available.

## Downloads

Check out
[Github Actions Artifacts](https://github.com/soyflourbread/luckfox-pico/actions/workflows/main.yml)
for latest Alpine Linux images.

## Flashing

See
[the official docs](https://wiki.luckfox.com/Luckfox-Pico/Linux-MacOS-Burn-Image)
for instructions on flashing `pico-mini-b-sysupgrade.img` to your Pico board.

For example, to flash Pico Pro Max boards,
connect the board to your computer while pressing _BOOT_ key, then execute
```bash
sudo ./upgrade_tool uf pico-mini-b-sysupgrade.img
```

## Setting Up

The default username/password is `root:luckfox`.

UART serial debug port is enabled,
and `sshd` server is installed and enabled as well.

To connect to it via ethernet, simply do
```bash
ssh root@<ip_of_pico_board>
```

### RNDIS/Ethernet-over-USB

This system image has RNDIS enabled for all boards.
To connect to your Pico through RNDIS,
check out [the official guide](https://wiki.luckfox.com/Luckfox-Pico/SSH-Telnet-Login/).

The board's static IP is `10.1.1.1`.

Below is a brief guide to connect via RNDIS on Linux:
```bash
ip link # obtain network device name of pico
sudo ip addr add 10.1.1.10/24 dev <network_device_of_pico>
ping 10.1.1.1 # it works!
```

## Customization

Just fork this repo and trigger Github Actions after you made your changes!

For example,
* To add software packages, edit `bootstrap.sh`.
* To change files in the system image, edit `overlay/`.

## apk issues (SSL Certificate)

### Issue

APK package downloads fail with SSL certificate verification errors:

```text
34CFF7A6:error:0A000086:SSL routines:tls_post_process_server_certificate:certificate verify failed
ERROR: [package]: Permission denied
```

### Cause

* Incorrect system time/date (most common)
* Missing or outdated CA certificates

### Fix

update time:

```bash
ntpd -n -q -p pool.ntp.org
```

Switch to HTTP repositories temporarily:

```bash
echo "http://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /etc/apk/repositories
echo "http://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories
apk update
```

Update CA certificates:

```bash
apk add ca-certificates ca-certificates-bundle
update-ca-certificates
```

Switch back to HTTPS:

```bash
echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /etc/apk/repositories
echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories
apk update
```

## Network Routing Issues (Multiple Interface Conflicts)

### Issue

Luckfox Pico Plus has no internet despite working network interfaces:

```text
# Individual interfaces work
ping -I eth0 8.8.8.8     # works (ethernet has internet)
ping -I usb0 8.8.8.8     # fails (USB host doesn't share internet)

# Default routing fails
ping 8.8.8.8             # fails (wrong route chosen)
apk update               # fails due to routing
```

### Cause

* Multiple DHCP interfaces create conflicting default routes
* USB interface gets lower metric (higher priority) than ethernet
* Static gateway on usb0:1 overrides metric configuration

### Fix

Edit network configuration:

```bash
vi /etc/network/interfaces
```
or 
```bash
nano /etc/network/interfaces
```

Set route metrics to prioritize ethernet:

```bash
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
    post-up ip route add 192.168.137.0/24 via 192.168.137.1 dev usb0 || true
    pre-down ip route del 192.168.137.0/24 via 192.168.137.1 dev usb0 || true
```

Apply changes:

```bash
/etc/init.d/networking restart
```

## USB Host System Configuration (Linux)

### Issue

Cannot SSH to Luckfox Pico Plus over USB connection despite device showing up.

### Cause

* Host system doesn't automatically configure USB gadget network interface
* Missing IP configuration on host side
* No route configured to reach Luckfox IP addresses

### Fix

Check USB gadget interface appears:

```bash
# Look for new network interface (usually usb0, enp0s*, etc.)
ip link show
dmesg | grep -i usb
```

Configure host interface for USB networking:

```bash
# Find the USB network interface name (replace 'usb0' with actual name)
sudo ip addr add 192.168.137.1/24 dev usb0
sudo ip link set usb0 up
```

Test connection:

```bash
# Ping the Luckfox
ping 192.168.137.254

# SSH to Luckfox
ssh root@192.168.137.254
```

Make persistent (Ubuntu/Debian):

```bash
# Add to /etc/network/interfaces
echo "auto usb0" | sudo tee -a /etc/network/interfaces
echo "iface usb0 inet static" | sudo tee -a /etc/network/interfaces
echo "    address 192.168.137.1" | sudo tee -a /etc/network/interfaces
echo "    netmask 255.255.255.0" | sudo tee -a /etc/network/interfaces
```

Optional - Enable internet sharing:

```bash
# Enable IP forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Add NAT rule (replace eth0 with your internet interface)
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i usb0 -o eth0 -j ACCEPT
```