# Docker DEV X11

A script for generate docker container which support X11 and ssh

# Usage

generate Dockerfile and docker-compose.yml

```bash
$ ./generate.sh Dockerfile
```

run

```bash
$ cd ${IMG_DIR}
$ sudo docker-compose up -d
```
if enable ssh support

```bash
$ ssh -p $PORT $USER@localhost
```

script for easy use

```bash
docker-dev-env-${IMAGE_NAME} echo "I am in docker!"
I am in docker!
```

