# Deploy vault with consul using security considerations

This tutorial deploy:

  * k8s cluster (local kind cluster) for vault/consul.
  * k8s cluster (local kind cluster) for applications that will consume vault secrets, hosted other kubernetes cluster.

In addition to this, security options will be used in the context consul/vault/apps.

## Versions
```
# kind version
kind v0.11.1 go1.16.4 linux/amd64
# vault version
Vault v1.8.1 (4b0264f28defc05454c31277cfa6ff63695a458d)
# consul version
Consul v1.10.2
```
## Create kind clusters

Vault cluster
```
# kind create cluster --name vault --config kind-vault.yaml
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

Apps cluster

```
# kind create cluster --name apps --config kind-apps.yaml
Creating cluster "apps" ...
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

### Get clusters informations

```
# kubectl config use-context kind-apps
# kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:45357
KubeDNS is running at https://127.0.0.1:45357/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

# kubectl get nodes                   
NAME                 STATUS   ROLES                  AGE   VERSION
apps-control-plane   Ready    control-plane,master   24m   v1.20.7
apps-worker          Ready    <none>                 23m   v1.20.7
apps-worker2         Ready    <none>                 23m   v1.20.7
apps-worker3         Ready    <none>                 23m   v1.20.7

# kubectl config use-context kind-vault
Switched to context "kind-vault".
# kubectl cluster-info                 
Kubernetes control plane is running at https://127.0.0.1:35727
KubeDNS is running at https://127.0.0.1:35727/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

# kubectl get nodes   
NAME                  STATUS   ROLES                  AGE     VERSION
vault-control-plane   Ready    control-plane,master   2m56s   v1.20.7
vault-worker          Ready    <none>                 2m22s   v1.20.7
vault-worker2         Ready    <none>                 2m22s   v1.20.7
vault-worker3         Ready    <none>                 2m22s   v1.20.7
```

### Install ingress controller

```
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# kubectl get services -n ingress-nginx
NAME                                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller             NodePort    10.96.170.71    <none>        80:31459/TCP,443:31363/TCP   3m14s
ingress-nginx-controller-admission   ClusterIP   10.96.234.178   <none>        443/TCP                      3m14s
```

Add the url in hosts file
```
# echo "127.0.0.1 clustervault" | sudo tee -a /etc/hosts
```

Test he url
```
# curl http://clustervault   
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>

```

## Create hashicorp namespace
```
# kubectl config use-context kind-vault
# kubectl create namespace hashicorp
namespace/hashicorp created
```

## Hashicorp helm repo

Add hashicorp helm repository
```
# helm repo add hashicorp https://helm.releases.hashicorp.com
# helm repo update
```

## Consul

### Install Consul

This tutorial use vault with consul storage with enabled gossip encryption, TLS, and ACLs.

```
# helm upgrade --install -n hashicorp consul hashicorp/consul --values helm-consul-values.yml
Release "consul" does not exist. Installing it now.
NAME: consul
LAST DEPLOYED: Sat Sep  4 16:59:16 2021
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

### Verify security enabled

Now, you can verify that gossip encryption and TLS are enabled, and that ACLs are being enforced

In a separate terminal, forward port 8501 from the Consul server on Kubernetes so that you can interact with the Consul CLI from the development host

```
# kubectl -n hashicorp port-forward consul-consul-server-0 8501:8501
```

Set the CONSUL_HTTP_ADDR environment variable to use the HTTPS address/port on the development host.

```
# export CONSUL_HTTP_ADDR=https://127.0.0.1:8501
```

Export the CA file from Kubernetes so that you can pass it to the CLI.

```
# kubectl -n hashicorp get secret consul-consul-ca-cert -o jsonpath="{.data['tls\.crt']}" | base64 --decode > ca.pem
```

Now, execute consul members and provide Consul with the ca-file option to verify TLS connections.
```
# consul members -ca-file ca.pem
Node                    Address           Status  Type    Build   Protocol  DC         Segment
consul-consul-server-0  10.244.2.9:8301   alive   server  1.10.0  2         tecktools  <all>
consul-consul-server-1  10.244.3.10:8301  alive   server  1.10.0  2         tecktools  <all>
consul-consul-server-2  10.244.1.10:8301  alive   server  1.10.0  2         tecktools  <all>
```

### Set an ACL token

Now, try launching a debug session.

```
# consul debug -ca-file ca.pem
```

The command fails with the following message:

```
==> Capture validation failed: error querying target agent: Unexpected response code: 403 (Permission denied). verify connectivity and agent address
```

The consul-helm chart created several secrets during the initialization process and registered them with Kubernetes.

For this tutorial you can retrieve the value, decode it, and set it to the CONSUL_HTTP_TOKEN environment variable with the following command.

```
# export CONSUL_HTTP_TOKEN=$(kubectl -n hashicorp get secrets/consul-consul-bootstrap-acl-token --template={{.data.token}} | base64 -d)
```

Try to start a debug session again with an ACL token set.

```
# consul debug -ca-file ca.pem
==> Starting debugger and capturing static information...
     Agent Version: '1.10.0'
          Interval: '30s'
          Duration: '2m0s'
            Output: 'consul-debug-1630792579.tar.gz'
           Capture: 'metrics, logs, pprof, host, agent, cluster'
==> Beginning capture interval 2021-09-04 17:56:19.23206914 -0400 -04 (0)
==> Capture successful 2021-09-04 17:56:20.813324637 -0400 -04 (0)
```

The command succeeds. This proves that ACLs are being enforced. Type CTRL-C to end the debug session in the terminal.

### Create Consul policy to vault

```
# consul acl policy create -name "vault" -description "Policy to access vault path" -rules @consul-vault-policy-rules.hcl -ca-file ca.pem
ID:           cf44af88-9a4f-26f8-9ba6-747a120dd1e1
Name:         vault
Description:  Policy to access vault path
Datacenters:  
Rules:
key_prefix "vault/" {
  policy = "write"
}
```


### Create Consul token to vault

```
# consul acl token create -description "Policy to access vault path" -policy-name "vault" -ca-file ca.pem
AccessorID:       218407fa-c1d0-c182-9fe1-a6dce329852a
SecretID:         3114fd48-c103-3fe8-c3c7-1cde7ad538ee
Description:      Policy to access vault path
Local:            false
Create Time:      2021-09-04 22:15:02.159518609 +0000 UTC
Policies:
   cf44af88-9a4f-26f8-9ba6-747a120dd1e1 - vault
```

## Install vault

Replace "<SecretID>" in helm-vault.yaml with SecretID obtained in the previous step.
```
# helm upgrade --install -n hashicorp vault hashicorp/vault --values helm-vault-values.yml
Release "vault" does not exist. Installing it now.
W0904 18:19:15.134075 2978925 warnings.go:70] networking.k8s.io/v1beta1 Ingress is deprecated in v1.19+, unavailable in v1.22+; use networking.k8s.io/v1 Ingress
W0904 18:19:15.217641 2978925 warnings.go:70] networking.k8s.io/v1beta1 Ingress is deprecated in v1.19+, unavailable in v1.22+; use networking.k8s.io/v1 Ingress
NAME: vault
LAST DEPLOYED: Sat Sep  4 18:19:14 2021
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

Use the following command to register a gossip encryption key as a Kubernetes secret that the helm chart can consume.

```
# kubectl -n hashicorp create secret generic consul-gossip-encryption-key --from-literal=key=$(consul keygen)
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

## Add the url in hosts file
```
# echo "127.0.0.1 vault.clustervault" | sudo tee -a /etc/hosts
```

*NOTE: Because in this tutorial ingress have a self sign certificate, vault command need skip tls verivy*

```
# export VAULT_SKIP_VERIFY=1
```

## Configure Vault

Export url for vault
```
# export VAULT_ADDR=https://vault.clustervault
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

*NOTE: If you use kubernetes 1.21, see the [simple kind example](../kind/README.md#kubernetes-version-121)*

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