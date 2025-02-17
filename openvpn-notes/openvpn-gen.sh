#!/bin/bash
#Openvpn config generator script
option=$1
type=$2

#Expect exactly 2 arguments
if [ $# > 2 ]; then
    echo "Only 1 or 2 arguments expected."
    echo "Too many arguments. Exiting ..."
    show_usage
    exit 1
fi

show_usage()
{
cat <<-EOF
OpenVPN config generator.
Usage:  `basename $0` -s | --server [server_name] - Generate OpenVPN server configuration files
        `basename $0` -c | --client [client_name] - Generate OpenVPN client configuration files
        `basename $0` -i | --install - Verify and install OpenVPN and easy-rsa packages needed to build the files
        `basename $0` -h | --help - Show this help menu and exit
EOF
}

install_ovpn()
{
    #Verify if epel repo exist
    if [ ! -f /etc/yum.repos.d/epel.repo ]; then
        dnf makecache
        dnf install epel-release -y
    else
        echo "Epel repository is already installed"
    fi
    if [ ! `rpm -qa openvpn` ]; then
        echo "Installng OpenVPN"
        dnf install -y openvpn easy-rsa
    else
        echo "OpenVPN is already installed"
    fi
}

# generate vars file
gen_vars()
{
    echo "Making sure OpenVPN is installed"
    install_ovpn
    dir="/etc/openvpn/easy-rsa/"
    if [ ! -d ${dir} ]; then
        mkdir -p ${dir}
    fi
    #Copy easyrsa files
    cp -f /usr/share/easy-rsa/3/easyrsa ${dir}
    cp -rf /usr/share/easy-rsa/3/x509-types/ ${dir}
    cp -rf /usr/share/easy-rsa/3/openssl-easyrsa.cnf ${dir}
#do not indent these lines
cat <<-EOF >> ${dir}/vars
set_var EASYRSA "$PWD"
set_var EASYRSA_PKI "$EASYRSA/pki"
set_var EASYRSA_DN "cn_only"
set_var EASYRSA_REQ_COUNTRY "RO"
set_var EASYRSA_REQ_PROVINCE "Bucharest"
set_var EASYRSA_REQ_CITY "Bucharest"
set_var EASYRSA_REQ_ORG "OpenVPN CERTIFICATE AUTHORITY"
set_var EASYRSA_REQ_EMAIL "marius@example.com"
set_var EASYRSA_REQ_OU "OpenVPN EASY CA"
set_var EASYRSA_KEY_SIZE 2048
set_var EASYRSA_ALGO rsa
set_var EASYRSA_CA_EXPIRE 7500
set_var EASYRSA_CERT_EXPIRE 3650
set_var EASYRSA_NS_SUPPORT "no"
set_var EASYRSA_NS_COMMENT "OpenVPN CERTIFICATE AUTHORITY"
set_var EASYRSA_EXT_DIR "$EASYRSA/x509-types"
set_var EASYRSA_SSL_CONF "$EASYRSA/openssl-easyrsa.cnf"
set_var EASYRSA_DIGEST "sha256"
EOF
}

server_config()
{
server_dir="/etc/openvpn/server/"
#do not indent these lines
cat <<-EOF > ${server_dir}/${server}.conf
port 5197
proto udp
dev tun0
ca ${server_dir}/ca.crt
cert ${server_dir}/${server}.crt
key ${server_dir}/${server}.key
dh ${server_dir}/dh.pem
server 10.87.0.0 255.255.255.0
;allow-compression yes
;push "redirect-gateway def1 bypass-dhcp"
ifconfig-pool-persist fixed-ips.txt
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
;duplicate-cn
;client-to-client
cipher AES-256-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
auth SHA512
auth-nocache
keepalive 20 60
persist-key
persist-tun
tls-auth /etc/openvpn/server/ta.key 0 # This file is secret
;tls-crypt /etc/openvpn/server/ta.key
#compress lz4
daemon
user openvpn
group openvpn
log /var/log/openvpn-server.log
log-append /var/log/openvpn-server.log
verb 3
explicit-exit-notify 1
EOF
}

initpki()
{
    if [ ! -f ${dir}/vars ]; then
        echo "Generating vars file"
        gen_vars
        echo "Generated vars"
        cat ${dir}/vars
    else
        echo "Vars file already exist."
    fi
    # dir variable refers as easy-rsa
    echo "Initializing pki variables"
    cd ${dir}
    ./easyrsa init-pki
    echo "Building CA certificate for the server"
    ./easyrsa build-ca
    echo "Generating dh parameters"
    ./easyrsa gen-dh
    echo "Generating TLS Auth key"
    openvpn --genkey secret pki/ta.key
}

server_pki()
{
    if [ ! -d ${dir}/pki ]; then
        initpki
    else
        echo "PKI variables already initialized"
    fi
    echo "Generating server certs"
    cd ${dir}
    ./easyrsa gen-req ${server} nopass
    ./easyrsa sign-req server ${server}
    #copy certificates and keys to server directory
    cp ${dir}/pki/ca.crt ${server_dir}
    cp ${dir}/pki/dh.pem ${server_dir}
    cp ${dir}/pki/private/${server}.key ${server_dir}
    cp ${dir}/pki/issued/${server}.crt ${server_dir}
    cp ${dir}/pki/ta.key ${server_dir}
    if [ ! -f ${server_dir}/${server}.conf ]; then
        echo "Generating server configuration"
        server_config
    else
        echo "A openvpn server configuration with the same name already exists. Nothing to do."
        exit 1
    fi
}
