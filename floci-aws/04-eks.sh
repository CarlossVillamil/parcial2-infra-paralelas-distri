#!/usr/bin/env bash
# 6.4 EKS demostrativo: create-cluster -> update-kubeconfig -> get nodes -> nginx,
# y la evidencia de que CreateNodegroup solo registra metadatos.
# Usa un kubeconfig APARTE (~/.kube/floci-eks): el contexto de Minikube no se toca.
# Uso:  bash floci-aws/04-eks.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/env.sh"
CLUSTER=parcial2-eks
NODEGROUP=ng-demo
ROLE_ARN="arn:aws:iam::$FLOCI_ACCOUNT:role/eks-role"

paso "Subred por defecto del VPC emulado (consulta con admin)"
usar_admin
SUBNET=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)
if [ -z "$SUBNET" ] || [ "$SUBNET" = "None" ]; then
  echo "AVISO: Floci no devolvio subred por defecto; el cluster se crea sin VPC."
  VPC_CFG='{}'
  SUBNET=""
else
  echo "Subred: $SUBNET"
  VPC_CFG="subnetIds=$SUBNET"
fi

# A partir de aqui todo con el operador (Floci rechaza test/test para kubectl).
usar_operador
export KUBECONFIG="$EKS_KUBECONFIG"
mkdir -p "$(dirname "$KUBECONFIG")"

paso "CAPTURA 7a: aws eks create-cluster"
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  echo "El cluster ya existe"
else
  aws eks create-cluster --name "$CLUSTER" --version 1.31 \
    --role-arn "$ROLE_ARN" --resources-vpc-config "$VPC_CFG"
fi
echo "Esperando estado ACTIVE (descarga la imagen k3s la primera vez, puede tardar)..."
aws eks wait cluster-active --name "$CLUSTER"

paso "CAPTURA 7b: aws eks describe-cluster"
aws eks describe-cluster --name "$CLUSTER" \
  --query 'cluster.{Nombre:name,Estado:status,Version:version,Endpoint:endpoint,Arn:arn,Rol:roleArn}' \
  --output table

paso "CAPTURA 8: el 'cluster' es UN unico contenedor k3s"
docker ps --filter name=eks --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

paso "aws eks update-kubeconfig (archivo separado: $KUBECONFIG)"
aws eks update-kubeconfig --name "$CLUSTER" --alias floci-parcial2-eks

paso "CAPTURA 9: kubectl get nodes"
kubectl get nodes -o wide

paso "CAPTURA 10: Pod nginx en el EKS emulado"
kubectl get pod nginx >/dev/null 2>&1 || kubectl run nginx --image=nginx:alpine --port=80
kubectl wait --for=condition=Ready pod/nginx --timeout=240s
kubectl get pods -o wide

paso "Node group de 2 nodos (solo metadatos en Floci)"
if aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP" >/dev/null 2>&1; then
  echo "El node group ya existe"
else
  NG_SUBNET=${SUBNET:-subnet-demo}
  aws eks create-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP" \
    --node-role "$ROLE_ARN" --subnets "$NG_SUBNET" --instance-types t3.medium \
    --scaling-config minSize=2,maxSize=3,desiredSize=2
fi
aws eks wait nodegroup-active --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP"

paso "CAPTURA 11a: AWS dice que hay 2 nodos..."
aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP" \
  --query 'nodegroup.{Estado:status,Tipo:instanceTypes[0],Deseados:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize}' \
  --output table

paso "CAPTURA 11b: ...pero Kubernetes sigue viendo 1 nodo y hay 1 solo contenedor"
# Floci puede recrear el contenedor al aplicar el tipo t3.medium: se espera a la API.
for _ in $(seq 1 30); do kubectl get nodes >/dev/null 2>&1 && break; sleep 5; done
kubectl get nodes -o wide
echo "Contenedores k3s: $(docker ps -q --filter name=eks | wc -l)"
docker ps --filter name=eks --format 'table {{.Names}}\t{{.Status}}'

paso "Listo. kubectl de tu terminal sigue apuntando a: $(KUBECONFIG= kubectl config current-context)"
echo "Para comandos manuales contra el EKS usa:  bash floci-aws/kubectl-eks.sh <args>"
