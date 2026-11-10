#!/usr/bin/env bash
# kubectl contra el EKS de Floci sin tocar el contexto de Minikube.
# Ej.:  bash floci-aws/kubectl-eks.sh get pods -o wide
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/env.sh"
usar_operador
export KUBECONFIG="$EKS_KUBECONFIG"
exec kubectl "$@"
