# Container image for smblds

[![Build OCI image](https://github.com/smblds/smblds-container/actions/workflows/image.yml/badge.svg)](https://github.com/smblds/smblds-container/actions/workflows/image.yml)
[![Docker pulls](https://img.shields.io/docker/pulls/smblds/smblds.svg)](https://hub.docker.com/r/smblds/smblds)
[![OCI image size](https://img.shields.io/docker/image-size/smblds/smblds/latest.svg)](https://hub.docker.com/r/smblds/smblds/tags)
[![CodeFactor Grade](https://img.shields.io/codefactor/grade/github/smblds/smblds-container)](https://www.codefactor.io/repository/github/smblds/smblds-container)

## About

Source files and build instructions for an [OCI](https://opencontainers.org/) image (compatible with e.g. Docker or Podman) to mimic [Active Directory Lightweight Directory Services](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/adam/what-is-active-directory-lightweight-directory-services) (AD LDS) using [Samba](https://www.samba.org/) more or less. AD LDS is an independent mode of Active Directory, minus infrastructure features (such as Kerberos KDC, Group Policies or DNS SRV records), that provides directory services for applications.

This “Samba (Active Directory) Lightweight Directory Services” container image is primarily intended for developers and [CI/CD](https://en.wikipedia.org/wiki/CI/CD) use cases. As such, the [Samba AD DC](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller) configuration has been reduced to a bare minimum of run-time components to enable applications to access an LDAP service that feels and behaves like the one of a Samba AD DC, but without the overhead of a full Active Directory Domain Controller.

## Usage

The OCI image automatically provisions and starts a lightweight Samba AD DC, if a valid configuration has been provided. It may be started with Docker using:

```shell
docker run --name smblds \
           --publish 389:389 \
           --publish 636:636 \
           --detach smblds/smblds:latest
```

And it may be started with Podman using:

```shell
podman run --name smblds \
           --publish 389:389 \
           --publish 636:636 \
           --detach quay.io/smblds/smblds:latest
```

## Volumes

  * `/entrypoint.d` - Optional directory for customization scripts, any executable file is run before the start of the Samba daemon.
  * `/etc/dropbear` - Optional directory containing the SSH host keys for the Dropbear SSH server.
  * `/etc/samba` - Directory where, during the first run, the entrypoint script saves the default configuration file for the Samba daemon.
  * `/root` - Directory where, during the first run, the entrypoint script saves the configuration files for `ldapadd`, `ldapvi`, `ldapmodify`, `ldapsearch` etc. as well as optional SSH authorized keys.
  * `/var/cache/samba` - Directory where the Samba daemon writes its internal semi-persistent/run-time data into.
  * `/var/lib/samba` - Directory where the Samba daemon writes its internal `*.tdb` database files and the LDAP data into.
  * `/var/log/samba` - Directory where, if optionally configured, the Samba daemon writes its log files into.

While the typical developer and CI/CD use cases usually don't require persistent storage, `/entrypoint.d` might be handy for customization scripts that contain e.g. `samba-tool user create`.

## Environment Variables

  * `TZ` - Time zone according to IANA's time zone database, e.g. `Europe/Amsterdam`, defaults to `UTC`.
  * `REALM` - Kerberos realm, the uppercase version of the AD DNS domain, defaults to `SAMDOM.EXAMPLE.COM`.
  * `DOMAIN` - NetBIOS domain name (workgroup), single word up to 15 characters without a dot, defaults to `SAMDOM`.
  * `ADMINPASS` - Domain administrator password, needs to match [complexity requirements](https://technet.microsoft.com/en-us/library/cc786468%28v=ws.10%29.aspx), defaults to `Passw0rd`.
  * `INSECURE_LDAP` - Set to `true` to allow simple LDAP binds over unencrypted connections, defaults to `false`.
  * `INSECURE_PASSWORDSETTINGS` - Set to `true` to disable `ADMINPASS` [complexity requirements](https://technet.microsoft.com/en-us/library/cc786468%28v=ws.10%29.aspx), defaults to `false`.
  * `SSH_AUTHORIZED_KEYS` - SSH public key(s) to enable SSH access to the container, e.g. for complex scenarios.
  * `SERVER_SERVICES` - Override option for the [services](https://wiki.samba.org/index.php/FAQ#Why_Do_I_Not_Have_a_server_services_parameter_in_My_smb.conf_File.3F) that the Samba daemon will run, defaults to `ldap cldap`.

## Exposed Ports

  * `22` - TCP port for optional SSH access to the container, requires `SSH_AUTHORIZED_KEYS` to be set.
  * `389` - TCP port for LDAP access (STARTTLS or plaintext if `INSECURE_LDAP` is enabled).
  * `389/udp` - UDP port for optional [CLDAP](https://wiki.wireshark.org/MS-CLDAP.md) (Connection-less LDAP) access, usually not needed.
  * `636` - TCP port for LDAPS access (mandatory SSL/TLS encryption).
  * `3268` - TCP port for optional LDAP access to [Global Catalog](https://ldapwiki.com/wiki/Global%20Catalog) (STARTTLS or plaintext if `INSECURE_LDAP` is enabled).
  * `3269` - TCP port for optional LDAPS access to [Global Catalog](https://ldapwiki.com/wiki/Global%20Catalog) (mandatory SSL/TLS encryption).

## Pipeline / Workflow

[Docker Hub](https://hub.docker.com/) and [Quay](https://quay.io/) can both [automatically build](https://docs.docker.com/docker-hub/builds/) OCI images from a [linked GitHub account](https://docs.docker.com/docker-hub/builds/link-source/) and automatically push the built image to the respective container repository. However, as of writing, this leads to OCI images for only the `amd64` CPU architecture. To support as many CPU architectures as possible (currently `386`, `amd64`, `arm/v6`, `arm/v7`, `arm64/v8`, `ppc64le` and `s390x`), [GitHub Actions](https://github.com/features/actions) are used. There, the current standard workflow "[Build and push OCI image](.github/workflows/image.yml)" roughly uses first a [GitHub Action to install QEMU static binaries](https://github.com/docker/setup-qemu-action), then a [GitHub Action to set up Docker Buildx](https://github.com/docker/setup-buildx-action) and finally a [GitHub Action to build and push Docker images with Buildx](https://github.com/docker/build-push-action).

Thus the OCI images are effectively built within the GitHub infrastructure (using [free minutes](https://docs.github.com/en/github/setting-up-and-managing-billing-and-payments-on-github/about-billing-for-github-actions) for public repositories) and then only pushed to both container repositories, Docker Hub and Quay (which are also free for public repositories). This not only saves repeated CPU resources but also ensures identical bugs independent from which container repository the OCI image gets finally pulled (and somehow tries to keep it distant from program changes such as [Docker Hub Rate Limiting](https://www.docker.com/increase-rate-limits) in 2020). The authentication for the pushes to the container repositories happen using access tokens, which at Docker Hub need to be bound to a (community) user and at Quay using a robot account as part of the organization. These access tokens are saved as "repository secrets" as part of the settings of the GitHub project.

To avoid maintaining one `Dockerfile` per CPU architecture, the single one is automatically multi-arched using `sed -e 's/^\(FROM\) \(alpine:.*\)/ARG ARCH=\n\1 ${ARCH}\2/' -i Dockerfile` as part of the workflow itself. While this might feel hackish, it practically works very well.

Commits to Git trigger the workflow and lead to updated OCI images being pushed (except for GitHub pull requests) to public container image registries. Additionally, a cron-like option in the workflow leads to a daily updated OCI image.

## License

This project is licensed under the GNU General Public License, version 3 or later - see the [LICENSE](LICENSE) file for details.

As with all OCI images, these also contain other software under other licenses (such as BusyBox, OpenLDAP, Python, Samba etc. from the base distribution, along with any direct or indirect dependencies).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.
