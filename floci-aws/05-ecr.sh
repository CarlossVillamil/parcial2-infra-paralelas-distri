#!/usr/bin/env bash
# 6.5 Punto Extra 3: publicar la imagen de la API en el ECR de Floci y desplegarla
# en el EKS de Floci, documentando los problemas de DNS y de HTTP/HTTPS.
#
# Floci ya inyecta en el k3s un /etc/rancher/k3s/registries.yaml que resuelve ambos
# problemas. Para EVIDENCIARLOS, el script los reproduce y luego restaura la solucion:
#   A) sin mirror      -> "localhost" dentro del k3s es el propio k3s  (problema de DNS)
#   B) mirror por HTTPS -> el registry de Floci solo habla HTTP        (problema HTTP/HTTPS)
#   C) mirror de Floci por HTTP a su IP en floci-net                   (solucion)
# Reinicia SOLO el contenedor k3s de Floci (no Docker, no Minikube).
# Uso (desde la raiz del repo):  bash floci-aws/05-ecr.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
source "$DIR/env.sh"
REPO_NAME=parcial2-api
TAG=1.0
K3S=floci-aws-eks-parcial2-eks
REG_IN=/etc/rancher/k3s/registries.yaml
REG_FLOCI="$HOME/.floci/registries.yaml.floci"   # copia del archivo original de Floci
WORK="$HOME/.floci/ecr-demo"
mkdir -p "$WORK"

[ -f "$REPO/api/Dockerfile" ] || { echo "No existe api/Dockerfile (haz git pull)" >&2; exit 1; }
docker ps --format '{{.Names}}' | grep -qx "$K3S" || { echo "No esta corriendo $K3S (corre 04-eks.sh)" >&2; exit 1; }

# ---------------------------------------------------------------- IAM
paso "Politica de excepcion parcial2-ecr-auth (ecr:GetAuthorizationToken solo admite Resource \"*\")"
usar_admin
AUTH_ARN="arn:aws:iam::$FLOCI_ACCOUNT:policy/parcial2-ecr-auth"
aws iam get-policy --policy-arn "$AUTH_ARN" >/dev/null 2>&1 \
  || aws iam create-policy --policy-name parcial2-ecr-auth \
       --policy-document "file://$DIR/iam-policy-ecr-auth.json" >/dev/null
aws iam attach-user-policy --user-name parcial2-operator --policy-arn "$AUTH_ARN"
cat "$DIR/iam-policy-ecr-auth.json"
aws iam list-attached-user-policies --user-name parcial2-operator --output table

usar_operador
export KUBECONFIG="$EKS_KUBECONFIG"

# ---------------------------------------------------------------- ECR
paso "CAPTURA 12: repositorio parcial2-api en el ECR emulado"
aws ecr describe-repositories --repository-names "$REPO_NAME" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$REPO_NAME" >/dev/null
REPO_URI=$(aws ecr describe-repositories --repository-names "$REPO_NAME" \
  --query 'repositories[0].repositoryUri' --output text)
REGISTRY=${REPO_URI%%/*}
IMAGE="$REPO_URI:$TAG"
aws ecr describe-repositories --repository-names "$REPO_NAME" \
  --query 'repositories[0].{Nombre:repositoryName,URI:repositoryUri,ARN:repositoryArn}' --output table

paso "Prueba negativa: el operador no puede crear otros repositorios"
if aws ecr create-repository --repository-name otro-repo-no-autorizado 2>&1; then
  echo ">>> PERMITIDO: Floci no aplico la politica"
else
  echo ">>> DENEGADO: solo puede usar el repositorio parcial2-api"
fi

paso "Construyendo la imagen de la API (api/Dockerfile) en el Docker de la EC2"
docker build -t "parcial2-api:$TAG" "$REPO/api"

paso "CAPTURA 13: docker login, tag y push al ECR de Floci"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"
docker tag "parcial2-api:$TAG" "$IMAGE"
docker push "$IMAGE"
aws ecr describe-images --repository-name "$REPO_NAME" \
  --query 'imageDetails[].{Tags:join(`,`,imageTags),Bytes:imageSizeInBytes,Subida:imagePushedAt}' --output table

# ---------------------------------------------------------------- helpers EKS
if [ ! -f "$REG_FLOCI" ]; then
  docker cp "$K3S:$REG_IN" "$REG_FLOCI"
  echo "Copia del registries.yaml original de Floci: $REG_FLOCI"
fi

reiniciar_k3s() {
  echo "Reiniciando solo el contenedor $K3S para que containerd relea $REG_IN ..."
  docker restart "$K3S" >/dev/null
  for _ in $(seq 1 40); do
    kubectl get nodes 2>/dev/null | grep -q ' Ready' && { echo "Nodo Ready"; return; }
    sleep 5
  done
  echo "El nodo no volvio a Ready a tiempo" >&2; exit 1
}

desplegar() {   # $1 = nombre del Pod
  kubectl delete pod "$1" --ignore-not-found --wait=true >/dev/null
  kubectl run "$1" --image="$IMAGE" --image-pull-policy=Always --port=8080 --restart=Never
}

mostrar_fallo() {   # $1 = nombre del Pod; espera ErrImagePull/ImagePullBackOff
  local r=""
  for _ in $(seq 1 36); do
    r=$(kubectl get pod "$1" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
    case "$r" in ErrImagePull|ImagePullBackOff) break ;; esac
    sleep 5
  done
  kubectl get pod "$1" -o wide
  echo "--- kubectl describe pod $1 (eventos) ---"
  kubectl describe pod "$1" | sed -n '/^Events:/,$p' | grep -E 'Failed|Pulling|BackOff' | tail -4 || true
  echo "--- containerd del k3s (ultimos errores de pull) ---"
  if docker cp "$K3S:/var/lib/rancher/k3s/agent/containerd/containerd.log" "$WORK/containerd.log" 2>/dev/null; then
    grep -iE 'HTTP response to HTTPS|connection refused|failed to resolve' "$WORK/containerd.log" \
      | tail -2 | cut -c1-400 || true
  else
    echo "(no se pudo leer containerd.log)"
  fi
}

# ---------------------------------------------------------------- A) sin mirror
paso "CAPTURA 14: PROBLEMA DNS -> k3s SIN mirror (la URI apunta a localhost)"
echo "Imagen: $IMAGE"
printf 'mirrors: {}\n' > "$WORK/registries-sin-mirror.yaml"
docker cp "$WORK/registries-sin-mirror.yaml" "$K3S:$REG_IN"
reiniciar_k3s
desplegar api-sin-mirror
mostrar_fallo api-sin-mirror

# ---------------------------------------------------------------- B) mirror https
paso "CAPTURA 15: PROBLEMA HTTP/HTTPS -> mirror a la IP de Floci pero por HTTPS"
sed 's#"http://#"https://#g; s#- http://#- https://#g' "$REG_FLOCI" > "$WORK/registries-https.yaml"
grep -m1 -A2 'localhost:4566' "$WORK/registries-https.yaml" || head -6 "$WORK/registries-https.yaml"
docker cp "$WORK/registries-https.yaml" "$K3S:$REG_IN"
reiniciar_k3s
desplegar api-https
mostrar_fallo api-https

# ---------------------------------------------------------------- C) solucion
paso "CAPTURA 16: SOLUCION -> mirror de Floci por HTTP a su IP en floci-net"
grep -m1 -A2 'localhost:4566' "$REG_FLOCI" || head -6 "$REG_FLOCI"
docker cp "$REG_FLOCI" "$K3S:$REG_IN"
reiniciar_k3s
kubectl delete pod api-sin-mirror api-https --ignore-not-found >/dev/null
desplegar api-ecr
kubectl wait --for=condition=Ready pod/api-ecr --timeout=300s
kubectl get pods -o wide
echo "Imagen del Pod: $(kubectl get pod api-ecr -o jsonpath='{.spec.containers[0].image}')"
kubectl describe pod api-ecr | sed -n '/^Events:/,$p' | grep -E 'Pulled|Started' | tail -2 || true

paso "CAPTURA 17: la API descargada del ECR responde dentro del EKS emulado"
kubectl port-forward pod/api-ecr 18080:8080 >/dev/null 2>&1 &
PF=$!
sleep 4
curl -s -i http://localhost:18080/health | head -12; echo
kill "$PF" 2>/dev/null || true

paso "Listo. kubectl de tu terminal sigue apuntando a: $(KUBECONFIG= kubectl config current-context)"