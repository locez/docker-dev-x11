#!/bin/bash
set -e

fetch_profile () {
  grep "^\([^:]*:\)\{2\}$1" "$2"
}

parse_profile () {
  echo "$1" | awk -F':' "{ print \$$2; }"
}

BASE_IMAGE="$1"
USER_PROFILE="$(fetch_profile "${UID}" /etc/passwd)"
USER="$(parse_profile "${USER_PROFILE}" 1)"
GID="$(parse_profile "${USER_PROFILE}" 4)"
HOME="$(parse_profile "${USER_PROFILE}" 6)"
GROUP_PROFILE="$(fetch_profile "${GID}" /etc/group)"
GROUP="$(parse_profile "${USER_PROFILE}" 1)"

help_msg () {
    echo "Usage:"
    echo "$0 Dockerfile"
    exit 0
}

[ -z "$1" ] && help_msg

USER_DOCKERFILE="$1"
SSH_SETUP="echo no ssh support"
read -p "Need ssh support? (y/N) " SSH_SUPPORT
while true; do
  case "$SSH_SUPPORT" in
    [yY])

      read -sp "Enter your passwd for ${USER} ssh:" PASSWD
      echo ""
      SSH_PORT="22"
      read -p "Enter ssh port for listen(defalut: ${SSH_PORT}) :" SSH_PORT
      if [ -z "$SSH_PORT" ];then
        SSH_PORT="22"
      fi

      while true; do
        case "$SSH_PORT" in
          [1-9][0-9]*)
            echo "SSH_PORT: ${SSH_PORT}"
            break;;
          *)
            read -p "$SSH_PORT is an invalid number, put a number: " SSH_PORT
        esac
      done
      SSH_SETUP=$(cat <<- EOF
echo "${USER}:${PASSWD}" | chpasswd && \
command -v sshd && \
sed -i "s/#\{0,1\}Port 22/Port ${SSH_PORT}/g" /etc/ssh/sshd_config || \
(echo "command sshd not found, please install it in your dockerfile: ${USER_DOCKERFILE}" && exit 1)
EOF
)
      break;;
    [nN])
      break;;
    *)
      read -p "$SSH_SUPPORT is an invalid input, put either 'y' or 'n': " SSH_SUPPORT
  esac
done


IMAGE_NAME="docker_dev_x11"
read -p "Enter the image name(default: ${IMAGE_NAME}): " IMAGE_NAME
if [ -z "$IMAGE_NAME" ];then
    IMAGE_NAME="docker_dev_x11"
fi

mkdir -p ${IMAGE_NAME}
DOCKERFILE=${IMAGE_NAME}/Dockerfile
cat "${USER_DOCKERFILE}" > "${DOCKERFILE}"
cat <<EOF >> ${DOCKERFILE}
ENV DISPLAY=${DISPLAY}
RUN mkdir -p ${HOME} && \\
    echo "${USER}:x:${UID}:${GID}::${HOME}:/bin/bash" >> /etc/passwd && \\
    echo "${GROUP}:x:${GID}:" >> /etc/group && \\
    mkdir -p /etc/sudoers.d && \\
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER} && \\
    chmod 0440 /etc/sudoers.d/${USER} && \\
    chown ${UID}:${GID} -R ${HOME} && \\
    echo "export DISPLAY=${DISPLAY}" >> /etc/profile && \\
    command -v sudo && echo "command sudo found" || (echo "command sudo not found, please install it in your dockerfile: ${USER_DOCKERFILE}" && exit 1) && \\
    ${SSH_SETUP}

RUN echo "root:root" | chpasswd   
# setup entrypoint
COPY ./entrypoint.sh /

USER ${USER}
ENV HOME ${HOME}

ENTRYPOINT ["/entrypoint.sh"]
EOF

echo ""
echo "Generated Dockerfile:"
echo "======================"
cat ${DOCKERFILE}
echo "======================"

ENTRYPOINT=${IMAGE_NAME}/entrypoint.sh


echo "#!/usr/bin/env bash" > ${ENTRYPOINT}
[ -z "${SSH_SETUP}" ] || echo "sudo /etc/init.d/ssh start" >> ${ENTRYPOINT}

echo "sudo touch /var/run/tail.pid" >> ${ENTRYPOINT}
echo "sudo tail -f /var/run/tail.pid" >> ${ENTRYPOINT}
chmod +x ${ENTRYPOINT}

COMPOSEFILE=${IMAGE_NAME}/docker-compose.yml

read -p "Enter your workspace path:" WORKSPACE

cat << EOF > ${COMPOSEFILE}
version: "3"
services:
  ros_dev:
    build:
      context: .
      dockerfile: Dockerfile
    image: docker_dev_env_${IMAGE_NAME}:latest
    volumes:
      - "/home/${USER}/.Xauthority:/home/${USER}/.Xauthority"
      - "/tmp/.X11-unix/:/tmp/.X11-unix/"
      - "/dev/snd:/dev/snd"
      - "/dev/shm:/dev/shm"
      - "/etc/machine-id:/etc/machine-id"
      - "/var/lib/dbus:/var/lib/dbus"
      - "${WORKSPACE}:${WORKSPACE}"
    extra_hosts:
      - "${HOSTNAME}:127.0.0.1"
    network_mode: "host"
    privileged: true
EOF

echo ""
echo "Generated docker-compose.yml:"
echo "======================"
cat ${COMPOSEFILE}
echo "======================"


read -p "Build image now? (y/N) " answer
while true; do
  case "$answer" in
    [yY])
      echo "Now building the image..."
      sudo docker-compose -f "$COMPOSEFILE" build 
      break;;
    [nN])
      break;;
    *)
      read -p "$answer is an invalid input, put either 'y' or 'n': " answer
  esac
done

SCRIPT_NAME=docker-dev-env-${IMAGE_NAME}
SCRIPT_NAME=$(echo ${SCRIPT_NAME} |tr '_' '\-')

read -p "Generate ${SCRIPT_NAME} script? (y/N) " answer
while true; do
  case "$answer" in
    [yY])
      echo "install to ${HOME}/.local/bin/..."
      INSTALL_PATH=${HOME}/.local/bin/
      mkdir -p ${INSTALL_PATH}
      cat << EOF > ${INSTALL_PATH}/${SCRIPT_NAME}
#!/usr/bin/env bash
CID=\$(docker ps | grep docker_dev_env_${IMAGE_NAME} |cut -d ' ' -f1)
docker exec -it --user \$USER \$CID bash -c "export QT_X11_NO_MITSHM=1; \$*"
EOF
      chmod +x ${INSTALL_PATH}/${SCRIPT_NAME}      
      break;;
    [nN])
      break;;
    *)
      read -p "$answer is an invalid input, put either 'y' or 'n': " answer
  esac
done

