# kubernetes-raspberry4b
Home cluster based on kubespray with github actions deployment.

## Pre requirements

### Hardware

- [Raspberry pi 4b 8gb](https://www.raspberrypi.org/products/raspberry-pi-4-model-b/)
- SD Card. I used 32gb
- Cooler. I used [this one](https://www.amazon.com/Raspberry-Model-Aluminum-Cooling-Metal/dp/B07VQLBSNC)
- Ethernet connection

### Domain

- forward domain to your public IP (I'll call it example.com).

- add additional configuration to handle subdomains and www:

```
*          IN CNAME  example.com.
www        IN CNAME  example.com.
```

### Network

On my network provider - UPC I have to:

- disable ipv6
- forward port 80, 443, 6443 to raspberrypi ip
- make smaller DHCP range to prevent conflicts in kubernetes

## Installation

- Install on sd card ubuntu 20.04 64bit via https://www.raspberrypi.org/blog/raspberry-pi-imager-imaging-utility/
- Insert sd card to raspberry and connect it to internet


