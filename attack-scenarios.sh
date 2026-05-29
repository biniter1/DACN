#!/bin/bash
# ============================================================
# attack-scenarios.sh — Script thực hiện 6 kịch bản
#
# Cách dùng:
#   Đọc từng block, chạy từng lệnh, chụp ảnh output quan trọng
#   📸 = điểm cần chụp ảnh
#
# Môi trường cần chuẩn bị:
#   - kubectl context: boutique-baseline (baseline)
#   - kubectl context: devsecops-cluster/production (zero trust)
#   - AWS CLI configured
# ============================================================

# Alias tiện lợi
BASELINE_NS="boutique-baseline"
ZT_NS="production"

# ══════════════════════════════════════════════════════════════
# KH1 — CREDENTIAL LEAK
# Baseline: long-lived key → lộ rồi vẫn dùng được mãi
# Zero Trust: OIDC token TTL 15 phút → hết hạn tự vô hiệu
# ══════════════════════════════════════════════════════════════

## --- BASELINE: push secret lên repo ---

# Tạo file .env với AWS key (dùng key giả để demo)
cat > /tmp/demo.env << 'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
DATABASE_PASSWORD=SuperSecret123!
PAYMENT_API_KEY=sk_live_4xNmAfR3y2TkVCJ8kLpQ
EOF
# 📸 Chụp: nội dung file .env

# Gitleaks chạy nhưng non-blocking → push thành công
# Mở GitHub Actions tab để thấy job "Secret Scan" ❌ nhưng pipeline tiếp tục
# 📸 Chụp: GitHub Actions - job secret-scan failed nhưng deploy job vẫn chạy

# Attacker tìm thấy key đã commit, thử dùng:
# (Giả lập: key đang active trong GitHub Secrets của baseline)
aws sts get-caller-identity \
  --profile baseline-demo 2>&1
# 📸 Chụp: Account ID trả về → key còn hoạt động

## --- ZERO TRUST: Gitleaks block merge ---

# Tương tự tạo PR với .env file
# GitHub CI bắt buộc → Gitleaks fail → nút Merge bị disabled
# 📸 Chụp: GitHub PR page - "All checks have failed" + Merge button disabled

# OIDC token đã hết hạn sau 15 phút
aws sts get-caller-identity \
  --profile zt-expired-session 2>&1
# Output: ExpiredTokenException
# 📸 Chụp: "ExpiredTokenException: security token expired"

# ══════════════════════════════════════════════════════════════
# KH2 — MALICIOUS IMAGE DEPLOY
# Baseline: không verify image → deploy bất kỳ image nào
# Zero Trust: Trivy + Cosign + Kyverno → 3 lớp chặn
# ══════════════════════════════════════════════════════════════

## --- BASELINE: deploy unsigned/unscanned image ---

# Tag image bất kỳ (chứa CVE critical) vào ECR
docker pull python:3.6-alpine  # image cũ, có nhiều CVE
docker tag python:3.6-alpine \
  492462084314.dkr.ecr.ap-southeast-1.amazonaws.com/online-boutique/frontend:malicious
docker push \
  492462084314.dkr.ecr.ap-southeast-1.amazonaws.com/online-boutique/frontend:malicious

# Deploy thẳng vào baseline cluster (không bị chặn)
kubectl set image deployment/frontend \
  server=492462084314.dkr.ecr.ap-southeast-1.amazonaws.com/online-boutique/frontend:malicious \
  -n $BASELINE_NS
kubectl rollout status deployment/frontend -n $BASELINE_NS --timeout=120s
# 📸 Chụp: "deployment.apps/frontend successfully rolled out" → malicious image đang chạy!

## --- ZERO TRUST: 3 lớp chặn ---

# Lớp 1: Trivy ENFORCE trong pipeline → build fail nếu có CVE critical
# 📸 Chụp: GitHub Actions - step "Trivy image scan (ENFORCE)" ❌

# Lớp 2: Cosign verify fail
cosign verify \
  --key "awskms:///arn:aws:kms:ap-southeast-1:492462084314:key/b51a51ea-5064-424e-aaa9-458d2b4576dd" \
  492462084314.dkr.ecr.ap-southeast-1.amazonaws.com/online-boutique/frontend:malicious 2>&1
# 📸 Chụp: "Error: no matching signatures"

# Lớp 3: Kyverno block kubectl apply
kubectl run attacker-test \
  --image=492462084314.dkr.ecr.ap-southeast-1.amazonaws.com/online-boutique/frontend:malicious \
  -n $ZT_NS 2>&1
# 📸 Chụp: "admission webhook ... denied ... verify-image-signature"

# ══════════════════════════════════════════════════════════════
# KH3 — LATERAL MOVEMENT
# Baseline: không có NetworkPolicy → mọi pod nói chuyện được
# Zero Trust: NetworkPolicy + Istio mTLS + AuthorizationPolicy
# ══════════════════════════════════════════════════════════════

## --- BASELINE: frontend → paymentservice ---

# Lấy tên frontend pod trong baseline
FRONTEND_BASELINE=$(kubectl get pod -n $BASELINE_NS \
  -l app=frontend -o jsonpath='{.items[0].metadata.name}')
echo "Frontend pod: $FRONTEND_BASELINE"

# Exec vào pod → gọi paymentservice (không bị chặn)
kubectl exec -it $FRONTEND_BASELINE -n $BASELINE_NS -- \
  sh -c "nc -zv paymentservice 50051 2>&1; echo 'exit: '$?"
# Output: "Connection to paymentservice 50051 port [tcp/*] succeeded!"
# 📸 Chụp: "succeeded!" → lateral movement thành công

# Thử tiếp cartservice từ frontend
kubectl exec -it $FRONTEND_BASELINE -n $BASELINE_NS -- \
  sh -c "nc -zv redis-cart 6379 2>&1"
# 📸 Chụp: kết nối Redis thành công từ frontend pod

## --- ZERO TRUST: NetworkPolicy + Istio block ---

FRONTEND_ZT=$(kubectl get pod -n $ZT_NS \
  -l app=frontend -o jsonpath='{.items[0].metadata.name}')

# Thử gọi paymentservice từ frontend (chỉ checkoutservice mới được phép)
kubectl exec -it $FRONTEND_ZT -n $ZT_NS -- \
  sh -c "nc -zv paymentservice 50051 -w 5 2>&1; echo 'exit: '$?"
# Output: connection timeout hoặc "No route to host"
# 📸 Chụp: connection failed/timeout

# Xem Istio access log thấy RBAC deny
kubectl logs -n istio-system \
  $(kubectl get pod -n istio-system -l app=ztunnel \
  -o jsonpath='{.items[0].metadata.name}') \
  --tail=10 | grep -E "rbac_access_denied|frontend|payment"
# 📸 Chụp: rbac_access_denied trong log

# ══════════════════════════════════════════════════════════════
# KH4 — SECRET EXFILTRATION
# Baseline: secret lưu K8s Secret plain, không có RBAC restrict
# Zero Trust: RBAC deny, Pod Identity scoped, Falco phát hiện
# ══════════════════════════════════════════════════════════════

## --- BASELINE: đọc secret dễ dàng ---

# Bất kỳ pod nào cũng exec được, đọc env vars
CART_BASELINE=$(kubectl get pod -n $BASELINE_NS \
  -l app=cartservice -o jsonpath='{.items[0].metadata.name}')

kubectl exec $CART_BASELINE -n $BASELINE_NS -- \
  sh -c 'printenv | grep -iE "redis|password|key|secret|token"'
# 📸 Chụp: env vars lộ plain text (REDIS_PASSWORD, etc.)

# Đọc thẳng K8s secret từ kubectl (không bị RBAC chặn)
kubectl get secret boutique-secrets -n $BASELINE_NS \
  -o jsonpath='{.data}' | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
for k, v in d.items():
    print(f'{k} = {base64.b64decode(v).decode()}')
"
# 📸 Chụp: secrets decoded hiển thị plain text

# Thậm chí từ trong pod, dùng SA token để list secrets qua API
FRONTEND_BASELINE=$(kubectl get pod -n $BASELINE_NS \
  -l app=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl exec $FRONTEND_BASELINE -n $BASELINE_NS -- \
  sh -c '
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    curl -sk --cacert $CACERT \
      -H "Authorization: Bearer $TOKEN" \
      https://kubernetes.default.svc/api/v1/namespaces/boutique-baseline/secrets \
    | grep -o "\"name\":\"[^\"]*\"" | head -10
  '
# 📸 Chụp: danh sách secrets từ K8s API

## --- ZERO TRUST: RBAC deny + Falco alert ---

FRONTEND_ZT=$(kubectl get pod -n $ZT_NS \
  -l app=frontend -o jsonpath='{.items[0].metadata.name}')

# Thử list secrets → RBAC deny
kubectl exec $FRONTEND_ZT -n $ZT_NS -- \
  sh -c '
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null || echo "NO_TOKEN")
    if [ "$TOKEN" = "NO_TOKEN" ]; then
      echo "ERROR: No service account token mounted"
    else
      CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      curl -sk --cacert $CACERT \
        -H "Authorization: Bearer $TOKEN" \
        https://kubernetes.default.svc/api/v1/namespaces/production/secrets
    fi
  ' 2>&1
# 📸 Chụp: "Forbidden" hoặc "No token mounted"

# Thử đọc AWS secret qua CLI (Pod Identity scoped chỉ cho service cụ thể)
kubectl exec $FRONTEND_ZT -n $ZT_NS -- \
  aws secretsmanager get-secret-value \
  --secret-id prod/payment/api-key \
  --region ap-southeast-1 2>&1
# 📸 Chụp: "AccessDeniedException"

# Falco phát hiện exec vào pod (mở terminal thứ 2 để xem)
# Terminal 2: kubectl logs -n falco <falco-pod> -f | grep "shell spawned"
# Terminal 1: kubectl exec <pod> -n production -- /bin/sh -c "id"
# 📸 Chụp: Falco log "Notice: shell spawned by non-shell process"

# ══════════════════════════════════════════════════════════════
# KH5 — UNAUTHORIZED SERVICE ACCOUNT
# Baseline: SA token tự mount, không RBAC restrict → đọc K8s API
# Zero Trust: automountServiceAccountToken=false + RBAC deny
# ══════════════════════════════════════════════════════════════

## --- BASELINE: SA token bị lộ ---

FRONTEND_BASELINE=$(kubectl get pod -n $BASELINE_NS \
  -l app=frontend -o jsonpath='{.items[0].metadata.name}')

# Token được mount tự động trong pod
kubectl exec $FRONTEND_BASELINE -n $BASELINE_NS -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Output: ca.crt  namespace  token
# 📸 Chụp: thư mục token tồn tại

# Dùng token gọi K8s API → list configmaps
kubectl exec $FRONTEND_BASELINE -n $BASELINE_NS -- \
  sh -c '
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    curl -sk --cacert $CACERT \
      -H "Authorization: Bearer $TOKEN" \
      https://kubernetes.default.svc/api/v1/namespaces/boutique-baseline/configmaps \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
for item in d.get(\"items\", []):
    print(\"ConfigMap:\", item[\"metadata\"][\"name\"])
"
  '
# 📸 Chụp: list configmaps thành công = attacker biết được cấu hình

## --- ZERO TRUST: token không mount ---

FRONTEND_ZT=$(kubectl get pod -n $ZT_NS \
  -l app=frontend -o jsonpath='{.items[0].metadata.name}')

kubectl exec $FRONTEND_ZT -n $ZT_NS -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Output: "ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory"
# 📸 Chụp: directory không tồn tại

# Xác nhận qua kubectl describe pod
kubectl get pod $FRONTEND_ZT -n $ZT_NS \
  -o jsonpath='{.spec.automountServiceAccountToken}' 2>&1
# Output: false
# 📸 Chụp: automountServiceAccountToken = false

# Kiểm tra RBAC: SA frontend không được list secrets dù có token
kubectl auth can-i list secrets \
  --namespace $ZT_NS \
  --as=system:serviceaccount:$ZT_NS:frontend
# Output: no
# 📸 Chụp: "no"

# ══════════════════════════════════════════════════════════════
# KH6 — PIPELINE TAMPERING
# Baseline: push thẳng main, sửa/xóa CI workflow được
# Zero Trust: branch protection + CODEOWNERS chặn
# ══════════════════════════════════════════════════════════════

## --- BASELINE: xóa security check, push thẳng main ---

# Giả lập developer "simplify" CI bằng cách xóa secret scan
# Trên repo DACN (baseline), không có branch protection cứng
git -C /tmp/dacn-demo checkout main 2>/dev/null || \
  git clone https://github.com/biniter1/DACN /tmp/dacn-demo

cd /tmp/dacn-demo
# Xóa Gitleaks step (người dùng tự làm để chụp ảnh git diff)
# git add → git commit → git push origin main → thành công
# 📸 Chụp: git log --oneline hiển thị commit trực tiếp vào main

## --- ZERO TRUST: branch protection block ---

# Thử push thẳng vào main trên repo ZEROTRUST
cd /tmp
git clone https://github.com/biniter1/ZEROTRUST /tmp/zt-demo 2>/dev/null || true
cd /tmp/zt-demo
echo "# test" >> README.md
git add README.md
git commit -m "test direct push to main"
git push origin main 2>&1
# Output: "remote: error: GH006: Protected branch update failed"
# 📸 Chụp: "Protected branch update failed"

# Tạo PR sửa ci.yml (xóa Gitleaks) → yêu cầu CODEOWNERS review
# 📸 Chụp: PR page yêu cầu review từ @biniter1 (CODEOWNERS)
# 📸 Chụp: Không thể self-approve (cần reviewer khác)

echo ""
echo "✅ Hoàn tất script. Đảm bảo đã chụp đủ ảnh cho từng kịch bản."
