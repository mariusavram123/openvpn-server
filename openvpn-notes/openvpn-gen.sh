#!/bin/bash -x
#Openvpn config generator script
option=$1
type=$2
client=$3

# Script usage menu
show_usage () {
cat <<-EOF
OpenVPN config generator.
Usage:  `basename $0` -s | --server [server_name] - Generate OpenVPN server configuration files
        `basename $0` -c | --client [client_name] - Generate OpenVPN client configuration files
        `basename $0` -i | --install - Verify and install OpenVPN and easy-rsa packages needed to build the files
        `basename $0` -f | --full [server_name] [client_name] - Generate openvpn configuration for server and 1 client
        `basename $0` -h | --help - Show this help menu and exit
EOF
}

#Set the number of arguments depending of the option

case Z${option} in
    Z-s|Z--server|Z-c|Z--client)
        if [ $# != 2 ]; then
            echo "Only 2 arguments allowed with server or client option."
            show_usage
            exit 1
        fi
    ;;
    Z-i|Z--install)
        if [ $# != 1 ]; then
            echo "No argument needed with -i| --install option."
            show_usage
            exit 1
        fi
    ;;
    Z-f|Z--full)
        if [ $# != 3 ]; then
            echo "Expected exactly 3 arguments for the full option."
            show_usage
            exit 1
        fi
    ;;
    Z-h|Z--help)
        if [ $# != 1 ]; then
            echo "Only one argument expected for the help option."
            show_usage
            exit 1
        fi
    ;;
    X*)
        echo "Unknown usage."
        show_usage
        exit 1
    esac

# installing openvpn packages
install_ovpn () {
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
gen_vars () {
    echo "Making sure OpenVPN is installed"
    install_ovpn
    dir="/etc/openvpn/easy-rsa"
    if [ ! -d ${dir} ]; then
        mkdir -p ${dir}
    fi
    #Copy easyrsa files
    cp -f /usr/share/easy-rsa/3/easyrsa ${dir}
    cp -rf /usr/share/easy-rsa/3/x509-types/ ${dir}
    cp -rf /usr/share/easy-rsa/3/openssl-easyrsa.cnf ${dir}
#do not indent these lines
cat <<-EOF >> ${dir}/vars
set_var EASYRSA \"\$PWD\"
set_var EASYRSA_PKI \"\$EASYRSA/pki\"
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
set_var EASYRSA_EXT_DIR \"\$EASYRSA/x509-types\"
set_var EASYRSA_SSL_CONF \"\$EASYRSA/openssl-easyrsa.cnf\"
set_var EASYRSA_DIGEST "sha256"
EOF
}

# create server configuration
server_config () {
server_dir="/etc/openvpn/server/"
if [ -z ${server} ]; then
    echo "Server variable is empty."
    exit 1
fi
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

# initializing pki variables
initpki () {
    dir="/etc/openvpn/easy-rsa"
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
    openvpn --genkey secret ta.key
}

# easyrsa for server and create config
server_pki () {
    if [ -z ${server} ]; then
        echo "Server variable is empty"
	exit 1
    fi
    if [ ! -d ${dir}/pki ]; then
        initpki
    else
        echo "PKI variables already initialized"
    fi
    echo "Generating server certs"
    if [ -z ${server} ]; then
        echo "Unknown server name."
    fi
    #dir="/etc/openvpn/easy-rsa"
    cd ${dir}
    ./easyrsa gen-req ${server} nopass
    ./easyrsa sign-req server ${server}
    #copy certificates and keys to server directory
    server_dir="/etc/openvpn/server/"
    cp ${dir}/pki/ca.crt ${server_dir}
    cp ${dir}/pki/dh.pem ${server_dir}
    cp ${dir}/pki/private/${server}.key ${server_dir}
    cp ${dir}/pki/issued/${server}.crt ${server_dir}
    cp ${dir}/ta.key ${server_dir}
    if [ ! -f ${server_dir}/${server}.conf ]; then
        echo "Generating server configuration"
        server_config
    else
        echo "A openvpn server configuration with the same name already exists. Nothing to do."
        exit 1
    fi
}

# easyrsa for client and create config
client_config () {
if [ -z ${client} ]; then
    echo "Client variable is empty."
    exit 1
fi
# do not indent these lines
client_dir="/etc/openvpn/client"
cat <<-EOF > ${client_dir}/${client}.conf
client
dev tun0
proto udp
remote 10.85.0.24 5197
ca ca.crt
cert ${client_dir}/${client}.crt
key ${client_dir}/${client}.key
cipher AES-256-CBC
auth SHA512
auth-nocache
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
resolv-retry infinite
tls-auth ${client_dir}/ta.key 1
;compress lz4
nobind
persist-key
persist-tun
log /var/log/openvpn-client1.log
log-append /var/log/openvpn-client2.log
mute-replay-warnings
verb 3
EOF
}

# pki for client
client_pki () {
    if [ -z ${client} ]; then
	echo "Client variable is empty."
	exit 1
    fi
    echo "Generating client certs for ${client}"
    dir="/etc/openvpn/easy-rsa"
    cd ${dir}
    client_dir="/etc/openvpn/client/"
    ./easyrsa gen-req ${client} nopass
    ./easyrsa sign-req client ${client}
    cp pki/ca.crt ${client_dir}
    cp pki/issued/${client}.crt ${client_dir}
    cp pki/private/${client}.key ${client_dir}
    cp ta.key ${client_dir}
    if [ ! -f ${client_dir}/${client}.conf ]; then
        echo "Generating client configuration for ${client}"
        client_config
    else
        echo "A client configration for ${client} already exists. Nothing to do."
        exit 1
    fi
}

# create server tarball for configurations
server_tarball () {
    echo "Creating server tarball for ${server}"
    cd ${server_dir}
    tar zcvf ${server}.tar.gz ca.crt dh.pem ta.key ${server}.crt ${server}.key ${server}.conf
    if [ $? -eq 0 ]; then
        echo "Tarball created for server ${server}. You can find it in ${server_dir}."
    fi
}

# create client tarball for configurations
client_tarball () {
    echo "Creating client tarball for ${client}"
    client_dir="/etc/openvpn/client"
    cd ${client_dir}
    tar zcvf ${client}.tar.gz ca.crt ta.key ${client}.crt ${client}.key ${client}.conf
    if [ $? -eq 0 ]; then
        echo "Tarball created for client ${client}. You can find it in ${client_dir}."
    fi
}

# usage of the script - main function that calls all other small functions
script_usage () {
    case Z${option} in
        Z-h|Z--help)
            if [ -z ${type} ] && [ -z ${client} ]; then
                show_usage
                exit 0
            elif [ -n ${type} ]; then
                echo "Cannot accept config generation for server or client with the help command"
                show_usage
                exit 1
            elif [ -n ${client} ]; then
                echo "The third parameter should be empty with the help command"
                show_usage
                exit 1
            fi
        ;;
        Z-i|Z--install)
            install_ovpn
            exit 0
        ;;
        Z-s|Z--server)
            case ${type} in
            '')
                echo "Server cannot be empty"
                show_usage
                exit 1
            ;;
            *)
                echo "Started server config creation for ${type}"
                server=${type}
                install_ovpn
                gen_vars
                #initpki
                server_pki
                # server_pki calls server_config function
                server_tarball
            ;;
            esac
        ;;
        Z-c|Z--client)
            case ${type} in
            '')
                echo "Client name cannot be empty"
                show_usage
                exit 1
            ;;
            *)
                echo "Starting client configuration for ${type}"
                client=${type}
                install_ovpn
                client_pki
                client_tarball
            ;;
            esac
        ;;
        Z-a|Z--all)
            case ${type} in
            '')
                echo "Server cannot be empty"
                show_usage
                exit 1
            ;;
            *)
                if [ ${client} != "" ]; then
                    server=${type}
                    install_ovpn
                    gen_vars
                    #initpki
                    server_pki
                    client_pki
                    server_tarball
                    client_tarball
                fi
            esac
        ;;
	Z*)
	   echo "Unknown option."
	   show_usage
	   exit 0
	;;
    esac
}

# call the script_usage function according to the help menu
script_usage
