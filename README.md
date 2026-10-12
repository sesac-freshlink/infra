# infra

> FreshLink가 올라가는 **AWS 인프라 전체를 Terraform 코드로** 관리한다. VPC부터 EKS, RDS, SQS, CloudFront까지 명령 한 번으로 만들고 지울 수 있다.

| 항목 | 내용 |
| --- | --- |
| 담당 | 김진아 |
| 관련 기능 ID | I-01 인프라 코드화, I-10 메시징 인프라, I-11 프론트엔드 배포, I-09 비용 알림 |
| 기술 | Terraform, AWS (ap-northeast-2 서울, AZ 2a·2c) |
| 상태 저장 | S3 `freshlink-tfstate-<계정ID 끝 4자리>` (묶음별 state 키 분리) |
| 브랜치 | `main` ← `feat/I-xx-설명` (dev 없음). PR에 `terraform plan` 결과를 붙이고, 합친 뒤 `apply` |

---

## 1. 무엇이 만들어지나

![FreshLink 아키텍처 구조도](docs/architecture/architecture.png)

> 번호별 흐름 설명: [docs/architecture](docs/architecture/README.md)

| 구분 | 리소스 | 크기 |
| --- | --- | --- |
| 컴퓨팅 | EKS `freshlink-eks` + 관리형 노드 그룹 | t3.large × 2 (최대 3) |
| DB | RDS MySQL 8.0 `freshlink-mysql` | db.t4g.small, gp3 20 GiB, 단일 AZ, 스키마 3개 |
| 메시징 | SQS `inventory-commands.fifo`, `inventory-results` + DLQ 2개 | 3번 실패 시 DLQ |
| 네트워크 | 서브넷 6개(퍼블릭·앱·DB × 2 AZ), NAT 1개, S3 Gateway 엔드포인트 | 앱 서브넷 /20 |
| 프론트 | S3(비공개) + CloudFront(OAC) + CloudFront Function + ACM(us-east-1) | |
| 이미지 | ECR 5개 (`gateway`, `member-service`, `inventory-service`, `order-service`, `logistics-simulator`) | |
| 보안 | IRSA Role (서비스별 SQS 권한, Loki 로그 버킷), 보안 그룹 alb-sg · node-sg · rds-sg | |
| 관측성 | S3 Loki 로그 버킷(14일 수명 주기), Loki IRSA Role, EBS CSI 드라이버(Prometheus 볼륨) | 스택 자체는 [gitops/platform/observability](https://github.com/sesac-freshlink/gitops/tree/main/platform/observability)에서 ArgoCD가 설치 |
| 비용 | AWS Budgets 알림 | |

관측성은 Prometheus(지표) + Loki·Alloy(로그) + Zipkin(추적) + Grafana(화면)다. Terraform은 **Loki가 쓸 S3 버킷과 IAM Role, Prometheus 볼륨용 EBS CSI 드라이버까지만** 만들고, 스택 설치는 ArgoCD가 한다. 선택 이유는 [docs/기술스택과 선택이유.md](docs/기술스택과%20선택이유.md) 3-5.

Bastion 서버는 두지 않는다. 노드는 SSM Session Manager로 접속한다.

## 2. 두 묶음으로 나눈 이유 (비용 약 400 → 150 USD)

| 묶음 | 리소스 | 주말에 |
| --- | --- | --- |
| `persistent/` | VPC·서브넷, RDS, ECR, S3·CloudFront, SQS, IAM, Budgets, Loki 로그 버킷, EventBridge Scheduler | 그대로 둔다 (RDS는 중지) |
| `cluster/` | EKS, 노드 그룹, NAT, Helm 설치물(ArgoCD, LB Controller, metrics-server) | 금요일에 삭제, 월요일에 생성 |

state 키를 따로 둬서(`persistent/terraform.tfstate`, `cluster/terraform.tfstate`) `cluster`만 지워도 DB 데이터와 이미지는 남는다. 매주 `destroy`·`apply`를 반복하는 것 자체가 **"코드만으로 인프라를 언제든 똑같이 다시 만들 수 있다"를 매주 검증**하는 일이 된다.

켜고 끄기는 성격에 따라 둘로 나눠 자동화한다. 이유는 [docs/기술스택과 선택이유.md](docs/기술스택과%20선택이유.md) 3-6.

| 시각 (한국) | 작업 | 도구 |
| --- | --- | --- |
| 월 09:20 | 클러스터 묶음 생성(노드 2대 포함) + RDS 시작 | GitHub Actions |
| 화~금 09:30 | NAT 생성 | GitHub Actions |
| 화~금 09:30 / 09:40 | RDS 시작 / 노드 그룹 desired 2 | EventBridge Scheduler |
| 월~목 17:30 | 노드 그룹 desired 0 (+ 월~금 RDS 중지) | EventBridge Scheduler |
| 월~목 17:40 | NAT 삭제 | GitHub Actions |
| 금 17:30 | 클러스터 묶음 삭제 | GitHub Actions |
| 매일 23:00 | 안전 끄기: RDS 중지·노드 0대 / NAT 삭제 | EventBridge Scheduler / GitHub Actions |

- **EventBridge Scheduler:** API 한 번이면 끝나는 RDS 중지·시작과 노드 0↔2대. Lambda 없이 스케줄러가 API를 직접 부르고, 시간대 `Asia/Seoul`로 정시에 돈다.
- **GitHub Actions:** Terraform이 필요한 NAT·클러스터 삭제·생성. 월요일은 노드 그룹이 apply 뒤에 생기므로 Actions가 한 번에 처리한다.

## 3. 폴더 구조

```
infra/
├── modules/
│   ├── network/     # VPC, 서브넷 6개(EKS 태그), IGW, NAT, 라우팅 3종, S3 엔드포인트
│   ├── eks/         # 클러스터, 노드 그룹, OIDC, 애드온
│   ├── irsa/        # 서비스별 IAM Role, LB Controller Role
│   ├── rds/         # MySQL, 서브넷 그룹, rds-sg
│   ├── messaging/   # SQS 4개, 재시도 정책
│   ├── frontend/    # S3, CloudFront, OAC, Function, ACM
│   ├── ecr/         # 리포지토리 5개, 보관 개수 정책
│   ├── observability/ # Loki 로그용 S3 버킷, 14일 수명 주기
│   ├── scheduler/   # EventBridge Scheduler: RDS 중지·시작, 노드 그룹 0↔2대
│   └── budget/      # Budgets 알림
├── persistent/      # 유지 묶음 루트 모듈
└── cluster/         # 클러스터 묶음 루트 모듈
```

## 할 일: 관측성 (I-03)

- [ ] `modules/observability`: Loki 로그 버킷 `freshlink-loki-logs-<계정ID 끝 4자리>`, 수명 주기 14일, 퍼블릭 차단 (persistent 묶음)
- [ ] `modules/irsa`: `freshlink-loki-irsa` (위 버킷 읽기·쓰기만), EBS CSI 드라이버 Role
- [ ] `cluster`: EBS CSI 드라이버 애드온, `gp3` StorageClass
- [ ] 만든 버킷 이름·Role ARN을 `gitops/platform/observability/loki.yaml`에 반영

## 할 일: 켜고 끄기 (I-09)

- [ ] `modules/scheduler` (persistent 묶음): `aws_scheduler_schedule` 일정 6개, 시간대 `Asia/Seoul`, universal target `aws-sdk:rds:startDBInstance`·`stopDBInstance`, `aws-sdk:eks:updateNodegroupConfig`
- [ ] 스케줄러 IAM Role: `freshlink-mysql`과 노드 그룹에 대한 `rds:StartDBInstance`·`rds:StopDBInstance`·`eks:UpdateNodegroupConfig`만
- [ ] `modules/eks`: 노드 그룹 `scaling_config[0].desired_size`를 `lifecycle { ignore_changes }`에 넣기 (apply가 스케줄러 값을 되돌리지 않게)
- [ ] GitHub Actions: 월 클러스터 생성, 화~금 NAT 생성, 월~목 NAT 삭제, 금 클러스터 삭제, 매일 23:00 NAT 정리, 수동 버튼(workflow_dispatch)

## 4. 사용법

> 아직 뼈대만 있는 상태다. 모듈은 1~2주 차에 채운다.

준비물: Terraform, AWS CLI (프로필 설정), kubectl, Helm

```bash
# 1) 유지 묶음 (처음 한 번)
cd persistent
terraform init
terraform plan
terraform apply

# 2) 클러스터 묶음 (월요일 아침 / 필요할 때)
cd ../cluster
terraform init
terraform apply

# 3) 금요일 저녁
terraform destroy   # cluster 디렉터리에서만
```

`terraform apply` 전에 두 AZ 모두 t3.large를 지원하는지 확인한다.

```bash
aws ec2 describe-instance-type-offerings --location-type availability-zone \
  --filters Name=instance-type,Values=t3.large --region ap-northeast-2
```

## 5. 이름 규칙

AWS 리소스에는 접두사 `freshlink-`를 붙인다. ECR·Helm 릴리스·Deployment 이름은 레포 이름과 똑같이 쓴다(`order-service`). IRSA Role은 `freshlink-<레포>-irsa`.

## 6. 기여

- `main` ← `feat/I-xx-설명` (예: `feat/I-10-sqs-queues`)
- PR 본문에 `terraform plan` 결과를 붙인다. 합친 뒤 `apply`한다.
- `.tfstate`, `.tfvars`(비밀값)는 절대 커밋하지 않는다.
