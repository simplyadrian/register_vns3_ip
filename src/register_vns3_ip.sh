#!/bin/bash -e
#
#
if test "$RS_REBOOT" = "true" -o "$RS_ALREADY_RUN" = "true" ; then
  logger -t RightScale "VPN IP register,  skipped on a reboot."
  exit 0 
fi

# sleep for 2 minutes and 30 seconds to wait for openvpn to fully start
sleep 150

# install perl modules for ubuntu
if [  "$RS_DISTRO" ==  "ubuntu" ]; then
    apt-get install libdigest-hmac-perl
else
# install perl modules for centos
    yum install -y perl-Digest-HMAC
fi

chmod +x $RS_ATTACH_DIR/dns_set.rb && chmod +x $RS_ATTACH_DIR/dnscurl.pl

# This is only temporarily necessary (until some fixes are performed...)
source "/var/spool/ec2/meta-data.sh"

# DNS made easy credentials (used as environment variables by the script)
# $DNS_USER           -- dns credentials: username
# $DNS_PASSWORD  -- dns credentials: password

echo "Configuring DNS for ID: $EXTERNAL_DNS_ID (VPN IP: $vpn_cubed_ipv4 )"

$RS_ATTACH_DIR/dns_set.rb -i "$EXTERNAL_DNS_ID" -u "$DNS_USER" -p "$DNS_PASSWORD"
