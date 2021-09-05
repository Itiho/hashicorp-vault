# Deploy vault with consul in kind k8s 1.21+

**NOTE**: At the time of writing, HashiCorp vault (v1.8.1) requires additional steps when running in Kubernetes 1.21 or newer. Starting k8s v1.21, [Service Account Issuer Discovery](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-issuer-discovery) feature gate is now stable and enabled by default. 

You have 2 methods of resolving the issue.
* Secure: Configure your cluster to securely serve validation. 
* Insecure: Disable issuer validation.

This tutorial try this 2 methods and k8s 1.20 method too.

## Versions
```
# kind version
kind v0.11.1 go1.16.4 linux/amd64
# vault version
Vault v1.8.1 (4b0264f28defc05454c31277cfa6ff63695a458d)
```
## Create kind cluster

Create the cluster with the version you want
```
# kind create cluster --name vault --config kind1.21.yaml
Creating cluster "vault" ...
 ✓ Ensuring node image (kindest/node:v1.21.1) 🖼
 ✓ Preparing nodes 📦 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-vault"
You can now use your cluster with:

kubectl cluster-info --context kind-vault

Thanks for using kind!
```

or 

```
# kind create cluster --name vault --config kind1.20.yaml
Creating cluster "vault" ...
 ✓ Ensuring node image (kindest/node:v1.20.7) 🖼
 ✓ Preparing nodes 📦 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-vault"
You can now use your cluster with:

kubectl cluster-info --context kind-vault

Thanks for using kind!
```

### Get cluster informations

```
# kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:34259
CoreDNS is running at https://127.0.0.1:34259/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

# kubectl get nodes
NAME                  STATUS   ROLES                  AGE   VERSION
vault-control-plane   Ready    control-plane,master   97s   v1.21.1
vault-worker          Ready    <none>                 62s   v1.21.1
vault-worker2         Ready    <none>                 62s   v1.21.1
vault-worker3         Ready    <none>                 62s   v1.21.1
```

## Create hashicorp namespace
```
# kubectl create namespace hashicorp
namespace/hashicorp created
```

## Hashicorp helm repo

Add hashicorp helm repository
```
# helm repo add hashicorp https://helm.releases.hashicorp.com
# helm repo update
```

## Install Consul

This tutorial use vault with consul storage

```
# helm upgrade --install -n hashicorp consul hashicorp/consul --values helm-consul-values.yml
Release "consul" does not exist. Installing it now.
W0903 08:29:17.518478 2335357 warnings.go:70] policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget
W0903 08:29:17.679264 2335357 warnings.go:70] policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget
NAME: consul
LAST DEPLOYED: Fri Sep  3 08:29:16 2021
NAMESPACE: hashicorp
STATUS: deployed
REVISION: 1
NOTES:
Thank you for installing HashiCorp Consul!

Now that you have deployed Consul, you should look over the docs on using
Consul with Kubernetes available here:

https://www.consul.io/docs/platform/k8s/index.html


Your release is named consul.

To learn more about the release, run:

  $ helm status consul
  $ helm get all consul

# kubectl -n hashicorp get pods
NAME                     READY   STATUS    RESTARTS   AGE
consul-consul-server-0   0/1     Running   0          15s
consul-consul-server-1   0/1     Running   0          15s
consul-consul-server-2   0/1     Running   0          15s

# kubectl -n hashicorp get statefulset
NAME                   READY   AGE
consul-consul-server   3/3     79s
```

## Install vault
```
# helm upgrade --install -n hashicorp vault hashicorp/vault --values helm-vault-values.yml
Release "vault" does not exist. Installing it now.
W0903 08:33:42.101707 2351264 warnings.go:70] policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget
W0903 08:33:42.145334 2351264 warnings.go:70] policy/v1beta1 PodDisruptionBudget is deprecated in v1.21+, unavailable in v1.25+; use policy/v1 PodDisruptionBudget
NAME: vault
LAST DEPLOYED: Fri Sep  3 08:33:41 2021
NAMESPACE: hashicorp
STATUS: deployed
REVISION: 1
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get manifest vault

# kubectl -n hashicorp get pods
NAME                                    READY   STATUS    RESTARTS   AGE
consul-consul-server-0                  1/1     Running   0          6m13s
consul-consul-server-1                  1/1     Running   0          6m13s
consul-consul-server-2                  1/1     Running   0          6m13s
vault-0                                 0/1     Running   0          108s
vault-1                                 0/1     Running   0          108s
vault-2                                 0/1     Running   0          107s
vault-3                                 0/1     Running   0          106s
vault-4                                 0/1     Running   0          105s
vault-agent-injector-745867c568-44jp7   1/1     Running   0          108s
```

## Vault generates a master key

```
# kubectl -n hashicorp exec vault-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json > vault-keys.json
# VAULT_UNSEAL_KEY1=$(cat vault-keys.json | jq -r ".unseal_keys_b64[0]")
# VAULT_UNSEAL_KEY2=$(cat vault-keys.json | jq -r ".unseal_keys_b64[1]")
# VAULT_UNSEAL_KEY3=$(cat vault-keys.json | jq -r ".unseal_keys_b64[2]")
# VAULT_UNSEAL_KEY4=$(cat vault-keys.json | jq -r ".unseal_keys_b64[3]")
# VAULT_UNSEAL_KEY5=$(cat vault-keys.json | jq -r ".unseal_keys_b64[4]")
# VAULT_TOKEN=$(cat vault-keys.json | jq -r ".root_token")
```

## Unseal vault
```
# kubectl -n hashicorp exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY1
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       5
Threshold          3
Unseal Progress    1/3
Unseal Nonce       edd944aa-bc2c-843e-a747-adabe6fb3c4a
Version            1.8.1
Storage Type       consul
HA Enabled         true

# kubectl -n hashicorp exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY2
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       5
Threshold          3
Unseal Progress    2/3
Unseal Nonce       edd944aa-bc2c-843e-a747-adabe6fb3c4a
Version            1.8.1
Storage Type       consul
HA Enabled         true

# kubectl -n hashicorp exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY3
Key                    Value
---                    -----
Seal Type              shamir
Initialized            true
Sealed                 false
Total Shares           5
Threshold              3
Version                1.8.1
Storage Type           consul
Cluster Name           vault-cluster-03171017
Cluster ID             cec54185-e18a-eddb-b9cc-c69ff67a7609
HA Enabled             true
HA Cluster             n/a
HA Mode                standby
Active Node Address    <none>
```

Repeat the commands for vault[1-4]

```
# kubectl -n hashicorp exec vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY1
# kubectl -n hashicorp exec vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY2
# kubectl -n hashicorp exec vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY3
# kubectl -n hashicorp exec vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY1
# kubectl -n hashicorp exec vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY2
# kubectl -n hashicorp exec vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY3
# kubectl -n hashicorp exec vault-3 -- vault operator unseal $VAULT_UNSEAL_KEY1
# kubectl -n hashicorp exec vault-3 -- vault operator unseal $VAULT_UNSEAL_KEY2
# kubectl -n hashicorp exec vault-3 -- vault operator unseal $VAULT_UNSEAL_KEY3
# kubectl -n hashicorp exec vault-4 -- vault operator unseal $VAULT_UNSEAL_KEY1
# kubectl -n hashicorp exec vault-4 -- vault operator unseal $VAULT_UNSEAL_KEY2
# kubectl -n hashicorp exec vault-4 -- vault operator unseal $VAULT_UNSEAL_KEY3
```

## Configure Vault

In other terminal run port-forward
```
# kubectl -n hashicorp port-forward vault-0 8200:8200
```

Login in vault using root token
```
# vault login $VAULT_TOKEN
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                <token>
token_accessor       BWbrB9Wb3VInODesuY8FCoI4
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

If you see the error below
```
Error authenticating: error looking up token: Get "https://127.0.0.1:8200/v1/auth/token/lookup-self": EOF
```

Export vault HTTP address and try again
```
# export VAULT_ADDR='http://127.0.0.1:8200'
# vault login $VAULT_TOKEN                         
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                <token>
token_accessor       BWbrB9Wb3VInODesuY8FCoI4
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

### Secrets

Enable secret
```
# vault secrets enable --path=secrets kv
```

Create a demo secret
```
# vault kv put secrets/demo user=admin pass=admin123
Success! Data written to: secrets/demo
# vault kv get secrets/demo
==== Data ====
Key     Value
---     -----
pass    admin123
user    admin
```
### Policies

Create de police
```
# vault policy write demo-police demo-police.hcl
# vault policy read demo-police
path "secrets/demo" {
  capabilities = ["read"]
}
```

### Kubernetes auth
```
# vault auth enable --path kubernetes-kind kubernetes
```

Get cluster values
```
# K8S_TOKEN=$(kubectl -n hashicorp exec vault-0 -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
# K8S_CA=$(kubectl -n hashicorp exec vault-0 -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
# K8S_ADDRESS="https://$(kubectl -n hashicorp exec vault-0 -- sh -c 'echo $KUBERNETES_PORT_443_TCP_ADDR'):443"
```

#### Kubernetes up to version 1.20 (original documentation):
Configure auth
```
# vault write auth/kubernetes-kind/config token_reviewer_jwt="$K8S_TOKEN" kubernetes_host="$K8S_ADDRESS" kubernetes_ca_cert=$K8S_CA
# vault read auth/kubernetes-kind/config
Key                       Value
---                       -----
disable_iss_validation    false
disable_local_ca_jwt      false
issuer                    n/a
kubernetes_ca_cert        -----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
kubernetes_host           https://10.96.0.1:443
pem_keys                  []
```

#### Kubernetes version 1.21+ 

##### Insecure: Disable issuer validation
kubernetes-kind
Configure auth
```
# vault write auth/kubernetes-kind/config token_reviewer_jwt="$K8S_TOKEN" kubernetes_host="$K8S_ADDRESS" kubernetes_ca_cert=$K8S_CA disable_iss_validation=true
# vault read auth/kubernetes-kind/config
Key                       Value
---                       -----
disable_iss_validation    true
disable_local_ca_jwt      false
issuer                    n/a
kubernetes_ca_cert        -----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
kubernetes_host           https://10.96.0.1:443
pem_keys                  []
```
##### Secure: Configure your cluster to securely serve validation.

In another terminal run
```
kubectl proxy
```

Get the issue address
```
# ISSUER=$(curl --silent http://127.0.0.1:8001/api/v1/namespaces/default/serviceaccounts/default/token -H "Content-Type: application/json" -X POST -d '{"apiVersion": "authentication.k8s.io/v1", "kind": "TokenRequest"}' | jq -r '.status.token' | cut -d. -f2 | base64 -d | jq -r .iss)
# echo $ISSUER
https://kubernetes.default.svc.cluster.local
```


Configure auth
```
# vault write auth/kubernetes-kind/config token_reviewer_jwt="$K8S_TOKEN" kubernetes_host="$K8S_ADDRESS" kubernetes_ca_cert=$K8S_CA issuer=$ISSUER
# vault read auth/kubernetes-kind/config
Key                       Value
---                       -----
disable_iss_validation    false
disable_local_ca_jwt      false
issuer                    https://kubernetes.default.svc.cluster.local
kubernetes_ca_cert        -----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
kubernetes_host           https://10.96.0.1:443
pem_keys                  []

```
### Create role
```
# vault write auth/kubernetes-kind/role/demo bound_service_account_names=demo-app bound_service_account_namespaces=default policies=demo-police ttl=1h
Success! Data written to: auth/kubernetes-kind/role/demo
```

### Deployment

Apply the deployment
```
# kubectl apply -f demo-deploy.yaml
```

Get logs valt agent logs
```
# kubectl get pods
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-78ff9bd694-hr22n   1/1     Running   0          2m21s
# kubectl logs demo-app-78ff9bd694-hr22n -c vault-agent-init
==> Vault agent started! Log data will stream in below:

==> Vault agent configuration:

                     Cgo: disabled
               Log Level: info
                 Version: Vault v1.8.1
             Version Sha: 4b0264f28defc05454c31277cfa6ff63695a458d

2021-09-03T17:34:24.648Z [INFO]  sink.file: creating file sink
2021-09-03T17:34:24.648Z [INFO]  sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r-----
2021-09-03T17:34:24.649Z [INFO]  sink.server: starting sink server
2021-09-03T17:34:24.649Z [INFO]  template.server: starting template server
2021-09-03T17:34:24.649Z [INFO] (runner) creating new runner (dry: false, once: false)
2021-09-03T17:34:24.649Z [INFO]  auth.handler: starting auth handler
2021-09-03T17:34:24.649Z [INFO]  auth.handler: authenticating
2021-09-03T17:34:24.649Z [INFO] (runner) creating watcher
2021-09-03T17:34:24.673Z [INFO]  auth.handler: authentication successful, sending token to sinks
2021-09-03T17:34:24.673Z [INFO]  auth.handler: starting renewal process
2021-09-03T17:34:24.673Z [INFO]  sink.file: token written: path=/home/vault/.vault-token
2021-09-03T17:34:24.673Z [INFO]  sink.server: sink server stopped
2021-09-03T17:34:24.673Z [INFO]  sinks finished, exiting
2021-09-03T17:34:24.673Z [INFO]  template.server: template server received new token
2021-09-03T17:34:24.673Z [INFO] (runner) stopping
2021-09-03T17:34:24.673Z [INFO] (runner) creating new runner (dry: false, once: false)
2021-09-03T17:34:24.673Z [INFO] (runner) creating watcher
2021-09-03T17:34:24.673Z [INFO] (runner) starting
2021-09-03T17:34:24.683Z [INFO]  auth.handler: renewed auth token
2021-09-03T17:34:24.781Z [INFO] (runner) rendered "(dynamic)" => "/vault/secrets/demo"
2021-09-03T17:34:24.781Z [INFO] (runner) stopping
2021-09-03T17:34:24.781Z [INFO]  template.server: template server stopped
2021-09-03T17:34:24.781Z [INFO] (runner) received finish
2021-09-03T17:34:24.781Z [INFO]  auth.handler: shutdown triggered, stopping lifetime watcher
2021-09-03T17:34:24.781Z [INFO]  auth.handler: auth handler stopped
```

Verify if secrets is inject

```
# kubectl exec demo-app-78ff9bd694-hr22n -c demo-app -- cat /usr/share/nginx/html/index.html
user=admin<br>pass=admin123>
# kubectl exec demo-app-78ff9bd694-hr22n -c demo-app -- cat /vault/secrets/demo             

export pass=admin123

export user=admin
# kubectl exec demo-app-78ff9bd694-hr22n -c demo-app -- curl -s http://localhost
user=admin<br>pass=admin123>
```