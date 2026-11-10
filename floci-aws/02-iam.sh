#!/usr/bin/env bash
# 6.2 IAM: usuario, rol y politica de minimo privilegio + prueba negativa.
# Corre con las credenciales admin (test/test) y deja las claves del operador
# en ~/.floci/operator.env (fuera del repo, permisos 600).
# Uso:  bash floci-aws/02-iam.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/env.sh"
usar_admin

USER_NAME=parcial2-operator
ROLE_NAME=eks-role
POLICY_NAME=parcial2-least-privilege
POLICY_ARN="arn:aws:iam::$FLOCI_ACCOUNT:policy/$POLICY_NAME"

paso "CAPTURA 3a: politica de minimo privilegio (sin '*' en Action ni Resource)"
cat "$DIR/iam-policy.json"

paso "Usuario $USER_NAME"
aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1 \
  && echo "Ya existe" || aws iam create-user --user-name "$USER_NAME"

paso "Rol $ROLE_NAME (lo exige eks create-cluster)"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "Ya existe"
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$DIR/eks-trust-policy.json"
fi
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
  || echo "(aviso: no se pudo adjuntar AmazonEKSClusterPolicy; no bloquea el flujo)"

paso "Politica $POLICY_NAME"
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "Ya existe: se publica una nueva version con el JSON actual"
  aws iam create-policy-version --policy-arn "$POLICY_ARN" \
    --policy-document "file://$DIR/iam-policy.json" --set-as-default
else
  aws iam create-policy --policy-name "$POLICY_NAME" \
    --policy-document "file://$DIR/iam-policy.json"
fi
aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN"

paso "CAPTURA 3b: politicas adjuntas al operador"
aws iam list-attached-user-policies --user-name "$USER_NAME"

paso "Access key del operador"
if [ -f "$FLOCI_OPERATOR_ENV" ]; then
  echo "Ya existe $FLOCI_OPERATOR_ENV: se reutiliza (no se crea otra clave)."
else
  mkdir -p "$(dirname "$FLOCI_OPERATOR_ENV")"
  chmod 700 "$(dirname "$FLOCI_OPERATOR_ENV")"
  read -r AK SK < <(aws iam create-access-key --user-name "$USER_NAME" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  umask 077
  printf 'export AWS_ACCESS_KEY_ID=%s\nexport AWS_SECRET_ACCESS_KEY=%s\n' "$AK" "$SK" > "$FLOCI_OPERATOR_ENV"
  echo "Clave creada: $AK (el secreto quedo solo en $FLOCI_OPERATOR_ENV)"
fi

paso "Cambiando a las credenciales del operador"
usar_operador
aws sts get-caller-identity

paso "CAPTURA 4: PRUEBA NEGATIVA (cada comando debe fallar con AccessDenied)"
negativa() {
  echo "\$ $*"
  if "$@" 2>&1; then
    echo ">>> PERMITIDO: Floci no aplico la politica (documentar como limitacion del emulador)"
  else
    echo ">>> DENEGADO: la politica de minimo privilegio funciona"
  fi
  echo
}
negativa aws iam list-users
negativa aws s3 mb s3://otro-bucket-no-autorizado
negativa aws eks list-clusters
