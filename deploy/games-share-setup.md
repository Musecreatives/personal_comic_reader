# Games Samba share setup

Samba share for transferring the game library between the Windows machine
and the server (`/mnt/media-pool/games`), reachable only over Tailscale.

## Path & permissions

`/mnt/media-pool/games` on the `mergerfs` union (writes land mostly on
`/mnt/hdd1tb` since `/mnt/external` is ~87% full and mergerfs uses the `mfs`
policy — expected).

Matches the existing Jellyfin permission pattern:

- Owner `server:media`, mode `2775` (`rwxrwsr-x`, setgid so new files
  inherit the `media` group)
- Default ACLs so subfolders/files keep the same group permissions:

```bash
sudo mkdir -p /mnt/media-pool/games
sudo chown server:media /mnt/media-pool/games
sudo chmod 2775 /mnt/media-pool/games
sudo setfacl -m g:media:rwx /mnt/media-pool/games
sudo setfacl -d -m u::rwx,g::rwx,g:media:rwx,o::r-x /mnt/media-pool/games
```

## Network exposure

Samba (`smbd`) **cannot bind directly to the Tailscale interface** —
`tailscale0` is a point-to-point interface with no broadcast address, and
Samba's interface code hard-rejects non-broadcast interfaces
(`not adding non-broadcast interface tailscale0` in the log). So `smbd`
listens on `0.0.0.0`/`::` as usual, and access is restricted by two layers
instead:

1. **`smb.conf` `hosts allow`/`hosts deny`** — only `127.0.0.1`, `::1`
   (needed because `localhost` resolves to `::1` on this box), and the
   Tailscale CGNAT range `100.64.0.0/10` are allowed; everything else is
   denied at the Samba layer.
2. **`ufw`** — default-deny incoming, with `22/tcp` (SSH) open on all
   interfaces, and `139,445/tcp` opened only on `lo` and `tailscale0`.

```bash
sudo ufw allow OpenSSH
sudo ufw allow in on lo to any port 445,139 proto tcp
sudo ufw allow in on tailscale0 to any port 445,139 proto tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

## Final `/etc/samba/smb.conf`

```ini
[global]
   workgroup = WORKGROUP
   server string = %h server
   security = user
   map to guest = never
   hosts allow = 127.0.0.1 ::1 100.64.0.0/10
   hosts deny = 0.0.0.0/0
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d

[games]
   path = /mnt/media-pool/games
   browseable = yes
   read only = no
   writable = yes
   valid users = server
   create mask = 0664
   directory mask = 2775
   force group = media
```

## Samba user

Linux user `server` (already in the `media` group). Password set once,
interactively:

```bash
sudo smbpasswd -a server
```

## Windows: map the drive

Run in a Windows terminal (prompts for the Samba password rather than
taking it as a plaintext argument):

```
net use G: \\100.108.109.63\games /user:server /persistent:yes
```

Swap `G:` for whichever drive letter is free. `/persistent:yes` reconnects
it automatically on future logins. To remove it later:

```
net use G: /delete
```

## Verification

```bash
smbclient -L localhost -U server
```

Should list the `games` share as type `Disk`. (`smbclient` isn't installed
by default — `sudo apt install -y smbclient`.)
