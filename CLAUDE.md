# infra - AI 작업 가이드

> FreshLink AWS 인프라 전체를 Terraform으로 관리한다. 서울 리전, `persistent/`(유지)와 `cluster/`(주말 삭제) 두 묶음.

---

## 문서 참조

| 문서 | 내용 |
|------|------|
| `README.md` | 리소스 표(1장), 두 묶음과 켜고 끄기 스케줄(2장), 폴더 구조(3장), 할 일 체크리스트, 사용법(4장), 이름 규칙(5장) |
| `.github` 레포 `docs/기술스택과 선택이유.md` | 도구별 선택 이유 (관측성 3-5, 켜고 끄기 3-6, Cognito 3-7) |
| `.github` 레포 `docs/architecture/` | 구조도와 번호별 흐름 |
| `docs/troubleshooting/` | 장애·오류 해결 기록. 작성법은 `docs/troubleshooting/README.md` |
| `.github` 레포 `CONTRIBUTING.md` | 브랜치·커밋·PR 규칙 |
| `.github` 레포 `docs/ai-agents.md` | 인프라 에이전트 플러그인(`freshlink-infra`) 설치·사용법 (사람용) |

이 `CLAUDE.md`는 AI 작업 규칙만 담는다. 위 문서와 겹치는 사실은 위 문서가 진실.

## 에이전트

인프라 에이전트 7개와 작업 순서는 `freshlink-infra` 플러그인에 있다 (`.github` 레포에서 배포). 새 기능 요청이면 `infra-pipeline` 스킬을 먼저 읽고 그 순서대로 서브에이전트를 쓴다. 플러그인이 설치되어 있지 않으면 사용자에게 `.github` 레포 `docs/ai-agents.md`의 설치 명령을 안내한다.

## Communication Style (Caveman Mode)
Respond like a caveman. No articles, no filler words, no pleasantries, no yapping. Short. Direct. Grunt-level brevity. Code speaks for itself. If asked for code, output ONLY code. Minimize token usage absolutely.

서브에이전트 산출물(`_workspace/*.md`)과 보고도 caveman 모드. 단, 레포에 커밋되는 것(README, docs/, 코드 주석, PR 본문)은 caveman 금지 — 기존 문서처럼 평이한 한국어 문장(`~한다` 체)으로 쓴다.

---

## 기술 스택

| 구분 | 기술 |
|------|------|
| IaC | Terraform, AWS provider (ap-northeast-2, AZ 2a·2c) |
| 상태 | S3 `freshlink-tfstate-<계정ID 끝 4자리>`, 키 `persistent/terraform.tfstate`, `cluster/terraform.tfstate` |
| 컴퓨팅 | EKS `freshlink-eks`, 관리형 노드 그룹 t3.large × 2 (최대 3) |
| 데이터·메시징 | RDS MySQL 8.0, SQS FIFO + 표준 + DLQ |
| 프론트 | S3 + CloudFront(OAC) + ACM(us-east-1) |
| 인증 | Cognito User Pool `freshlink-users` (그룹 OWNER·CUSTOMER, `custom:storeId`) |
| 켜고 끄기 | EventBridge Scheduler (RDS·노드 수) + GitHub Actions (NAT·cluster 묶음) |

---

## 핵심 규칙

```
⛔ terraform apply / destroy / import / state 명령 실행 금지 — 사람이 PR 머지 후 직접
⛔ aws CLI로 리소스 생성·수정·삭제 금지. 읽기도 사용자 확인 후
⛔ *.tfstate, *.tfvars(실값), *.tfplan, 키·비밀번호 커밋·출력 금지 (*.tfvars.example만 커밋)
✅ persistent ← cluster 방향만 의존. persistent는 cluster를 절대 참조하지 않는다
✅ cluster가 persistent 값을 쓸 때 terraform_remote_state 또는 data source. ID·ARN 하드코딩 금지
✅ cluster 묶음은 매주 금요일 destroy, 월요일 apply. destroy를 막거나 재생성에 사람 손이 필요한 것을 넣지 않는다
✅ 노드 그룹 desired_size는 lifecycle ignore_changes (스케줄러 값을 apply가 되돌리지 않게)
✅ 리소스 이름 freshlink- 접두사. IRSA Role은 freshlink-<레포>-irsa
✅ IAM 최소 권한. "*"는 근거를 주석으로
✅ provider·모듈 버전 고정. 변수에 description·type
✅ 시간당 과금 리소스 추가·크기 변경은 비용 영향(README 2장)을 PR에 적는다
```

---

## 디렉토리 구조

README 3장이 진실. 요약:

```
modules/{network,eks,irsa,rds,messaging,frontend,ecr,observability,scheduler,cognito,budget}
persistent/   # 유지 묶음 루트 (VPC, RDS, ECR, S3·CloudFront, SQS, IAM, Budgets, Scheduler, Cognito)
cluster/      # 클러스터 묶음 루트 (EKS, 노드 그룹, NAT, Helm 설치물: ArgoCD, LB Controller, metrics-server)
```

새 리소스를 어느 묶음에 넣을지 기준: 주말 동안 데이터·설정이 남아야 하면 `persistent`, 시간당 과금이고 다시 만들어도 되면 `cluster`.

---

## 다른 레포와의 연결

| 출력값 | 쓰는 곳 |
|--------|---------|
| IRSA Role ARN | `gitops/services/<svc>/values.yaml` ServiceAccount annotation |
| Loki 버킷·Role | `gitops/platform/observability/loki.yaml` |
| User Pool ID, 앱 클라이언트 ID, issuer | gitops의 gateway·member-service values, frontend 빌드 환경 변수 |
| ECR 주소, OIDC Role | `.github` 재사용 워크플로, 서비스 레포 CI |

출력값 이름이나 형식을 바꾸면 위 레포도 같이 고쳐야 한다. 다른 담당자 레포(frontend, 서비스)를 고쳐야 하면 작업 전 사용자에게 알린다.

---

## 브랜치·커밋

- `main` ← `feat/I-xx-설명` (dev 없음). 예: `feat/I-10-sqs-queues`
- 커밋: `feat(I-10): SQS 큐 추가` 형식 (`.github` `CONTRIBUTING.md`)
- PR 본문 "확인 방법"에 `terraform plan` 결과 (`/plan-summary`로 요약). 합친 뒤 사람이 `apply`
- 커밋·push·PR은 사용자가 요청할 때만

---

## 검증

```bash
terraform fmt -check -recursive
terraform -chdir=persistent init -backend=false && terraform -chdir=persistent validate
terraform -chdir=cluster init -backend=false && terraform -chdir=cluster validate
tflint --recursive
trivy config .
```

`terraform plan`은 AWS 자격 증명이 필요하다. 실행 전 사용자에게 묻는다.
