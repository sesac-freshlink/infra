# infra - AI 작업 가이드

> FreshLink AWS 인프라 전체를 Terraform으로 관리한다. 서울 리전. 환경은 dev·prod 두 개이고, 두 환경 공용 `global` 묶음과 환경마다 `persistent`(유지)·`cluster`(지웠다 다시 만듦) 두 묶음으로 나눈다.

---

## 문서 참조

| 문서 | 내용 |
|------|------|
| `.github` 레포 `docs/aws-리소스-계획.md` | 환경·리소스·이름(2장), 묶음·state 키(6-4), 켜고 끄기(6-5), 비용(6-6), 모듈(8장). **구조 사실의 진실** |
| `README.md` | 소개, 루트·state 키(2장), 처음 만들기·apply 순서(4장), 팀원 계정·권한(5장), 이름 규칙(6장) |
| `envs/README.md` | 환경 루트별 할 일, 팀원 IAM 권한이 기대는 이름·태그 규칙 |
| `gitops/README.md` 3·4장 | dev·prod 차이, 배포·승격 |
| `.github` 레포 `docs/jina/할일-목록.md` | 작업 순서 (2 global·state·IAM, 3 dev persistent, 9 dev cluster, 10 OIDC, 15 prod, 16 승격) |
| `.github` 레포 `docs/기술스택과 선택이유.md` | 도구별 선택 이유 (관측성 3-5, 켜고 끄기 3-6, Cognito 3-7) |
| `.github` 레포 `docs/architecture/` | 구조도와 번호별 흐름 |
| `docs/troubleshooting/` | 장애·오류 해결 기록. 작성법은 `docs/troubleshooting/README.md` |
| `.github` 레포 `CONTRIBUTING.md` | 브랜치·커밋·PR 규칙 |
| `.github` 레포 `docs/ai-agents.md` | 인프라 에이전트 플러그인(`freshlink-infra`) 설치·사용법 (사람용) |

이 `CLAUDE.md`는 AI 작업 규칙만 담는다. 구조 사실은 `aws-리소스-계획.md`가 진실.

## 에이전트

인프라 에이전트 7개와 작업 순서는 `freshlink-infra` 플러그인에 있다 (`.github` 레포에서 배포). 새 기능 요청이면 `infra-pipeline` 스킬을 먼저 읽고 그 순서대로 서브에이전트를 쓴다. 플러그인이 설치되어 있지 않으면 사용자에게 `.github` 레포 `docs/ai-agents.md`의 설치 명령을 안내한다.

## Communication Style (Caveman Mode)
Respond like a caveman. No articles, no filler words, no pleasantries, no yapping. Short. Direct. Grunt-level brevity. Code speaks for itself. If asked for code, output ONLY code. Minimize token usage absolutely.

서브에이전트 산출물(`_workspace/*.md`)과 보고도 caveman 모드. 단, 레포에 커밋되는 것(README, docs/, 코드 주석, PR 본문)은 caveman 금지 — 기존 문서처럼 평이한 한국어 문장(`~한다` 체)으로 쓴다.

---

## 환경과 묶음

환경은 dev·prod 두 개다. 두 환경은 같은 모듈을 부르고 변수 파일(env, CIDR, 이름 접두사, `developers` 목록, 콜백 URL)만 다르다. VPC는 dev `10.0.0.0/16`, prod `10.1.0.0/16`.

| 루트 | state 키 | 리소스 | 주말·평소 |
|------|----------|--------|-----------|
| `global/` | `global` | 두 환경 공용: ECR 5개, GitHub OIDC 공급자, Terraform state 저장소, Budgets | 그대로 둔다 |
| `envs/<env>/persistent/` | `dev/persistent`, `prod/persistent` | VPC·서브넷, RDS, SSM 접속용 t4g.nano, Secrets Manager, S3·CloudFront, SQS, IAM, EventBridge Scheduler, Loki 로그 버킷, Cognito User Pool·트리거 Lambda | 그대로 둔다 (RDS·nano는 중지) |
| `envs/<env>/cluster/` | `dev/cluster`, `prod/cluster` | EKS, 노드 그룹, NAT, Helm(ArgoCD, AWS Load Balancer Controller, metrics-server, External Secrets Operator) | dev: 금 21:00 삭제, 월 08:40 생성, 평일 09:00~21:00만 켬. prod: 같은 워크플로를 `env=prod`로 쓰되 평소 꺼 두고 릴리스 확인·리허설·시연 날만 켬. prod 켜기 cron은 할 일 15에서 정할 때까지 넣지 않음 |

- 배포(이 레포 밖): 서비스 레포 `dev` 브랜치 push → ECR(태그 = 커밋 7자리) → gitops `envs/dev` → dev 클러스터. `main` 머지 → 다시 빌드하지 않고 같은 이미지 태그를 gitops `envs/prod`로 승격 → prod 클러스터. ECR과 서비스 CI가 맡는 GitHub OIDC Role은 두 환경 공용이다. `dev` 브랜치가 맡을 수 있는 Role에는 prod 쓰기 권한(prod 버킷 쓰기, prod terraform 실행 등)을 주지 않는다.
- 팀원 IAM 그룹 `freshlink-developers`는 dev 리소스만 쓴다. prod는 읽기 권한도 없다.
- 할 일 2에서 정한 것: state 키 `<루트>/terraform.tfstate`(예 `dev/persistent/terraform.tfstate`), 잠금은 S3 잠금 파일(`use_lockfile`, DynamoDB 없음), 버킷 이름은 레포 루트 `backend.hcl`(커밋 안 함)로 `-backend-config`에 넘김, state 버킷·Budgets·팀원 IAM은 `global`.
- 팀원 IAM 권한은 이름·태그로 dev를 가려낸다: 큐 `dev-*`, 비밀 `freshlink-dev-*`, Cognito·SSM 인스턴스는 태그 `Environment=dev`(provider `default_tags`), 로그 그룹 이름에 `freshlink-dev-`. 이 규칙을 어기는 이름을 만들지 않는다.
- 할 일 3에서 정한 것: 개발자별 큐는 `<env>-<아이디>-inventory-commands.fifo` 등(`QUEUE_PREFIX` `<env>-<아이디>-`), DLQ `...-dlq(.fifo)`, maxReceiveCount 3. 앱 DB 비밀 `freshlink-<env>-<서비스>-db`(JSON host·port·dbname·username·password), 스키마 `member`·`inventory`·`orders`, 사용자 `*_app`.
- 할 일 7에서 정한 것: IRSA Role은 cluster 묶음(`modules/irsa`, OIDC 공급자가 클러스터와 같이 생기고 지워진다). 켜고 끄기 워크플로 Role은 persistent 묶음 `freshlink-<env>-cluster-actions`(infra `main`만 신뢰, PowerUserAccess + `freshlink-<env>-*` IAM만). 클러스터·노드 그룹 이름은 persistent가 정하고 cluster가 remote state로 읽는다.
- 할 일 8·9에서 정한 것: ArgoCD root Application은 cluster 묶음이 `charts/argocd-root`로 등록하고, 계정마다 다른 값(ECR 주소, 서비스 IRSA Role ARN, `AWS_REGION`·`COGNITO_ISSUER_URI`·`COGNITO_CLIENT_ID`·`COGNITO_USER_POOL_ID`)을 넘긴다. gitops는 공개 레포라 이 값을 적지 않는다. root·서비스 Application에는 finalizer를 두지 않는다(금요일 삭제 때 ArgoCD 컨트롤러를 먼저 멈춘다).
- 정하지 않은 값은 지어내지 않는다: prod 켜는 방법 세부·prod 켜기 cron 여부(할 일 15).

---

## 기술 스택

| 구분 | 기술 |
|------|------|
| IaC | Terraform, AWS provider (ap-northeast-2, AZ 2a·2c) |
| 상태 | S3 `freshlink-tfstate-<계정ID 끝 4자리>`, 키 5개 `global`, `dev/persistent`, `dev/cluster`, `prod/persistent`, `prod/cluster` (+ `/terraform.tfstate`), S3 잠금 파일(`use_lockfile`) |
| 컴퓨팅 | 환경마다 EKS `freshlink-<env>-eks`, 관리형 노드 그룹 t3.large × 2 (최대 3) |
| 데이터·메시징 | 환경마다 RDS MySQL 8.4 db.t4g.small(`freshlink-<env>-mysql`)과 SSM 접속용 t4g.nano(public-a, 공인 IP, 인바운드 없음. NAT 없이 SSM에 닿게), SQS `<env>-inventory-commands.fifo`·`<env>-inventory-results`·DLQ 2개(dev는 개발자별 큐 추가) |
| 프론트 | 환경마다 S3 + CloudFront(OAC) + ACM(us-east-1) |
| 인증 | 환경마다 Cognito User Pool `freshlink-<env>-users` (그룹 OWNER·CUSTOMER, `custom:storeId`) |
| 비밀 | Secrets Manager + External Secrets Operator |
| 켜고 끄기 | EventBridge Scheduler (RDS·nano·노드 수, 환경별 `persistent`에 정의) + GitHub Actions (NAT·`cluster` 묶음, `env` 입력) |

---

## 핵심 규칙

```
⛔ terraform apply / destroy / import / state 명령 실행 금지 — 사람이 PR 머지 후 직접
⛔ aws CLI로 리소스 생성·수정·삭제 금지. 읽기도 사용자 확인 후
⛔ *.tfstate, *.tfvars(실값), *.tfplan, 키·비밀번호 커밋·출력 금지 (*.tfvars.example만 커밋)
✅ 의존 방향: envs/<env>/cluster → 같은 환경 envs/<env>/persistent, 각 환경 → global. 반대 방향 금지
✅ dev와 prod는 서로 참조하지 않는다. dev 루트가 prod state를 읽거나 그 반대 금지
✅ 다른 루트 값은 terraform_remote_state 또는 data source로 읽는다. ID·ARN 하드코딩 금지
✅ dev·prod는 같은 모듈을 부르고 차이는 변수 파일만. 모듈 안에 prod 전용 분기 금지
✅ dev cluster 묶음은 매주 금요일 21:00 destroy, 월요일 08:40 apply. prod cluster는 필요한 날만 켠다. destroy를 막거나 재생성에 사람 손이 필요한 것을 넣지 않는다
✅ 노드 그룹 desired_size는 lifecycle ignore_changes (스케줄러 값을 apply가 되돌리지 않게)
✅ 리소스 이름 freshlink-<env>-<이름> (예 freshlink-dev-mysql, freshlink-prod-eks). IRSA Role freshlink-<env>-<레포>-irsa, Cognito freshlink-<env>-users, 큐 <env>-inventory-commands.fifo
✅ 예외: ECR·Helm 릴리스·Deployment·ServiceAccount는 레포 이름 그대로. global 공용 리소스에는 env를 붙이지 않는다
✅ IAM 최소 권한, 자기 환경 리소스만 (IRSA·External Secrets·스케줄러). "*"는 근거를 주석으로
✅ 팀원 그룹 freshlink-developers는 dev 리소스만. prod 권한(읽기 포함)을 주지 않는다
✅ GitHub OIDC Role: dev 브랜치가 맡을 수 있는 Role에는 prod 쓰기 권한(prod 버킷 쓰기, prod terraform 실행 등)을 주지 않는다. 서비스 CI는 global `freshlink-ci-ecr-push` 하나(서비스 레포 5개 dev·main, ECR 푸시만, 할 일 8). sub는 `repo:<조직>/<레포>:...`와 ID가 붙은 `repo:<조직>@<ID>/<레포>@<ID>:...` 둘 다 받는다(StringLike)
✅ provider·모듈 버전 고정. 변수에 description·type
✅ 시간당 과금 리소스 추가·크기 변경은 비용 영향(aws-리소스-계획.md 6-6, dev·prod 합계)을 PR에 적는다
```

---

## 디렉토리 구조

옛 최상위 `persistent/`·`cluster/` 폴더는 할 일 2에서 지웠다. 새 코드는 아래 구조에만 만든다.

```
global/                     # 두 환경 공용 루트 (ECR, GitHub OIDC 공급자, state 저장소, Budgets, 팀원 IAM)
envs/
├── dev/
│   ├── persistent/         # dev 유지 묶음 루트
│   └── cluster/            # dev 클러스터 묶음 루트 (금요일 삭제, 월요일 생성)
└── prod/
    ├── persistent/         # prod 유지 묶음 루트 (dev와 같은 모듈, 변수만 다름)
    └── cluster/            # prod 클러스터 묶음 루트 (필요한 날만)
modules/{network,eks,irsa,rds,messaging,frontend,ecr,observability,scheduler,cognito,budget}
```

새 리소스를 어디에 넣을지: 두 환경이 같이 쓰면 `global`, 주말 동안 데이터·설정이 남아야 하면 `envs/<env>/persistent`, 시간당 과금이고 다시 만들어도 되면 `envs/<env>/cluster`.

---

## 다른 레포와의 연결

| 출력값 | 쓰는 곳 |
|--------|---------|
| IRSA Role ARN (환경별) | `gitops/envs/<env>/<svc>/values.yaml` ServiceAccount annotation |
| Loki 버킷·Role (환경별) | `gitops/platform/observability/loki.yaml` (환경별 값 위치는 할 일 17에서 정함) |
| User Pool ID, 앱 클라이언트 ID, issuer (환경별) | gitops `envs/<env>/`의 gateway·member-service values, frontend 빌드 환경 변수(dev·prod 따로) |
| 큐 이름 (환경별) | gitops `envs/<env>/<svc>/values.yaml` 환경 변수(`QUEUE_PREFIX`) |
| ECR 주소(`global`), 서비스 CI가 맡는 OIDC Role(공용) | `.github` 재사용 워크플로, 서비스 레포 CI |

출력값 이름이나 형식을 바꾸면 위 레포도 같이 고쳐야 한다. 다른 담당자 레포(frontend, 서비스)를 고쳐야 하면 작업 전 사용자에게 알린다.

---

## 브랜치·커밋

- `main` ← `feat/I-xx-설명` (dev 브랜치 없음). 환경은 브랜치가 아니라 폴더(`envs/dev`, `envs/prod`)로 나눈다. 서비스 레포의 `dev`→dev, `main`→prod 규칙은 이 레포에 해당하지 않는다. 예: `feat/I-10-sqs-queues`
- 커밋: `feat(I-10): SQS 큐 추가` 형식 (`.github` `CONTRIBUTING.md`)
- PR 본문 "확인 방법"에 `terraform plan` 결과 (`/plan-summary`로 요약). 합친 뒤 사람이 바뀐 루트에서 `apply`한다. 순서 `global` → `envs/<env>/persistent` → `envs/<env>/cluster`, dev 먼저
- 커밋·push·PR은 사용자가 요청할 때만

---

## 검증

```bash
terraform fmt -check -recursive
for root in global envs/dev/persistent envs/dev/cluster envs/prod/persistent envs/prod/cluster; do
  [ -d "$root" ] || continue   # 아직 없는 루트는 건너뛴다 (할 일 2·3·9·15에서 생긴다)
  terraform -chdir=$root init -backend=false && terraform -chdir=$root validate
done
tflint --recursive
trivy config .
```

`terraform plan`은 AWS 자격 증명이 필요하다. 실행 전 사용자에게 묻고, 어느 루트(state 키)인지 같이 적는다.
