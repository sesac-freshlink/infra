# envs

환경별 루트 모듈. `dev/persistent`는 할 일 3에서 채웠다(README 4-4). 나머지는 아래 할 일에서 채운다.

| 루트 | state 키 | 채우는 할 일 |
| --- | --- | --- |
| `dev/persistent` | `dev/persistent/terraform.tfstate` | 3 (RDS·SQS·Secrets), 그 뒤 Cognito·프론트·관측성 |
| `dev/cluster` | `dev/cluster/terraform.tfstate` | 7 (EKS·NAT·IRSA·Helm, README 4-6) |
| `prod/persistent` | `prod/persistent/terraform.tfstate` | 14 (dev와 같은 모듈, README 4-12) |
| `prod/cluster` | `prod/cluster/terraform.tfstate` | 14 (README 4-12) |

리소스 이름 규칙(팀원 IAM 권한이 이 이름·태그로 dev를 가려낸다):

- SQS 큐: `<env>-...` (예 `dev-inventory-commands.fifo`)
- Secrets Manager 비밀: `freshlink-<env>-...` (예 `freshlink-dev-order-db`)
- Cognito User Pool, SSM 접속용 인스턴스: provider `default_tags`의 `Environment` 태그
- CloudWatch 로그 그룹: 이름에 `freshlink-<env>-` 포함 (예 `/aws/lambda/freshlink-dev-post-confirmation`)
