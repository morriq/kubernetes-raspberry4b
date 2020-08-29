# kubernetes-raspberry4b
Home cluster based on kubespray with github actions deployment.

## Pre requirements

### Hardware

- [Raspberry pi 4b 8gb][https://www.raspberrypi.org/products/raspberry-pi-4-model-b/]
- SD Card. I used 32gb
- Cooler. I used [this one][https://www.amazon.com/Raspberry-Model-Aluminum-Cooling-Metal/dp/B07VQLBSNC]
- Ethernet connection

### Domain

- forward domain to your public IP (I'll call it example.com).

- handle subdomains .

### Network

On my network provider - UPC I have to:

- disable ipv6
- forward port 80, 443, 6443 to my raspberrypi ip
- make smaller DHCP range to prevent conflicts in kubernetes

