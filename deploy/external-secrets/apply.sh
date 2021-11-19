#!/bin/bash

VAULT_ADDR="https://seu-vault.com.br"

echo "Entre com o token de acesso ao vault"
read VAULT_TOKEN
echo "Entre com o Environment"
read ENV
echo "Entre com o OWNER do projeto"
read OWNER
echo "Entre com o contexto do kubernetes"
read K8S_CONTEXT
kubectl config use-context $K8S_CONTEXT

echo "Entre com o Cluster Name a ser configurado no vault"
read CLUSTER_NAME

echo "É um cluster ainda não configurado? (sim/nao)"
read NEW_CLUSTER

echo "É um cluster 1.21+? (sim/nao)"
read CLUSTER121

vault login $VAULT_TOKEN

if [[ "$NEW_CLUSTER" == "sim" ]]
then
    echo "Instalando o external secrets"
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
    kubectl create -f serviceaccount.yaml

    VAULT_HELM_SECRET_NAME=$(kubectl -n external-secrets get secrets --output=json | jq -r '.items[].metadata | select(.name|startswith("vault-token-")).name')

    APPS_TOKEN_REVIEW_JWT=$(kubectl -n external-secrets get secret $VAULT_HELM_SECRET_NAME --output='go-template={{ .data.token }}' | base64 --decode)
    APPS_KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
    APPS_KUBE_HOST=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.server}')

    if [[ "$CLUSTER121" == "sim" ]]
    then
        kubectl proxy &
        PROXY_PID=$!
        sleep 20
        ISSUER=$(curl --silent http://127.0.0.1:8001/api/v1/namespaces/default/serviceaccounts/default/token -H "Content-Type: application/json" -X POST -d '{"apiVersion": "authentication.k8s.io/v1", "kind": "TokenRequest"}' | jq -r '.status.token' | cut -d. -f2 | base64 -d | jq -r .iss)
        kill -9 $PROXY_PID
    fi
    echo "Configure vault kubernetes auth"
    vault auth enable --path $CLUSTER_NAME kubernetes
    if [[ "$CLUSTER121" == "$sim" ]]
    then
         vault write auth/$CLUSTER_NAME/config token_reviewer_jwt="$APPS_TOKEN_REVIEW_JWT" kubernetes_host="$APPS_KUBE_HOST" kubernetes_ca_cert="$APPS_KUBE_CA_CERT"
    else
        vault write auth/$CLUSTER_NAME/config token_reviewer_jwt="$APPS_TOKEN_REVIEW_JWT" kubernetes_host="$APPS_KUBE_HOST" kubernetes_ca_cert="$APPS_KUBE_CA_CERT" issuer=$ISSUER
    fi
fi

echo "Create vault police"
cat police-template.hcl | sed "s/env/$ENV/g" | sed "s/owner/$OWNER/g" | vault policy write $ENV-$OWNER-all -

echo "Configure vault role"
vault write auth/$CLUSTER_NAME/role/$ENV-$OWNER-all bound_service_account_names=vault bound_service_account_namespaces=external-secrets policies=$ENV-$OWNER-all ttl=1h

echo "Create external secrets SecretStore"
cat ClusterSecretStore.yaml | sed "s/ENV/$ENV/g" | sed "s/OWNER/$OWNER/g"| sed "s/CLUSTER_NAME/$CLUSTER_NAME/g" |kubectl apply -f -
