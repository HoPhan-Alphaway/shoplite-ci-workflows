# shoplite-ci-workflows

Reusable GitHub Actions workflows dùng chung cho mọi repo ShopLite. Mỗi repo service chỉ có 1 file `.github/workflows/ci.yml` ~40 dòng gọi các workflow ở đây → sửa pipeline 1 chỗ, áp dụng cho cả 5 repo.

| Workflow | Làm gì |
|---|---|
| `java-ci.yml` | `./mvnw verify` (unit + Testcontainers integration test, Docker có sẵn trên runner) |
| `node-ci.yml` | `npm ci` → `npm run lint` (tsc) → `npm run build` |
| `docker-build-push.yml` | Build image → **Trivy** scan (fail nếu có CVE CRITICAL đã có bản vá) → push `ghcr.io/<owner>/<repo>:<git-sha>` + `:main`, kèm SBOM + provenance |
| `update-gitops.yml` | Sửa `image.tag` trong `shoplite-gitops/apps/<svc>/values-dev.yaml` rồi commit → ArgoCD tự rollout |

Promote dev → prod nằm ở `shoplite-gitops/.github/workflows/promote.yml` (chạy tay, mở PR).

## Luồng

```
PR mở        ─► test ─► build + Trivy (không push)           → check bắt buộc để merge
merge main   ─► test ─► build + Trivy ─► push GHCR ─► commit tag vào gitops (dev)
                                                       │
                                     ArgoCD thấy commit ─► rollout shop-dev
Actions › promote (gitops) ─► PR copy tag dev → prod ─► merge = duyệt ─► rollout shop-prod
```

## Bảo mật / thực hành chuẩn

- **Pin action theo commit SHA**, không theo tag (`@v4`). Tag là mutable: tháng 3/2026 kẻ tấn công đã force-push 76/77 tag của `aquasecurity/trivy-action` sang commit độc hại để đánh cắp secret CI. Comment `# vX.Y.Z` cạnh SHA để người đọc biết version; nâng cấp bằng Dependabot/Renovate.
- **Version workflow dùng chung**: caller gọi `@v1`. Thay đổi phá vỡ → tag `v2`, repo nào sẵn sàng thì đổi.
- **Quyền tối thiểu**: mặc định `contents: read`; chỉ job image có `packages: write`. Push GHCR dùng `GITHUB_TOKEN` (hết hạn khi job xong), không PAT.
- **Ghi vào repo gitops bằng deploy key**: SSH key chỉ có quyền ghi đúng 1 repo `shoplite-gitops`. Private key lưu **1 lần** dưới dạng **organization secret** `GITOPS_DEPLOY_KEY` (visibility = chỉ 5 repo service), repo service nhận qua `secrets: inherit`. Hẹp hơn PAT (PAT có quyền trên mọi repo của user). Phương án chuẩn hơn cho team lớn: GitHub App (token ngắn hạn, audit theo app).
- `secrets: inherit` không lưu gì cả — nó chỉ chuyển tiếp các secret mà repo caller nhìn thấy (secret của repo + org secret được chia cho repo đó) sang reusable workflow. Account cá nhân không có secret cấp account → muốn "khai báo 1 lần" phải dùng organization.

## Setup lần đầu / rotate key

```bash
gh auth refresh -h github.com -s admin:org   # cần quyền quản trị org
bash scripts/setup-org.sh                    # chạy lại bất cứ lúc nào để rotate key
```

Thêm repo service mới: thêm tên repo vào `SERVICES` trong script rồi chạy lại (hoặc Org Settings › Secrets › GITOPS_DEPLOY_KEY › thêm repo).
- PR từ fork không đọc được secret → không bao giờ chạy được `update-gitops`.

## Phát hành version mới cho workflow

```bash
git tag -f v1 && git push -f origin v1      # thay đổi tương thích
git tag v2 && git push origin v2             # thay đổi phá vỡ
```
