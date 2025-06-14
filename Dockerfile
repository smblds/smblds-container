#
# Copyright (c) 2022-2025  Robert Scheck <robert@fedoraproject.org>
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

FROM alpine:latest

LABEL maintainer="Robert Scheck <https://github.com/smblds/smblds-container>" \
      description="Samba (Active Directory) Lightweight Directory Services" \
      org.opencontainers.image.title="smblds" \
      org.opencontainers.image.description="Samba (Active Directory) Lightweight Directory Services" \
      org.opencontainers.image.url="https://www.samba.org/" \
      org.opencontainers.image.documentation="https://wiki.samba.org/index.php/User_Documentation" \
      org.opencontainers.image.source="https://gitlab.com/samba-team/samba" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.name="smblds" \
      org.label-schema.description="Samba (Active Directory) Lightweight Directory Services" \
      org.label-schema.url="https://www.samba.org/" \
      org.label-schema.usage="https://wiki.samba.org/index.php/User_Documentation" \
      org.label-schema.vcs-url="https://gitlab.com/samba-team/samba"

COPY entrypoint.sh healthcheck.sh /
RUN set -x && \
  chmod 0755 /entrypoint.sh /healthcheck.sh

RUN set -x && \
  apk --no-cache upgrade && \
  apk --no-cache add samba-dc dropbear ldapvi ldb-tools openldap-clients py3-cryptography py3-setproctitle tini tzdata && \
  rm -f /etc/motd /etc/samba/smb.conf && \
  python_sitepackages="$(python -c 'import site; print(site.getsitepackages()[0])')" && \
  cp -pf "${python_sitepackages}/samba/ntacls.py" "${python_sitepackages}/samba/ntacls.py.orig" && \
  sed -e '/smbd.set_nt_acl(/,/)/d' -i "${python_sitepackages}/samba/ntacls.py" && \
  sed -e '/^\s\{4\}else:$/{N;s/^\s\{4\}else:\n$//}' -i "${python_sitepackages}/samba/ntacls.py" && \
  diff -u "${python_sitepackages}/samba/ntacls.py.orig" "${python_sitepackages}/samba/ntacls.py" || python "${python_sitepackages}/samba/ntacls.py" && \
  rm -f "${python_sitepackages}/samba/ntacls.py.orig" && \
  for bin in ldapadd ldapcompare ldapdelete ldapexop ldapmodify ldapmodrdn ldappasswd ldapsearch ldapvc ldapwhoami; do \
    echo -e '#!/bin/sh\n\nHOME='"'/root'"' exec '"/usr/bin/${bin}"' -x -y /root/.ldappass "$@"' > "/usr/local/bin/${bin}" && \
    chmod 0755 "/usr/local/bin/${bin}"; \
  done && \
  echo -e '#!/bin/sh\n\nHOME='"'/root'"' exec /usr/bin/ldapvi "$@"' > /usr/local/bin/ldapvi && \
  chmod 0755 /usr/local/bin/ldapvi && \
  for bin in ldbadd ldbdel ldbedit ldbmodify ldbrename ldbsearch; do \
    echo -e '#!/bin/sh\n\nLDB_MODULES_PATH='"'/usr/lib/samba/ldb'"' exec '"/usr/bin/${bin}"' "$@"' > "/usr/local/bin/${bin}" && \
    chmod 0755 "/usr/local/bin/${bin}"; \
  done && \
  mkdir /entrypoint.d/ && \
  chmod 0750 /entrypoint.d/

ENV TZ=UTC
VOLUME ["/entrypoint.d/", "/etc/dropbear/", "/etc/samba/", "/root/", "/var/cache/samba/", "/var/lib/samba/", "/var/log/samba/"]
EXPOSE 22 389 389/udp 636 3268 3269

ENTRYPOINT ["/sbin/tini", "-g", "--", "/entrypoint.sh"]
HEALTHCHECK CMD ["/healthcheck.sh"]
