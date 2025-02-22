# openvpn-server
Openvpn server notes for Mageia 7 or Almalinux 9

Created a script that should automatically generate the configurations for Almalinux 9

Usage instructions:


Installing openvpn and easyrsa needed for config generation:

```
./openvpn-gen.sh -i 
```
or

```
./openvpn-gen.sh --install 
```


Create the server configurations and initialize all pki for openvpn:

```
./openvpn-gen.sh -s <server_name>
```
or
```
./openvpn-gen.sh --server <server_name>
```
Replace server name with the name you want to give the server.


Create the configurations for a client:

```
./openvpn-gen.sh -c <client_name>
```
or
```
./openvpn-gen.sh --client <client_name>
```
Replace the client name with the name you want to give to the client connecting to the server.
This can also be used to add a client with another name without deleting anything related to existing clients.


Create both server and client configurations:
```
./openvpn-gen.sh -f <server_name> <client_name>
```
or
```
./openvpn-gen.sh --full <server_name> <client_name>
```

More information:
```
./openvpn-gen.sh -h
```
or
```
./openvpn-gen.sh --help
```
