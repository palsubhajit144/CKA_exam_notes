# Questions in simple words + solutions

---
## Q10 – Install Argo CD with Helm (only generate the YAML)
**Simple meaning:** Argo CD is a tool that deploys apps from Git. Helm is a package manager for Kubernetes. Don't install it; just ask Helm to *print* the YAML it would apply (`helm template`), save it into a file, and leave out the CRDs (custom resource definitions) because they already exist in the cluster.

**Steps**
1. Add repo: `helm repo add argo https://argoproj.github.io/argo-helm` (name = `argo`), then `helm repo update`.
2. Generate: 
```bash
helm template argocd argo/argo-cd --version 7.7.3 --namespace argocd --set crds.install=false > ~/argo-helm.yaml
```
3. Check: `grep -c "kind: CustomResourceDefinition" ~/argo-helm.yaml` → `0`.
4. Install Argo CD:
   ```bash
		helm install argocd argo/argo-cd --namespace argocd --version 7.7.3 --set crds.install=false
   ```
**Traps:** forgetting `--version 7.7.3`, forgetting `--namespace argocd`, forgetting `crds.install=false`. If unsure about values: `helm show values argo/argo-cd --version 7.7.3 | grep -n -A3 crds`.

---
## Q11 – Move from Ingress to Gateway API
**Simple meaning:** Ingress is the old way to expose a web app on HTTPS. Gateway API is the new way and splits it in two objects: a **Gateway** (the "door": hostname, port 443, TLS certificate) and an **HTTPRoute** (the "signposts": which path goes to which Service). Copy the settings from Ingress `web` into these two, test with curl, then delete the Ingress.

**Steps**
1. Read the old config: `kubectl get ingress web -o yaml` → note host, TLS secret name, paths → services/ports.
2. Gateway (`gatewayClassName: nginx`, listener HTTPS 443, hostname, `tls.mode: Terminate`, `certificateRefs` = the same secret as the Ingress).
3. HTTPRoute (`parentRefs: web-gateway`, same hostname, same path rules and backends).
4. Test `curl https://gateway.web.k8s.local` (add `-k` if the certificate is self-signed).
5. `kubectl delete ingress web`.

Full YAML: see `scripts/q11-solution.sh`.
**Mapping table:** Ingress `tls.secretName` → Gateway `listeners[].tls.certificateRefs`; Ingress `host` → Gateway `hostname` + Route `hostnames`; Ingress `paths` → Route `rules[].matches` + `backendRefs`; Ingress `pathType: Prefix` → `PathPrefix`.
**Traps:** listener protocol must be `HTTPS` (not HTTP); Gateway and Route in the same namespace as the Secret/Services unless you configure cross-namespace; delete the Ingress only *after* it works. Check `kubectl describe gateway web-gateway` for "Accepted/Programmed = True".

---
## Q12 – Pick the right NetworkPolicy
**Simple meaning:** By default all pods talk to all pods. A "default deny" policy blocks everything. You must pick **one** ready-made policy in `~/netpol` that lets *only* the frontend pods reach the backend pods, on the port the backend really listens on – not more.

**How to decide**
1. Look at labels and ports: 
   `kubectl -n frontend get deploy frontend -o yaml | grep -A3 labels`
   `kubectl -n backend get deploy backend -o yaml | grep -E -A3 "labels|containerPort"`
2. Open each sample and compare. Reject a sample if it: allows everything (`- {}`), selects the wrong labels or wrong port, has a `podSelector` without `namespaceSelector` (would only match pods in the *backend* namespace), or allows the whole namespace / all ports (too permissive).
3. Best sample = `namespaceSelector` (frontend namespace) **and** `podSelector` (frontend pods) in the *same* `from` item (that is AND), plus the correct port. In the lab that is `netpol3.yaml`.
4. `kubectl apply -f ~/netpol/netpolX.yaml` — don't edit or delete anything else.

**Trap:** two separate `- namespaceSelector` / `- podSelector` list items = OR (much more permissive); one item with both = AND. If the deny-all also blocks *egress* on the frontend side, check whether the chosen sample handles egress; you may only apply one.

---
## Q13 – Fix a cluster after migration (external etcd → local etcd)
**Simple meaning:** The cluster was copied to a new machine. Its old settings still point to a different (external) etcd database that no longer exists. The kube-apiserver can't reach its database, and other components use old addresses. Find each broken piece and repoint it to the local machine/etcd, then make sure everything restarts and is Ready.

**Investigate (kubectl may not work!)**
```bash
sudo -i
systemctl status kubelet ; journalctl -u kubelet -n 50 --no-pager
crictl ps -a                      # which control-plane containers are Exited/crashing
crictl logs <container-id>        # read the error (e.g. dial tcp 10.x.x.x:2379 timeout)
ls /var/log/pods/                 # logs if crictl is empty
grep -rn "etcd" /etc/kubernetes/manifests/kube-apiserver.yaml
cat /etc/kubernetes/manifests/etcd.yaml   # local etcd listens on 127.0.0.1:2379 with certs in /etc/kubernetes/pki/etcd
```
**Typical fixes**
- `kube-apiserver.yaml`: `--etcd-servers=https://127.0.0.1:2379`; `--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt`; `--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt`; `--etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key`.
- `kube-scheduler` / `kube-controller-manager`: check `/etc/kubernetes/scheduler.conf` and `controller-manager.conf` → `server:` must equal the address in `admin.conf`. Also check the manifests for wrong paths/IPs.
- kubelet: `/etc/kubernetes/kubelet.conf` server address; `systemctl restart kubelet`.
- Static pods only restart when their manifest *changes*; if you edit only a kubeconfig, move the manifest out of `/etc/kubernetes/manifests`, wait ~20s, move it back.

**Verify:** `kubectl get nodes` (Ready) and `kubectl get pods -A` (all Running/Ready).
Edit manifests with care: a YAML typo makes the pod disappear. Keep a backup copy outside the manifests folder.

---
## Q14 – cert-manager CRDs and field documentation
**Simple meaning:** cert-manager adds new resource types (CRDs) like Certificate and Issuer. (a) Save the list of its CRDs into a file, (b) save the built-in documentation of one field (`subject`) of the Certificate resource.

```bash
kubectl get crd | grep cert-manager > ~/resources.yaml     # default output = no "-o yaml"
kubectl explain certificate.spec.subject > ~/subject.yaml
```
**Traps:** using `-o yaml`/`-o name` breaks "default output format". `kubectl explain` works because the CRD carries a schema; if there are several versions add `--api-version=cert-manager.io/v1`.

---
## Q15 – Fix Pod resource requests (WordPress)
**Simple meaning:** "requests" = what the scheduler reserves for a pod. They are too big, so 3 pods don't fit on the one node. Split the node's capacity evenly by 3 pods, keep some spare for the system (overhead), and use the *same* numbers for init containers and normal containers. Limits stay unchanged.

**Steps**
1. Node capacity: `kubectl describe node | grep -A8 Allocatable` (use *Allocatable*).
2. Maths: `(allocatable × ~85–90%) ÷ 3`. Example: 4000m CPU, 8000Mi → keep ~10–15% → ≈ 1100m and ≈ 2300Mi per pod.
3. `kubectl -n relative-fawn scale deploy wordpress --replicas=0`
4. `kubectl -n relative-fawn edit deploy wordpress` → set `resources.requests.cpu/memory` on **every** container **and** init container.
5. `kubectl -n relative-fawn scale deploy wordpress --replicas=3` → all 3 Running/Ready.

**Why "same for init":** a pod's effective request is `max(largest init container, sum of app containers)`, so a big init container blocks scheduling too. **Trap:** a request larger than an existing limit is invalid – fix or mention. See `scripts/q15-solution.sh` for an automated version.

---
## Q16 – Logging sidecar
**Simple meaning:** The old app writes logs into a *file*, not to the screen, so `kubectl logs` shows nothing. Add a second container (sidecar) in the same Pod that reads that file and prints it to its own stdout. Both containers share the file through a shared volume.

**Steps**: `kubectl edit deploy synergy-leverager` and add:
```yaml
spec:
  template:
    spec:
      volumes:
      - name: logs
        emptyDir: {}
      containers:
      - name: <existing-container>      # only add this volumeMount, change nothing else
        volumeMounts:
        - name: logs
          mountPath: /var/log
      - name: sidecar
        image: busybox:stable
        command: ["/bin/sh","-c","tail -n+1 -f /var/log/synergy-leverager.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log
```
Verify: `kubectl logs deploy/synergy-leverager -c sidecar`.
**Traps:** type plain ASCII `-` and `"` (the pasted question contains fancy dashes/quotes); the file name is `synergy-leverager.log` (copy it exactly); don't touch other fields of the existing container.
