#!/bin/sh
#
# Copyright (c) 2022-2023  Robert Scheck <robert@fedoraproject.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

set -e
[ -n "${DEBUG}" ] && set -x

REALM="${REALM:-SAMDOM.EXAMPLE.COM}"
DOMAIN="${DOMAIN:-SAMDOM}"
ADMINPASS="${ADMINPASS:-Passw0rd}"
INSECURE_LDAP="${INSECURE_LDAP:-false}"
INSECURE_PASSWORDSETTINGS="${INSECURE_PASSWORDSETTINGS:-false}"
SERVER_SERVICES="${SERVER_SERVICES:-ldap cldap}"
BASEDN="$(echo "${REALM}" | tr 'A-Z' 'a-z')"
BASEDN="DC=${BASEDN//./,DC=}"

# Catch container interruption signals to remove hint file for health script
cleanup() {
  rm -f /tmp/samba.daemon-expected
}
trap cleanup INT TERM

# Provision default Samba AD non-interactively
if [ ! -f /etc/samba/smb.conf ]; then
  samba-tool domain provision \
    --realm="$(echo "${REALM}" | tr 'a-z' 'A-Z')" \
    --domain="$(echo "${DOMAIN}" | tr 'a-z' 'A-Z')" \
    --adminpass="${ADMINPASS}"

  # Disable all unused server services
  sed -e '/^\[global\]/a\\tserver services = '"${SERVER_SERVICES}" -i /etc/samba/smb.conf

  # Disable NetBIOS and printing support
  sed -e '/^\[global\]/a\\tdisable netbios = yes\n\tload printers = no' -i /etc/samba/smb.conf
fi

# Disable mandatory LDAP encryption (if requested)
case "${INSECURE_LDAP}" in
  1|y*|Y*|t*|T*)
    sed -e '/^\[global\]/a\\tldap server require strong auth = no' -i /etc/samba/smb.conf
    ;;
esac

# Weaken Samba password settings (if requested)
case "${INSECURE_PASSWORDSETTINGS}" in
  1|y*|Y*|t*|T*)
    samba-tool domain passwordsettings set \
      --complexity=off \
      --min-pwd-length=0 \
      --min-pwd-age=0 \
      --max-pwd-age=0
    ;;
esac

# Write default OpenLDAP client configuration
if [ ! -f /root/.ldaprc ]; then
  cat > /root/.ldaprc <<EOF
URI ldaps://localhost
TLS_REQCERT never
VERSION 3
BASE ${BASEDN}
BINDDN CN=Administrator,CN=Users,${BASEDN}
EOF
  chmod 600 /root/.ldaprc
fi

# Write password of Samba 'Administrator' user
if [ ! -f /root/.ldappass ]; then
  echo -n "${ADMINPASS}" > /root/.ldappass
  chmod 600 /root/.ldappass
fi

# Write default ldapvi configuration
if [ ! -f /root/.ldapvirc ]; then
  cat > /root/.ldapvirc <<EOF
profile default
host: ldaps://localhost
user: CN=Administrator,CN=Users,${BASEDN}
password: ${ADMINPASS}
base: ${BASEDN}
tls: never
EOF
  chmod 600 /root/.ldapvirc
fi

# Write authorized_keys, then start Dropbear SSH
if [ -n "${SSH_AUTHORIZED_KEYS}" ]; then
  mkdir -p /root/.ssh/
  chmod 700 /root/.ssh/
  echo -e "${SSH_AUTHORIZED_KEYS}" >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  pidof dropbear > /dev/null || dropbear -R
fi

# Run optional entrypoint scripts
for entrypoint in /entrypoint.d/*; do
  if [ -e "${entrypoint}" ]; then
    if [ -x "${entrypoint}" ]; then
      echo "Launching ${entrypoint}"
      "${entrypoint}"
    else
      echo "Ignoring ${entrypoint}, not executable"
    fi
  fi
done

# Start Samba (either as main or forking process)
if [ $# -eq 0 ]; then
  pidof samba > /dev/null || { touch /tmp/samba.daemon-expected && exec samba --interactive; }
else
  pidof samba > /dev/null || { touch /tmp/samba.daemon-expected && samba; }
fi

# Default to run whatever the user wanted, e.g. "sh"
exec "$@"
