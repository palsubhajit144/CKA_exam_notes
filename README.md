# CKA Practice Lab (Q10 – Q16)

## What you get
| Question | Topic | Where to practice | Setup script | Solution script |
|---|---|---|---|---|
| Q10 | Argo CD `helm template` | kind cluster | `q10-setup.sh` | `q10-solution.sh` |
| Q11 | Ingress → Gateway API | kind cluster | `q11-setup.sh` | `q11-solution.sh` |
| Q12 | NetworkPolicy | kind cluster (Calico) | `q12-setup.sh` | `q12-solution.sh` |
| Q13 | Fix broken kubeadm cluster | **separate Ubuntu VM** | `q13-01…` + `q13-02-break.sh` | `q13-03-solution.sh` |
| Q14 | cert-manager CRDs / `kubectl explain` | kind cluster | `q14-setup.sh` | `q14-solution.sh` |
| Q15 | Resource requests (WordPress) | kind cluster | `q15-setup.sh` | `q15-solution.sh` |
| Q16 | Logging sidecar | kind cluster | `q16-setup.sh` | `q16-solution.sh` |

Read `QUESTIONS_EXPLAINED_AND_SOLUTIONS.md` for the simple-language meaning of every question.

## Requirements
- Linux machine or VM (WSL2 also works), 4 CPU / 8 GB RAM recommended, internet access.
- Docker installed and running.
- Q13 needs a **second, fresh Ubuntu 22.04/24.04 VM** (2 CPU / 4 GB) because it breaks a real kubeadm control plane (kind cannot simulate this properly).

## Step-by-step
```bash
cd scripts
./00-prereqs.sh            # installs kubectl, kind, helm (asks you to install Docker if missing)
./01-create-cluster.sh     # 1-node kind cluster "cka": Calico + Gateway API + NGINX Gateway Fabric (GatewayClass "nginx")
```
Then, for each question (example Q10):
```bash
./q10-setup.sh             # builds the exam situation
# ---> read the question, solve it YOURSELF (use kubectl / helm / docs)
./q10-solution.sh          # compare with the reference solution
```
Repeat setup as many times as you want – every setup script deletes and recreates its own objects.

### Q13 (VM)
```bash
# on the fresh Ubuntu VM, as root, copy the scripts there first
./q13-01-kubeadm-install.sh   # builds single-node kubeadm cluster (stacked etcd)
./q13-02-break.sh             # simulates the migration damage
# fix it yourself using crictl / journalctl / editing /etc/kubernetes/manifests
./q13-03-solution.sh          # reference fix
./q13-04-restore.sh           # go back to healthy to repeat
```

### Clean up
`./99-cleanup.sh` deletes the kind cluster and files created in your home folder.

## Notes / honest limitations
- I could not run these scripts in my sandbox (no internet), so if a version in a script has moved (Helm chart, Calico, Gateway API, NGF), change the version string at the top of the command and rerun.
- The lab's node is your own machine, so Q15 numbers differ from the exam. The scripts compute values from *your* node, which is exactly the method you need in the exam.
- Q11 in the lab: there is no public DNS for `gateway.web.k8s.local`, so the solution script tests with `curl --resolve` + `port-forward`. In the exam, plain `curl https://gateway.web.k8s.local` works.
- Q12 in the lab: the default-deny policy is in the `backend` namespace only. In the real exam check whether **both** namespaces have deny policies; the samples decide which single policy you may apply.

## Exam speed tips
```bash
alias k=kubectl; export do="--dry-run=client -o yaml"; source <(kubectl completion bash); complete -o default -F __start_kubectl k
```
Bookmarks to open first: kubernetes.io docs → Gateway API, Network Policies, Static Pods, `kubectl` cheat sheet; helm.sh docs.
