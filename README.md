# auto-create-users
- docker command :
```bash
docker build -t debian-dev . && docker run -ti debian-dev
```

- example of what the sudo script will write to `/etc/sudoers`
```
Host_Alias cdelon_hosts = buroprofs,dpmoc
cdelon cdelon_hosts=(root) NOPASSWD: /usr/bin/rm -r *
```
