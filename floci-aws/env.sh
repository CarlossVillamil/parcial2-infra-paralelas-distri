# Variables comunes para hablar con Floci. Uso:  source floci-aws/env.sh
# test/test son las credenciales "admin" publicas del emulador (no son secretas).
# Las claves del usuario parcial2-operator NUNCA van aqui: viven en ~/.floci/operator.env
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_PAGER=""

FLOCI_ACCOUNT=000000000000
FLOCI_OPERATOR_ENV="$HOME/.floci/operator.env"
EKS_KUBECONFIG="$HOME/.kube/floci-eks"

paso() { printf '\n\033[1;36m==== %s ====\033[0m\n' "$*"; }

usar_operador() {
  if [ ! -f "$FLOCI_OPERATOR_ENV" ]; then
    echo "No existe $FLOCI_OPERATOR_ENV. Corre primero: bash floci-aws/02-iam.sh" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$FLOCI_OPERATOR_ENV"
}

usar_admin() {
  export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
}
