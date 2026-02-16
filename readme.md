

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

### Emplacement du dossier partagé

Dans cette version, le dossier partagé par Samba est `/storage`, mais les
**données chiffrées sur le disque** se trouvent dans `/encrypted`. Côté hôte,
il est recommandé de monter ce répertoire comme suit :

```yaml
volumes:
  - ./samba_encrypted:/encrypted
```

Le répertoire `./samba_encrypted` sur l’hôte contient uniquement des données
chiffrées par `gocryptfs`, même si les clients SMB voient des noms de fichiers
lisibles.

### Nom du partage

Le nom affiché du partage peut être modifié via la variable d’environnement :

```yaml
environment:
  NAME: "Data"
```

### Connexion au dossier partagé

Sur macOS, avec le `compose.yml` fourni (port 1445 mappé vers 445 dans le conteneur),
la connexion depuis le Finder peut se faire avec :

```text
smb://localhost:1445/Data
```

Sous Windows, la connexion peut se faire avec :

```text
\\<ip-hote>\Data
```

> [!NOTE]
> Remplacer `<ip-hote>` par l’adresse IP ou le nom d’hôte de la machine qui exécute Docker.

### Identifiants par défaut

Les identifiants par défaut peuvent être modifiés avec les variables
d’environnement `USER` et `PASS`. Par défaut : utilisateur `samba` et mot de
passe `secret`.

```yaml
environment:
  USER: "samba"
  PASS: "secret"
```

### Permissions (UID / GID, lecture seule)

Les variables `UID` et `GID` permettent de contrôler l’identifiant utilisateur
et groupe utilisés dans le conteneur :

```yaml
environment:
  UID: "1002"
  GID: "1005"
```

Pour forcer le partage en **lecture seule**, la variable suivante peut être
utilisée :

```yaml
environment:
  RW: "false"
```

### Autres réglages Samba

Pour des besoins plus avancés, il est possible de surcharger complètement la
configuration en adaptant le fichier `smb.conf` de ce dépôt, puis en le
montant dans le conteneur :

```yaml
volumes:
  - ./smb.conf:/etc/samba/smb.conf
```

### Configuration multi‑utilisateurs

Pour configurer plusieurs utilisateurs, il est possible de monter le fichier
`users.conf` local dans le conteneur :

```yaml
volumes:
  - ./users.conf:/etc/samba/users.conf
```

Chaque ligne de `users.conf` contient une liste d’attributs séparés par `:`
décrivant l’utilisateur à créer :

`username:UID:groupname:GID:password:homedir`

- `username` : nom de l’utilisateur.
- `UID` : identifiant numérique de l’utilisateur.
- `groupname` : nom du groupe principal.
- `GID` : identifiant numérique du groupe principal.
- `password` : mot de passe en clair (ne peut pas contenir `:`, `\n` ou `\r`).
- `homedir` : (optionnel) répertoire personnel de l’utilisateur.

### Authentification LDAP via variables d’environnement

L’authentification peut être déléguée à un annuaire LDAP sans modifier
manuellement `smb.conf`. Lorsque la variable `LDAP_URL` est définie, le
conteneur génère automatiquement une configuration Samba avec
`passdb backend = ldapsam:...`.

Variables principales à définir (dans `docker compose` ou `docker run`) :

```yaml
environment:
  LDAP_URL: "ldap://ldap.exemple.local"
  LDAP_BASE_DN: "dc=exemple,dc=local"
  LDAP_BIND_DN: "cn=admin,dc=exemple,dc=local"
  LDAP_BIND_PASSWORD: "motDePasseAdmin"
  LDAP_USER_SUFFIX: "ou=people"   # optionnel, valeur par défaut
  LDAP_GROUP_SUFFIX: "ou=groups"  # optionnel, valeur par défaut
```

Avec ces variables, le script d’entrée génère un `smb.conf` équivalent à :

```ini
[global]
        server string = samba
        security = user
        server min protocol = SMB3
        passdb backend = ldapsam:ldap://ldap.exemple.local
        ldap admin dn = cn=admin,dc=exemple,dc=local
        ldap suffix = dc=exemple,dc=local
        ldap user suffix = ou=people
        ldap group suffix = ou=groups

[Data]
        path = /storage
        comment = Shared
        browseable = yes
        writable = yes
        read only = no
        smb encrypt = required
```

Les comptes (utilisateurs / groupes) doivent alors exister dans l’annuaire
LDAP avec le schéma Samba approprié. Dans ce mode, la création d’utilisateurs
locaux via `users.conf` est ignorée, et les authentifications sont gérées par
l’annuaire.
