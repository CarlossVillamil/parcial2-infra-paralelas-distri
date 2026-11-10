#!/usr/bin/env bash
# 6.1 Levanta Floci en la EC2 e instala/configura el AWS CLI.
# Idempotente: si el contenedor ya existe, solo lo arranca. NO reinicia Docker ni toca Minikube.
# Uso (desde la raiz del repo):  bash floci-aws/01-start-floci.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/env.sh"
NET=floci-net

paso "Recursos de la EC2 (Minikube + Floci + k3s comparten esta maquina)"
free -h
df -h /

paso "Docker: version y modo (Floci EKS necesita Docker rootful)"
DOCKER_VER=$(docker version --format '{{.Server.Version}}')
echo "Docker server: $DOCKER_VER"
if docker info 2>/dev/null | grep -qi rootless; then
  echo "ERROR: Docker esta en modo rootless; el k3s de Floci falla (permission denied /var/dmesg)." >&2
  exit 1
fi
echo "Docker rootful: OK"

# Docker >= 29 (almacen containerd) solo usa HTTP plano con localhost/127.0.0.1,
# no con *.localhost, asi que en ese caso el ECR se publica con URIs estilo 'path'.
EXTRA=()
if [ "${DOCKER_VER%%.*}" -ge 29 ]; then
  echo "Docker >= 29: se usara FLOCI_SERVICES_ECR_URI_STYLE=path"
  EXTRA+=(-e FLOCI_SERVICES_ECR_URI_STYLE=path)
fi

paso "Red Docker propia para Floci, su registry ECR y los contenedores k3s"
docker network inspect "$NET" >/dev/null 2>&1 && echo "La red $NET ya existe" || docker network create "$NET"

paso "Contenedor Floci"
if docker ps -a --format '{{.Names}}' | grep -qx floci; then
  echo "El contenedor 'floci' ya existe: solo se asegura que este corriendo."
  docker start floci >/dev/null
else
  # 127.0.0.1: el puerto 4566 solo es accesible desde la propia EC2 (o por tunel SSH).
  # IAM_ENFORCEMENT: sin esto Floci NO evalua las politicas y nunca habria AccessDenied.
  # EKS_MAX_MEMORY_MIB: techo de RAM del contenedor k3s para no ahogar a Minikube.
  docker run -d --name floci --restart unless-stopped \
    --network "$NET" \
    -p 127.0.0.1:4566:4566 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v floci-data:/app/data \
    -e FLOCI_STORAGE_MODE=persistent \
    -e FLOCI_SERVICES_DOCKER_NETWORK="$NET" \
    -e FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED=true \
    -e FLOCI_SERVICES_EKS_MAX_MEMORY_MIB="${EKS_MAX_MEMORY_MIB:-2048}" \
    "${EXTRA[@]}" \
    floci/floci:latest
fi

echo -n "Esperando a que Floci responda"
for _ in $(seq 1 60); do
  if curl -fs http://localhost:4566/_floci/health >/dev/null 2>&1; then echo " OK"; break; fi
  echo -n "."; sleep 1
done
curl -s http://localhost:4566/_floci/health; echo

paso "AWS CLI v2"
if ! command -v aws >/dev/null 2>&1; then
  sudo apt-get install -y unzip >/dev/null
  TMP=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP/awscliv2.zip"
  unzip -q "$TMP/awscliv2.zip" -d "$TMP"
  sudo "$TMP/aws/install"
  rm -rf "$TMP"
fi
aws --version

paso "CAPTURA 1: Floci corriendo"
docker ps --filter name=floci --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

paso "CAPTURA 2: identidad contra Floci (cuenta emulada $FLOCI_ACCOUNT)"
echo "AWS_ENDPOINT_URL=$AWS_ENDPOINT_URL"
aws sts get-caller-identity
