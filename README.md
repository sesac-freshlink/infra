# infra

> FreshLink가 올라가는 **AWS 인프라 전체를 Terraform 코드로** 관리한다. VPC부터 EKS, RDS, SQS, CloudFront까지 명령 한 번으로 만들고 지울 수 있다.

| 항목 | 내용 |
| --- | --- |
| 담당 | 김진아 |
| 관련 기능 ID | I-01 인프라 코드화, I-10 메시징 인프라, I-11 프론트엔드 배포, I-09 비용 알림 |
| 기술 | Terraform 1.11 이상, AWS provider 6.x (ap-northeast-2 서울, AZ 2a·2c) |
| 환경 | dev, prod 두 개. 같은 모듈을 부르고 변수만 다르다 |
| 상태 저장 | S3 `freshlink-tfstate-<계정ID 끝 4자리>`, 루트마다 키 하나(5개), S3 잠금 파일(`use_lockfile`)로 잠금 |
| 브랜치 | `main` ← `feat/I-xx-설명` (dev 브랜치 없음, 환경은 폴더로 나눈다) |

설계 근거와 비용은 `.github` 레포 [`docs/aws-리소스-계획.md`](https://github.com/sesac-freshlink/.github/blob/main/docs/aws-%EB%A6%AC%EC%86%8C%EC%8A%A4-%EA%B3%84%ED%9A%8D.md)에 있다. 이 README와 다르면 그 문서를 따른다.

---

## 1. 무엇이 만들어지나

![FreshLink 아키텍처 구조도](https://raw.githubusercontent.com/sesac-freshlink/.github/main/docs/architecture/architecture.png)

> 번호별 흐름 설명: [.github 레포 docs/architecture](https://github.com/sesac-freshlink/.github/blob/main/docs/architecture/README.md)

두 환경이 같이 쓰는 것 (`global/`, 만들어 둠)

| 구분 | 리소스 | 비고 |
| --- | --- | --- |
| state | S3 `freshlink-tfstate-<계정ID 끝 4자리>` | 버전 관리, 암호화, 퍼블릭 차단, HTTPS만, 지난 버전 90일 보관, `prevent_destroy` |
| 비용 | AWS Budgets `freshlink-monthly`, 비용 이상 탐지 `freshlink-services` | 10월 160 + 11월 200 = 360 USD. 50·80·100%와 예측 100% 초과 시 메일. 크레딧은 빼고 실제 사용 금액으로 본다 |
| 이미지 | ECR 5개 (`gateway`, `member-service`, `inventory-service`, `order-service`, `logistics-simulator`) | 태그 덮어쓰기 금지, push 때 스캔, 최근 30개 보관 |
| CI 인증 | GitHub OIDC 공급자 | 이 공급자를 믿는 Role은 할 일 10에서 만든다 |
| 팀원 | IAM 그룹 `freshlink-developers`, 사용자 `freshlink-taewoo`·`freshlink-kyungwoo`·`freshlink-younghoon` | MFA 필수, dev 리소스만 (5장) |

환경마다 하나씩 있는 것 (`envs/<env>/`, 할 일 3·9·15에서 채운다)

| 구분 | 리소스 | 크기 |
| --- | --- | --- |
| 컴퓨팅 | EKS `freshlink-<env>-eks` + 관리형 노드 그룹 | t3.large × 2 (최대 3) |
| DB | RDS MySQL 8.0 `freshlink-<env>-mysql` + SSM 접속용 t4g.nano | db.t4g.small, gp3 20 GiB, 단일 AZ, 스키마 3개 |
| 메시징 | SQS `<env>-inventory-commands.fifo`, `<env>-inventory-results` + DLQ 2개 (dev는 개발자별 큐 추가) | 3번 실패 시 DLQ |
| 네트워크 | VPC(dev `10.0.0.0/16`, prod `10.1.0.0/16`), 서브넷 6개, NAT 1개, S3 Gateway 엔드포인트 | 앱 서브넷 /20 |
| 프론트 | S3(비공개) + CloudFront(OAC) + CloudFront Function + ACM(us-east-1) | |
| 보안 | IRSA Role, Secrets Manager + External Secrets Operator, 보안 그룹 | |
| 인증 | Cognito User Pool `freshlink-<env>-users` + 가입 확인 트리거 Lambda | |
| 관측성 | S3 Loki 로그 버킷(14일), Loki IRSA Role, EBS CSI 드라이버 | 스택은 [gitops/platform/observability](https://github.com/sesac-freshlink/gitops/tree/main/platform/observability)에서 ArgoCD가 설치 |

Bastion 서버는 두지 않는다. 노드와 RDS 접속은 SSM Session Manager로 한다.

## 2. 루트 다섯 개와 state 키

| 루트 | state 키 | 리소스 | 주말·평소 |
| --- | --- | --- | --- |
| `global/` | `global/terraform.tfstate` | state 버킷, Budgets, ECR, GitHub OIDC 공급자, 팀원 IAM | 그대로 둔다 |
| `envs/dev/persistent/` | `dev/persistent/terraform.tfstate` | VPC, RDS, nano, Secrets, S3·CloudFront, SQS, Scheduler, Loki 버킷, Cognito | 그대로 둔다 (RDS·nano는 중지) |
| `envs/dev/cluster/` | `dev/cluster/terraform.tfstate` | EKS, 노드 그룹, NAT, Helm 설치물 | 금 21:00 삭제, 월 08:40 생성, 평일 09:00~21:00만 켬 |
| `envs/prod/persistent/` | `prod/persistent/terraform.tfstate` | dev와 같은 모듈, 변수만 다름 | 그대로 둔다 |
| `envs/prod/cluster/` | `prod/cluster/terraform.tfstate` | dev와 같은 모듈 | 평소 꺼 두고 릴리스 확인·리허설·시연 날만 켬 |

의존 방향은 `envs/<env>/cluster` → `envs/<env>/persistent` → `global` 한쪽뿐이다. dev와 prod는 서로를 참조하지 않는다. `cluster`만 지워도 DB 데이터, 이미지, 회원 계정은 남는다. 매주 `destroy`·`apply`를 반복하는 것 자체가 **"코드만으로 인프라를 언제든 똑같이 다시 만들 수 있다"를 매주 검증**하는 일이 된다.

켜고 끄기 (dev, 한국 시각)

| 시각 | 작업 | 도구 |
| --- | --- | --- |
| 월 08:40 | 클러스터 묶음 생성(노드 2대 포함) + RDS 시작 | GitHub Actions |
| 화~금 09:00 | NAT 생성 | GitHub Actions |
| 화~금 09:00 / 09:10 | RDS·nano 시작 / 노드 그룹 desired 2 | EventBridge Scheduler |
| 월~목 21:00 | 노드 그룹 desired 0 (+ 월~금 RDS·nano 중지) | EventBridge Scheduler |
| 월~목 21:10 | NAT 삭제 | GitHub Actions |
| 금 21:00 | 클러스터 묶음 삭제 | GitHub Actions |
| 매일 23:00 | 안전 끄기: RDS 중지·노드 0대 / NAT 삭제 | EventBridge Scheduler / GitHub Actions |

이유는 [기술스택과 선택이유.md](https://github.com/sesac-freshlink/.github/blob/main/docs/%EA%B8%B0%EC%88%A0%EC%8A%A4%ED%83%9D%EA%B3%BC%20%EC%84%A0%ED%83%9D%EC%9D%B4%EC%9C%A0.md) 3-6.

## 3. 폴더 구조

```
infra/
├── backend.hcl.example  # state 버킷 이름. backend.hcl로 복사해서 쓴다 (커밋 안 함)
├── global/              # 두 환경 공용 루트 (state 버킷, Budgets, ECR, OIDC, 팀원 IAM)
├── envs/
│   ├── dev/{persistent,cluster}/
│   └── prod/{persistent,cluster}/
├── modules/
│   ├── budget/          # Budgets, 비용 이상 탐지, 알림 시험용 예산
│   ├── ecr/             # 리포지토리, 보관 개수 정책
│   ├── network/  eks/  irsa/  rds/  messaging/  frontend/
│   └── observability/  scheduler/  cognito/
└── scripts/aws-mfa.*    # 팀원 PC에서 MFA 임시 자격 받기
```

새 리소스 위치: 두 환경이 같이 쓰면 `global`, 주말 동안 남아야 하면 `envs/<env>/persistent`, 시간당 과금이고 다시 만들어도 되면 `envs/<env>/cluster`.

## 할 일: 관측성 (I-03)

- [ ] `modules/observability`: Loki 로그 버킷 `freshlink-<env>-loki-logs-<계정ID 끝 4자리>`, 수명 주기 14일, 퍼블릭 차단 (`envs/<env>/persistent`)
- [ ] `modules/irsa`: `freshlink-<env>-loki-irsa` (위 버킷 읽기·쓰기만), EBS CSI 드라이버 Role
- [ ] `envs/<env>/cluster`: EBS CSI 드라이버 애드온, `gp3` StorageClass
- [ ] 만든 버킷 이름·Role ARN을 `gitops/platform/observability/loki.yaml`에 반영

## 할 일: 켜고 끄기 (I-09)

- [ ] `modules/scheduler` (`envs/<env>/persistent`): `aws_scheduler_schedule` 일정 6개, 시간대 `Asia/Seoul`, universal target `aws-sdk:rds:startDBInstance`·`stopDBInstance`, `aws-sdk:eks:updateNodegroupConfig`
- [ ] 스케줄러 IAM Role: `freshlink-<env>-mysql`과 노드 그룹에 대한 `rds:StartDBInstance`·`rds:StopDBInstance`·`eks:UpdateNodegroupConfig`만
- [ ] `modules/eks`: 노드 그룹 `scaling_config[0].desired_size`를 `lifecycle { ignore_changes }`에 넣기 (apply가 스케줄러 값을 되돌리지 않게)
- [ ] GitHub Actions: 월 클러스터 생성, 화~금 NAT 생성, 월~목 NAT 삭제, 금 클러스터 삭제, 매일 23:00 NAT 정리, 수동 버튼(workflow_dispatch)

## 할 일: 인증 (Cognito, C-01·C-02·C-03)

- [ ] `modules/cognito` (`envs/<env>/persistent`): `aws_cognito_user_pool` `freshlink-<env>-users` (이메일을 아이디로, 이메일 인증), 사용자 속성 `custom:storeId`
- [ ] `aws_cognito_user_group` `OWNER`, `CUSTOMER`
- [ ] `aws_cognito_user_pool_client` 브라우저용 1개: 시크릿 없음, `ALLOW_USER_SRP_AUTH`·`ALLOW_REFRESH_TOKEN_AUTH`, ID·액세스 토큰 1시간·리프레시 1일, `custom:storeId`는 읽기 속성에만 넣고 쓰기 속성에서 뺀다 (프론트는 ID 토큰을 API에 보낸다)
- [ ] 가입 확인 트리거 Lambda (Python, Post Confirmation): `confirmSignUp`의 `clientMetadata.role`이 OWNER/CUSTOMER면 그 그룹, 아니면 CUSTOMER에 넣는다. 실행 Role은 `cognito-idp:AdminAddUserToGroup`만
- [ ] `modules/irsa`: member-service Role에 이 User Pool의 `cognito-idp:AdminUpdateUserAttributes`만 추가
- [ ] 출력값(User Pool ID, 앱 클라이언트 ID, issuer URI)을 `gitops`의 gateway·member-service values와 frontend 빌드 환경 변수(`VITE_COGNITO_USER_POOL_ID`, `VITE_COGNITO_CLIENT_ID`)에 반영
- [ ] 더미 점주 3명 시드 스크립트 (`admin-create-user` + 그룹 + `custom:storeId`, E-12)

## 4. 사용법

준비물: Terraform 1.11 이상, AWS CLI, kubectl, Helm. 관리자 자격(김진아)으로 실행한다.

### 4-1. 맨 처음 한 번: `global` 만들기

state 버킷이 아직 없으므로 처음에는 로컬 state로 만들고, 버킷이 생기면 state를 버킷으로 옮긴다. **Budgets를 가장 먼저** 만든다.

```bash
cd global
cp terraform.tfvars.example terraform.tfvars        # 메일 3개(김진아, 이태우, 김경우) 넣기

# 1) 로컬 state로 시작 (*_override.tf는 .gitignore에 있어 커밋되지 않는다)
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
terraform init

# 2) 예산·이상 탐지 먼저
terraform apply -target=module.budget

# 3) 나머지 전부 (state 버킷, ECR, OIDC, 팀원 IAM)
terraform apply
terraform output tfstate_bucket                     # 버킷 이름 확인

# 4) state를 S3로 옮기기
cd ..
cp backend.hcl.example backend.hcl                  # bucket 값을 위 출력값으로 고친다
rm global/backend_override.tf
cd global
terraform init -migrate-state -backend-config=../backend.hcl   # "yes"
rm -f terraform.tfstate terraform.tfstate.backup    # S3에 올라간 것을 확인한 뒤 로컬 사본 삭제
```

비용 이상 탐지 모니터를 만들 때 `LimitExceeded`가 나면 계정에 AWS가 자동으로 만든 서비스 모니터(`Default-Services-Monitor`)가 이미 있는 것이다. `aws ce get-anomaly-monitors`로 ARN을 찾아 콘솔에서 지우고 다시 apply한다.

`.terraform.lock.hcl`은 처음 `init`한 PC에서 생기며 커밋한다. 다른 OS에서도 쓰려면 `terraform providers lock -platform=windows_amd64 -platform=linux_amd64`로 해시를 같이 넣는다.

### 4-2. 그 다음부터 (모든 루트)

```bash
terraform -chdir=global init -backend-config=../backend.hcl
terraform -chdir=envs/dev/persistent init -backend-config=../../../backend.hcl
terraform -chdir=envs/dev/persistent plan
```

apply 순서는 `global` → `envs/<env>/persistent` → `envs/<env>/cluster`, dev 먼저다. `cluster`는 `destroy`해도 되지만 `global`과 `persistent`는 지우지 않는다.

`envs/<env>/cluster`를 처음 만들기 전에 두 AZ 모두 t3.large를 지원하는지 확인한다.

```bash
aws ec2 describe-instance-type-offerings --location-type availability-zone \
  --filters Name=instance-type,Values=t3.large --region ap-northeast-2
```

### 4-3. 예산 알림 시험

```bash
# terraform.tfvars에서 budget_test_alert = true
terraform -chdir=global apply      # freshlink-alert-test 예산(1 USD, 1% 초과 시 메일) 생성
```

이번 달 실제 사용 금액이 0.01 USD를 넘으면 세 사람에게 메일이 간다. Budgets는 하루 몇 번만 평가하므로 메일까지 몇 시간 걸릴 수 있다. 세 사람이 메일을 받으면 `budget_test_alert = false`로 돌리고 다시 apply해서 시험 예산을 지운다.

## 5. 팀원 계정 (그룹 `freshlink-developers`)

| 사용자 | 팀원 |
| --- | --- |
| `freshlink-taewoo` | 이태우 |
| `freshlink-kyungwoo` | 김경우 |
| `freshlink-younghoon` | 문영훈 |

권한은 dev 리소스만이다. prod는 읽기 권한도 없다(허용 문장이 없어 기본 거부).

| 허용 | 범위 |
| --- | --- |
| SQS 보내기·받기·지우기·속성 조회·비우기·DLQ 재처리 | 이름이 `dev-`로 시작하는 큐 |
| Secrets Manager 값 읽기 | 이름이 `freshlink-dev-`로 시작하는 비밀 |
| Cognito User Pool·사용자·그룹 조회 | 태그 `Environment=dev`인 User Pool |
| SSM 포트 포워딩 세션 시작·종료 | 태그 `Environment=dev`인 인스턴스. 셸 세션은 안 된다 |
| CloudWatch Logs 읽기·Logs Insights | 이름에 `freshlink-dev-`가 들어간 로그 그룹 |
| 본인 비밀번호·액세스 키·MFA 관리 | 본인 사용자만 |

CloudWatch 지표(`GetMetricData`)와 큐·로그 그룹·User Pool 목록(`List*`)은 리소스 단위로 좁힐 수 없어 prod까지 보이게 되므로 주지 않았다. 지표와 로그는 dev Grafana로 본다. 이름과 태그 규칙은 [`envs/README.md`](envs/README.md)에 있다.

### 5-1. 계정 전달 (김진아)

콘솔 비밀번호와 액세스 키는 Terraform으로 만들지 않는다(state에 비밀이 남지 않게). `global` apply 뒤 사람마다 한 번 실행한다.

```bash
aws iam create-login-profile --user-name freshlink-taewoo \
  --password '<임시 비밀번호>' --password-reset-required
```

계정 ID(로그인 주소), 사용자 이름, 임시 비밀번호는 **채팅이나 레포에 붙여 넣지 않고 직접 전달**한다.

### 5-2. 처음 로그인 (팀원)

1. `https://<계정ID>.signin.aws.amazon.com/console`에 로그인하고 새 비밀번호로 바꾼다.
2. 오른쪽 위 이름 → 보안 자격 증명 → MFA 디바이스 할당(인증 앱). **이 전에는 다른 것이 모두 거부된다.**
3. 로그아웃 후 MFA로 다시 로그인하고, 같은 화면에서 액세스 키를 만든다(용도: CLI).
4. PC에서 키를 등록하고 MFA 임시 자격을 받는다. 임시 자격은 12시간 유효하니 아침마다 다시 받는다.

```powershell
aws configure --profile freshlink                       # 액세스 키, 리전 ap-northeast-2
powershell -ExecutionPolicy Bypass -File scripts\aws-mfa.ps1   # Git Bash·WSL은 ./scripts/aws-mfa.sh
aws sts get-caller-identity --profile freshlink-dev
```

IntelliJ나 Gradle로 서비스를 띄울 때는 환경 변수 `AWS_PROFILE=freshlink-dev`를 준다.

### 5-3. 확인 (할 일 2 완료 기준)

```bash
aws sts get-caller-identity --profile freshlink-dev                                   # 성공해야 한다
aws sqs get-queue-url --queue-name prod-inventory-results --profile freshlink-dev     # AccessDenied여야 한다
aws sqs get-queue-url --queue-name dev-inventory-results --profile freshlink-dev      # 할 일 3 이후 성공
```

prod 큐가 아직 없어도 권한 검사가 먼저라 `AccessDenied`가 나온다(`QueueDoesNotExist`가 나오면 권한이 새는 것이다).

### 5-4. 팀원이 빠질 때

`global/variables.tf`의 `developers`에서 지우고 apply한다. 액세스 키·MFA·로그인 프로필까지 같이 지워진다.

## 6. 이름 규칙

- 환경 리소스: `freshlink-<env>-<이름>` (예 `freshlink-dev-mysql`). IRSA Role `freshlink-<env>-<레포>-irsa`, 큐 `<env>-inventory-commands.fifo`, 비밀 `freshlink-<env>-...`
- 공용(`global`) 리소스에는 env를 붙이지 않는다. ECR·Helm 릴리스·Deployment 이름은 레포 이름 그대로(`order-service`)
- 모든 리소스에 provider `default_tags`로 `Project`, `Environment`, `ManagedBy`, `StateKey` 태그가 붙는다

## 7. 기여

- `main` ← `feat/I-xx-설명` (예: `feat/I-10-sqs-queues`)
- PR 본문에 `terraform plan` 결과를 붙인다. 합친 뒤 바뀐 루트에서 `apply`한다.
- `.tfstate`, `.tfvars`(실값), `backend.hcl`은 커밋하지 않는다. `*.example`만 커밋한다.
- 검증: `terraform fmt -check -recursive`, 루트마다 `terraform init -backend=false && terraform validate`
