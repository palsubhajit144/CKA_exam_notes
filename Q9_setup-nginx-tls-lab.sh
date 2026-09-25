#!/usr/bin/env bash
# Reproduces the "nginx-static ssl_protocols" CKA-style practice scenario.
# Requires: a working kubectl context, and openssl installed locally.
set -e

NAMESPACE=nginx-static
DOMAIN=web.k8x.local

echo "==> Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Generating self-signed TLS cert for $DOMAIN"
mkdir -p /tmp/nginx-lab-certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/nginx-lab-certs/tls.key \
  -out /tmp/nginx-lab-certs/tls.crt \
  -subj "/CN=${DOMAIN}/O=${DOMAIN}" 2>/dev/null

echo "==> Creating TLS secret"
kubectl create secret tls nginx-tls \
  --cert=/tmp/nginx-lab-certs/tls.crt \
  --key=/tmp/nginx-lab-certs/tls.key \
  -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating ConfigMap nginx-config (deliberately TLSv1.3-only, to reproduce the bug)"
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx-static
data:
  nginx.conf: |
    user  nginx;
    worker_processes  auto;
    events { worker_connections 1024; }
    http {
      server {
        listen 443 ssl;
        server_name web.k8x.local;
        ssl_certificate     /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.3;
        location / {
          root /usr/share/nginx/html;
          index index.html;
        }
      }
    }
EOF

echo "==> Creating Deployment nginx-static"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-static
  namespace: nginx-static
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-static
  template:
    metadata:
      labels:
        app: nginx-static
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 443
        volumeMounts:
        - name: nginx-conf
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls
          mountPath: /etc/nginx/tls
          readOnly: true
      volumes:
      - name: nginx-conf
        configMap:
          name: nginx-config
      - name: tls
        secret:
          secretName: nginx-tls
EOF

echo "==> Creating Service nginx-static (NodePort 30443)"
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-static
  namespace: nginx-static
spec:
  type: NodePort
  selector:
    app: nginx-static
  ports:
  - port: 443
    targetPort: 443
    nodePort: 30443
EOF

echo "==> Waiting for rollout"
kubectl rollout status deployment/nginx-static -n "$NAMESPACE"

echo ""
echo "Lab is ready."
echo ""
echo "Option A - NodePort (bare-metal / VM cluster where nodes are reachable):"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "<node-ip>")
echo "  Add to /etc/hosts:  ${NODE_IP}  ${DOMAIN}"
echo "  Test:               curl -k --tls-max 1.2 https://${DOMAIN}:30443"
echo ""
echo "Option B - kind/minikube where NodePort isn't directly reachable:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/nginx-static 8443:443 &"
echo "  Add to /etc/hosts:  127.0.0.1  ${DOMAIN}"
echo "  Test:               curl -k --tls-max 1.2 https://${DOMAIN}:8443"
echo ""
echo "Right now this should FAIL (TLSv1.2 handshake rejected) because"
echo "ssl_protocols is set to TLSv1.3 only. That's the bug to fix."
