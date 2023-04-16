# VPN

Means router with VPN. I chosed `TP-LINK Archer C6` which has posibility to use OpenVPN.

My final network

Connect Box(Bridge mode) -> Archer router -> netis router

netis router - used to connect raspberries with network - connected via wifi with archer, working in router mode:

Setup VPN in Archer: VPN Server -> Open VPN:

<img width="575" alt="Screenshot 2021-08-05 at 18 19 32" src="https://user-images.githubusercontent.com/2962338/128385220-892de34c-a837-43de-8b26-d50704c7924a.png">

generate key, and export it. From now I can use this key in https://openvpn.net/vpn-client/
