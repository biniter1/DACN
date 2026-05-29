# BASELINE CHECKLIST — Trước khi thực hiện kịch bản

## Cấu trúc file baseline
```
baseline/
├── .github/workflows/
│   └── baseline-ci.yml          ← CI với Gitleaks non-blocking
├── helm-chart/
│   └── values-baseline.yaml     ← NetworkPolicy off, seccomp off
├── k8s/manifests/
│   ├── namespace.yaml            ← PSS warn (không enforce restricted)
│   ├── rbac-baseline.yaml        ← Default SA, không RBAC granular
│   └── secrets-baseline.yaml     ← Secret lưu plain text
└── attack-scenarios.sh           ← Script từng kịch bản
```

## So sánh Baseline vs Zero Trust

| Kiểm soát               | Baseline              | Zero Trust             | Demo kịch bản |
|-------------------------|-----------------------|------------------------|---------------|
| Credential              | Long-lived key        | OIDC TTL 15 phút       | KH1           |
| Branch protection       | Require 1 approval    | Require CI pass        | KH1, KH6      |
| Secret scan             | Gitleaks non-blocking | Gitleaks required      | KH1           |
| Image scan              | ECR passive only      | Trivy enforce          | KH2           |
| Image signing           | ❌ Không có           | Cosign + KMS           | KH2           |
| Admission control       | ❌ Không có Kyverno   | Kyverno 5 policies     | KH2           |
| Network segmentation    | ❌ NetworkPolicy off  | NetworkPolicy + Istio  | KH3           |
| Secret management       | K8s Secret plain      | ESO + Secrets Manager  | KH4           |
| RBAC                    | Default SA, no deny   | Per-service SA + deny  | KH4, KH5      |
| SA token mount          | automount = true      | automount = false      | KH5           |
| Runtime detection       | ❌ Không có Falco     | Falco eBPF             | KH4           |
| seccompProfile          | ❌ off                | RuntimeDefault         | (bổ trợ)      |

## Checklist trước khi chụp ảnh

### Môi trường cần có
- [ ] Cluster baseline: `dacn-cluster` (repo DACN) hoặc namespace `boutique-baseline`
- [ ] Cluster Zero Trust: `devsecops-cluster` production namespace
- [ ] kubectl context switch hoạt động
- [ ] AWS CLI configured với account 492462084314

### Setup baseline cluster
```bash
# Deploy baseline
kubectl apply -f baseline/k8s/manifests/namespace.yaml
kubectl apply -f baseline/k8s/manifests/rbac-baseline.yaml
kubectl apply -f baseline/k8s/manifests/secrets-baseline.yaml

helm upgrade --install boutique ./helm-chart \
  --namespace boutique-baseline \
  --values baseline/helm-chart/values-baseline.yaml \
  --wait --timeout 10m

# Verify
kubectl get pods -n boutique-baseline
# Tất cả phải Running
```

### Kiểm tra Zero Trust cluster sẵn sàng
```bash
# Pods running
kubectl get pods -n production

# Falco running
kubectl get pods -n falco

# Kyverno running
kubectl get pods -n kyverno

# Istio ztunnel running
kubectl get pods -n istio-system -l app=ztunnel
```

## Thứ tự chụp ảnh (15 screenshots)

| # | Kịch bản | Baseline cần chụp                          | Zero Trust cần chụp                       |
|---|----------|--------------------------------------------|-------------------------------------------|
| 1 | KH1      | GitHub Actions: secret-scan ❌ nhưng deploy tiếp | GitHub PR: Merge button disabled      |
| 2 | KH1      | AWS CLI: key còn active                    | Terminal: ExpiredTokenException           |
| 3 | KH2      | kubectl rollout: malicious image deployed  | GitHub Actions: Trivy scan ❌             |
| 4 | KH2      | —                                          | cosign verify: "no matching signatures"   |
| 5 | KH2      | —                                          | kubectl run: Kyverno denied               |
| 6 | KH3      | kubectl exec + nc: connection succeeded    | kubectl exec + nc: connection timeout     |
| 7 | KH3      | —                                          | Istio log: rbac_access_denied             |
| 8 | KH4      | printenv: secret plain text                | kubectl exec: AccessDeniedException       |
| 9 | KH4      | kubectl get secret → decode plain          | Falco log: shell spawned alert            |
|10 | KH5      | ls /var/run/secrets: token exists          | ls /var/run/secrets: No such file        |
|11 | KH5      | curl K8s API: configmaps list thành công   | kubectl auth can-i: "no"                 |
|12 | KH6      | git push main: thành công                  | git push main: Protected branch failed   |
|13 | KH6      | —                                          | PR page: CODEOWNERS review required      |
