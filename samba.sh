#!/usr/bin/env bash
set -Eeuo pipefail

start_snapshot_watcher() {
    local src="$share"
    local dest="${SNAPSHOT_DIR:-/snapshots}"

    if ! command -v inotifywait >/dev/null 2>&1; then
        echo "inotifywait n'est pas disponible, le snapshot automatique est désactivé."
        return 0
    fi

    mkdir -p "$dest" || { echo "Échec de la création du répertoire de snapshots $dest"; return 1; }

    inotifywait -m -r -e create,modify,move,delete --format '%w%f' "$src" | while read -r file; do
        ts="$(date +%Y%m%d-%H%M%S)"
        snap_dir="$dest/$ts"
        mkdir -p "$snap_dir" || { echo "Échec de la création du snapshot $snap_dir"; continue; }

        rsync -a --delete "$src"/ "$snap_dir"/ >/dev/null 2>&1 || {
            echo "Échec de la synchronisation du snapshot pour l'évènement sur $file"
            continue
        }

        echo "Snapshot créé dans $snap_dir suite à un changement sur $file"
    done &
}

# This function checks for the existence of a specified Samba user and group. If the user does not exist, 
# it creates a new user with the provided username, user ID (UID), group name, group ID (GID), and password. 
# If the user already exists, it updates the user's UID and group association as necessary, 
# and updates the password in the Samba database. The function ensures that the group also exists, 
# creating it if necessary, and modifies the group ID if it differs from the provided value.
add_user() {
    local cfg="$1"
    local username="$2"
    local uid="$3"
    local groupname="$4"
    local gid="$5"
    local password="$6"
    local homedir="$7"

    # Check if the smb group exists, if not, create it
    if ! getent group "$groupname" &>/dev/null; then
        [[ "$groupname" != "smb" ]] && echo "Group $groupname does not exist, creating group..."
        groupadd -o -g "$gid" "$groupname" > /dev/null || { echo "Failed to create group $groupname"; return 1; }
    else
        # Check if the gid right,if not, change it
        local current_gid
        current_gid=$(getent group "$groupname" | cut -d: -f3)
        if [[ "$current_gid" != "$gid" ]]; then
            [[ "$groupname" != "smb" ]] && echo "Group $groupname exists but GID differs, updating GID..."
            groupmod -o -g "$gid" "$groupname" > /dev/null || { echo "Failed to update GID for group $groupname"; return 1; }
        fi
    fi

    # Check if the user already exists, if not, create it
    if ! id "$username" &>/dev/null; then
        [[ "$username" != "$USER" ]] && echo "User $username does not exist, creating user..."
        extra_args=()
        # Check if home directory already exists, if so do not create home during user creation
        if [ -d "$homedir" ]; then
          extra_args=("${extra_args[@]}" -H)
        fi
        adduser "${extra_args[@]}" -S -D -h "$homedir" -s /sbin/nologin -G "$groupname" -u "$uid" -g "Samba User" "$username" || { echo "Failed to create user $username"; return 1; }
    else
        # Check if the uid right,if not, change it
        local current_uid
        current_uid=$(id -u "$username")
        if [[ "$current_uid" != "$uid" ]]; then
            echo "User $username exists but UID differs, updating UID..."
            usermod -o -u "$uid" "$username" > /dev/null || { echo "Failed to update UID for user $username"; return 1; }
        fi

        # Update user's group
        usermod -g "$groupname" "$username" > /dev/null || { echo "Failed to update group for user $username"; return 1; }
    fi

    # Check if the user is a samba user
    pdb_output=$(pdbedit -s "$cfg" -L)  #Do not combine the two commands into one, as this could lead to issues with the execution order and proper passing of variables. 
    if echo "$pdb_output" | grep -q "^$username:"; then
        # skip samba password update if password is * or !
        if [[ "$password" != "*" && "$password" != "!" ]]; then
            # If the user is a samba user, update its password in case it changed
            echo -e "$password\n$password" | smbpasswd -c "$cfg" -s "$username" > /dev/null || { echo "Failed to update Samba password for $username"; return 1; }
        fi
    else
        # If the user is not a samba user, create it and set a password
        echo -e "$password\n$password" | smbpasswd -a -c "$cfg" -s "$username" > /dev/null || { echo "Failed to add Samba user $username"; return 1; }
        [[ "$username" != "$USER" ]] && echo "User $username has been added to Samba and password set."
    fi

    return 0
}

group="smb"
share="/storage"
encrypted="/encrypted"
secret="/run/secrets/pass"
config="/etc/samba/smb.conf"
users="/etc/samba/users.conf"

mkdir -p "$encrypted" || { echo "Failed to create directory $encrypted"; exit 1; }
mkdir -p "$share" || { echo "Failed to create directory $share"; exit 1; }

if [ -z "${GOCRYPTFS_PASSWORD:-}" ]; then
    if [ -n "${PASS:-}" ]; then
        export GOCRYPTFS_PASSWORD="$PASS"
    else
        echo "GOCRYPTFS_PASSWORD or PASS must be set for encrypted storage."
        exit 1
    fi
fi

if [ ! -f "$encrypted/gocryptfs.conf" ]; then
    echo "Initialisation du stockage chiffré gocryptfs dans $encrypted"
    echo "$GOCRYPTFS_PASSWORD" | gocryptfs -q -init -passfile /dev/stdin "$encrypted" || {
        echo "Failed to init gocryptfs repository at $encrypted"
        exit 1
    }
fi

echo "Montage gocryptfs de $encrypted vers $share"
echo "$GOCRYPTFS_PASSWORD" | gocryptfs -q -passfile /dev/stdin \
    -allow_other \
    "$encrypted" "$share" || {
    echo "Failed to mount gocryptfs from $encrypted to $share"
    exit 1
}

# Check if the secret file exists and if its size is greater than zero
if [ -s "$secret" ]; then
    PASS=$(cat "$secret")
fi

if [ -d "$config" ]; then

    echo "The bind $config maps to a file that does not exist!"
    exit 1

fi

if [ -f "$config" ] && [ -s "$config" ]; then

    echo "Using provided configuration file: $config."

else

    config="/etc/samba/smb.tmp"

    if [ -n "${LDAP_URL:-}" ]; then

        cat > "$config" <<EOF
[global]
        server string = samba
        security = user
        server min protocol = SMB3
        passdb backend = ldapsam:${LDAP_URL}
        ldap admin dn = ${LDAP_BIND_DN:-}
        ldap suffix = ${LDAP_BASE_DN:-}
        ldap user suffix = ${LDAP_USER_SUFFIX:-ou=people}
        ldap group suffix = ${LDAP_GROUP_SUFFIX:-ou=groups}

[Data]
        path = /storage
        comment = Shared
        browseable = yes
        writable = yes
        read only = no
        smb encrypt = required
EOF

        if [ -n "${NAME:-}" ] && [[ "${NAME,,}" != "data" ]]; then
            sed -i "s/\[Data\]/\[$NAME\]/" "$config"
        fi

        if [[ "$RW" == [Ff0]* ]]; then
            sed -i "s/^\(\s*\)writable =.*/\1writable = no/" "$config"
            sed -i "s/^\(\s*\)read only =.*/\1read only = yes/" "$config"
        fi

        if [ -n "${LDAP_BIND_PASSWORD:-}" ]; then
            smbpasswd -w "$LDAP_BIND_PASSWORD" || echo "Failed to set LDAP bind password."
        fi

    else

        template="/etc/samba/smb.default"

        if [ ! -f "$template" ]; then
          echo "Your /etc/samba directory does not contain a valid smb.conf file!"
          exit 1
        fi

        rm -f "$config"
        cp "$template" "$config"

        if [ -n "$NAME" ] && [[ "${NAME,,}" != "data" ]]; then
          sed -i "s/\[Data\]/\[$NAME\]/" "$config"
        fi

        sed -i "s/^\(\s*\)force user =.*/\1force user = $USER/" "$config"
        sed -i "s/^\(\s*\)force group =.*/\1force group = $group/" "$config"

        if [[ "$RW" == [Ff0]* ]]; then
            sed -i "s/^\(\s*\)writable =.*/\1writable = no/" "$config"
            sed -i "s/^\(\s*\)read only =.*/\1read only = yes/" "$config"
        fi

    fi

fi

if [ -d "$users" ]; then

    echo "The file $users does not exist, please check that you mapped it to a valid path!"
    exit 1

fi

mkdir -p /var/lib/samba/sysvol
mkdir -p /var/lib/samba/private
mkdir -p /var/lib/samba/bind-dns

if [ -z "${LDAP_URL:-}" ] && [ -f "$users" ] && [ -s "$users" ]; then

    while IFS= read -r line || [[ -n ${line} ]]; do

        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

        IFS=':' read -r username uid groupname gid password homedir <<< "$line"

        if [[ -z "$username" || -z "$uid" || -z "$groupname" || -z "$gid" || -z "$password" ]]; then
            echo "Skipping incomplete line: $line"
            continue
        fi

        [[ -z "$homedir" ]] && homedir="$share"

        add_user "$config" "$username" "$uid" "$groupname" "$gid" "$password" "$homedir" || { echo "Failed to add user $username"; exit 1; }

    done < <(tr -d '\r' < "$users")

elif [ -z "${LDAP_URL:-}" ]; then

    add_user "$config" "$USER" "$UID" "$group" "$GID" "$PASS" "$share" || { echo "Failed to add user $USER"; exit 1; }

    if [[ "$RW" != [Ff0]* ]]; then
        if [ -z "$(ls -A "$share")" ]; then
            chmod 0770 "$share" || { echo "Failed to set permissions for directory $share"; exit 1; }
            chown "$USER:$group" "$share" || { echo "Failed to set ownership for directory $share"; exit 1; }
        fi
    fi

fi

if [[ "$RW" != [Ff0]* ]]; then
    chmod 0770 "$share" || { echo "Failed to set permissions for directory $share"; exit 1; }
    chown "$USER:$group" "$share" || { echo "Failed to set ownership for directory $share"; exit 1; }
fi

ln -sf "$config" /etc/samba.conf

[ -d /run/samba/msg.lock ] && chmod -R 0755 /run/samba/msg.lock
[ -d /var/log/samba/cores ] && chmod -R 0700 /var/log/samba/cores
[ -d /var/cache/samba/msg.lock ] && chmod -R 0755 /var/cache/samba/msg.lock

start_snapshot_watcher || echo "Le watcher de snapshots n'a pas pu être démarré."

if command -v winbindd >/dev/null 2>&1; then
    winbindd || echo "Impossible de démarrer winbindd."
fi

exec smbd --configfile="$config" --foreground --debug-stdout -d "${DEBUG_LEVEL:-1}" --no-process-group
