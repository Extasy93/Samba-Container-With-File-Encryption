<div align="center">
<a href="https://github.com/dockur/samba"><img src="https://raw.githubusercontent.com/dockur/samba/master/.github/logo.png" title="Logo" style="max-width:100%;" width="256" /></a>
</div>
<div align="center">

[![Build]][build_url]
[![Version]][tag_url]
[![Size]][tag_url]
[![Package]][pkg_url]
[![Pulls]][hub_url]

</div></h1>

Docker container of [Samba](https://www.samba.org/), an implementation of the Windows SMB networking protocol.

## Guide rapide (français) 🇫🇷

### Principe général

- Ce projet démarre un **serveur Samba** dans un conteneur Docker.
- Le partage SMB exposé aux clients (macOS, Windows, Linux) est nommé `Data`.
- Les données sont :
  - **Chiffrées sur le disque** avec `gocryptfs` dans `/encrypted` (monté depuis `./samba_encrypted` sur l’hôte).
  - **Déchiffrées à la volée** dans `/storage`, qui est le répertoire réellement partagé par Samba.
  - **Snapshotées** automatiquement dans `/snapshots` (monté depuis `./snapshots`).

En pratique :
- Côté hôte, `./samba_encrypted` ne contient que des fichiers illisibles (chiffrement).
- Côté réseau (SMB), les clients voient un dossier “normal”.

### Lancer avec Docker Compose

Exemple minimal recommandé :

```yaml
services:
  samba:
    build: .
    image: dockurr/samba
    container_name: samba
    environment:
      NAME: "Data"        # Nom du partage
      USER: "samba"       # Utilisateur Samba par défaut
      PASS: "secret"      # Mot de passe Samba + gocryptfs par défaut
      UID: 1000
      GID: 1000
      RW: true            # true = écriture autorisée, false = lecture seule
      # Optionnel : mot de passe de chiffrement différent
      # GOCRYPTFS_PASSWORD: "monMotDePasseDeChiffrement"
    ports:
      # 1445 sur l’hôte -> 445 dans le conteneur (utile sur macOS)
      - 1445:445
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
      - MKNOD
    volumes:
      # Données chiffrées sur le disque hôte
      - ./samba_encrypted:/encrypted
      # Snapshots (en clair)
      - ./snapshots:/snapshots
    restart: always
```

Commande :

```bash
docker compose up --build -d
```

### Connexion au partage

- **macOS (Finder)**  
  - `Cmd + K` → « Se connecter au serveur… »  
  - URL : `smb://localhost:1445/Data`  
  - Identifiants par défaut :
    - Utilisateur : `samba`
    - Mot de passe : `secret`

- **Windows**  
  - Explorateur → barre d’adresse : `\\<IP_DE_L_HOTE>\Data`

### Utilisateurs (fichier `users.conf`)

Le dépôt contient un `users.conf` d’exemple.  
Chaque ligne suit le format :

```text
username:UID:groupname:GID:password:homedir
```

Exemple simple (`users.conf`) :

```text
#username:UID:groupname:GID:password:homedir
samba:1000:smb:1000:secret
antoine:1001:smb:1000:antoine
```

Il est recommandé de **ne pas publier** de vrais identifiants / mots de passe dans un dépôt public.

### Dossiers importants (côté hôte)

- `./samba_encrypted` : données chiffrées (à garder **en privé**, à exclure du contrôle de version).
- `./snapshots` : snapshots en clair de `/storage` (à garder hors dépôt public).

## Usage  🐳

##### Via Docker Compose (version personnalisée avec snapshots + chiffrement) :

```yaml
services:
  samba:
    # Construit l'image locale modifiée (snapshots + gocryptfs)
    build: .
    image: dockurr/samba
    container_name: samba
    environment:
      NAME: "Data"        # Nom du partage vu par le client
      USER: "samba"       # Utilisateur par défaut (mono‑user)
      PASS: "secret"      # Mot de passe Samba et, par défaut, mot de passe gocryptfs
      UID: 1000           # UID de l'utilisateur Samba
      GID: 1000           # GID du groupe Samba
      RW: true            # Lecture/écriture (mettre "false" pour lecture seule)
      # Optionnel : mot de passe de chiffrement gocryptfs distinct de PASS
      # GOCRYPTFS_PASSWORD: "motDePasseChiffrement"
    ports:
      # Port 1445 sur l’hôte -> 445 dans le conteneur (évite le conflit avec le SMB natif macOS)
      - 1445:445
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
      - MKNOD
    volumes:
      # Données chiffrées (ce qui est stocké physiquement sur le disque)
      - ./samba_encrypted:/encrypted
      # Snapshots (en clair par défaut, créés automatiquement à chaque changement)
      - ./snapshots:/snapshots
    restart: always
```

##### Via Docker CLI (sans `docker compose`) :

```bash
docker build -t samba-snapshot-encrypted .
docker run -d --name samba \
  -p 1445:445 \
  --device /dev/fuse \
  --cap-add SYS_ADMIN --cap-add MKNOD \
  -e NAME=Data \
  -e USER=samba \
  -e PASS=secret \
  -e UID=1000 \
  -e GID=1000 \
  -v "${PWD:-.}/samba_encrypted:/encrypted" \
  -v "${PWD:-.}/snapshots:/snapshots" \
  samba-snapshot-encrypted
```

## Configuration ⚙️

### How do I choose the location of the shared folder?

To change the location of the shared folder, include the following bind mount in your compose file:

In this customized version, the shared folder exposed by Samba is `/storage`, but the
**encrypted data on disk** lives in `/encrypted`. On the host side, you should bind‑mount
`/encrypted`:

```yaml
volumes:
  - ./samba_encrypted:/encrypted
```

The directory `./samba_encrypted` on your host will contain only **chiffres illisibles**
(`gocryptfs`), même si côté client SMB vous voyez des noms de fichiers normaux.

### How do I modify the display name of the shared folder?

You can change the display name of the shared folder by adding the following environment variable:

```yaml
environment:
  NAME: "Data"
```

### How do I connect to the shared folder?

On macOS, with the modified `compose.yml` (port 1445 mapped to 445 in the container),
you can connect from Finder with:

```text
smb://localhost:1445/Data
```

On Windows, you can connect with:

```text
\\<host-ip>\Data
```

> [!NOTE]
> Replace `<host-ip>` with the IP address or hostname of the Docker host.

### How do I modify the default credentials?

You can set the `USER` and `PASS` environment variables to modify the credentials from their default values: user `samba` with password `secret`.

```yaml
environment:
  USER: "samba"
  PASS: "secret"
```

### How do I modify the permissions?

You can set `UID` and `GID` environment variables to change the user and group ID.

```yaml
environment:
  UID: "1002"
  GID: "1005"
```

To mark the share as read-only, add the variable `RW: "false"`.

### How do I modify other settings?

If you need more advanced features, you can completely override the default configuration by modifying the [smb.conf](https://github.com/dockur/samba/blob/master/smb.conf) file in this repo, and binding your custom config to the container like this:

```yaml
volumes:
  - ./smb.conf:/etc/samba/smb.conf
```

### How do I configure multiple users?

If you want to configure multiple users, you can bind the local `users.conf`
file from this repo to the container as follows:

```yaml
volumes:
  - ./users.conf:/etc/samba/users.conf
```

Each line inside that file contains a `:` separated list of attributes describing
the user to be created:

`username:UID:groupname:GID:password:homedir`

where:
- `username` The textual name of the user.
- `UID` The numerical id of the user.
- `groupname` The textual name of the primary user group.
- `GID` The numerical id of the primary user group.
- `password` The clear text password of the user. The password can not contain `:`,`\n` or `\r`.
- `homedir` Optional field for setting the home directory of the user.

## Stars 🌟
[![Stars](https://starchart.cc/dockur/samba.svg?variant=adaptive)](https://starchart.cc/dockur/samba)

[build_url]: https://github.com/dockur/samba/
[hub_url]: https://hub.docker.com/r/dockurr/samba
[tag_url]: https://hub.docker.com/r/dockurr/samba/tags
[pkg_url]: https://github.com/dockur/samba/pkgs/container/samba

[Build]: https://github.com/dockur/samba/actions/workflows/build.yml/badge.svg
[Size]: https://img.shields.io/docker/image-size/dockurr/samba/latest?color=066da5&label=size
[Pulls]: https://img.shields.io/docker/pulls/dockurr/samba.svg?style=flat&label=pulls&logo=docker
[Version]: https://img.shields.io/docker/v/dockurr/samba/latest?arch=amd64&sort=semver&color=066da5
[Package]: https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fipitio.github.io%2Fbackage%2Fdockur%2Fsamba%2Fsamba.json&query=%24.downloads&logo=github&style=flat&color=066da5&label=pulls
