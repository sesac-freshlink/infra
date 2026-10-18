# dev-cluster 워크플로가 취소된 뒤 모든 작업이 state 잠금에서 멈춤

- 날짜: 2026-10-17
- 작성: catapillar0505
- 관련: https://github.com/sesac-freshlink/infra/actions/runs/39015386813 (취소된 destroy), https://github.com/sesac-freshlink/infra/actions/runs/39015445211 (다음 destroy), https://github.com/sesac-freshlink/infra/actions/runs/39050768055 (23:00 nat-off)

## 증상

토요일 수동 `destroy`를 도중에 취소하고 다시 돌린 뒤로 dev-cluster 워크플로가 모두 실패한다.

다음 `destroy`는 '지우기 전 정리' 단계에서 kubectl이 들어가지 못했다.

```text
E1017 07:56:48.614860    2425 memcache.go:381] "Couldn't get current server API group list" err="the server has asked for the client to provide credentials"
error: You must be logged in to the server (the server has asked for the client to provide credentials)
```

매일 23:00 `nat-off`는 terraform apply가 잠금을 얻지 못했다.

```text
Error: Error acquiring the state lock

Error message: operation error S3: PutObject, https response error
StatusCode: 412, ...
api error PreconditionFailed: At least one of the pre-conditions you
specified did not hold
Lock Info:
  ID:        2cb54a00-5295-c880-e7cb-7f66acbc2138
  Path:      freshlink-tfstate-<끝 4자리>/dev/cluster/terraform.tfstate
  Operation: OperationTypeApply
  Who:       runner@runnervm8k3b6
  Version:   1.16.6
  Created:   2026-10-17 07:55:34.136283705 +0000 UTC
```

## 환경·발생 조건

- 묶음/위치: `envs/dev/cluster`, `.github/workflows/dev-cluster.yml`
- 도구 버전: Terraform 1.16.6, S3 잠금 파일(`use_lockfile`)
- 어떤 작업 중이었나: 토요일 `destroy` 수동 실행 중 `terraform destroy`가 노드 그룹을 지우던 때 작업을 취소했다.

## 원인

1. 취소된 작업의 terraform이 노드 그룹 삭제를 기다리다 강제 종료돼 S3 잠금 파일(`dev/cluster/terraform.tfstate.tflock`)을 지우지 못했다. 잠금의 `Created`(07:55:34)가 취소된 작업의 destroy 시작 시각과 같다. 이후 terraform을 부르는 작업은 모두 412로 멈춘다.
2. 취소 전에 destroy가 access entry 두 개(워크플로 Role, `sesac-c2`)와 IRSA Role·OIDC 공급자·애드온 2개를 이미 지웠다. 클러스터는 남아 있어 `클러스터가 있는지`는 `true`인데 kubectl은 인증을 받지 못하고, '지우기 전 정리'가 `set -e`로 실패했다.
3. 반쯤 지워진 클러스터에서 `nat-on`·`nat-off`가 전체 apply를 하면 지워진 access entry·IRSA·애드온·노드 그룹·Helm까지 되살린다. 잠금 때문에 실제로는 일어나지 않았다.

## 해결

1. 워크플로에 action `unlock`(입력 `lock_id`)을 더했다. 지금 잠금의 ID가 입력과 같을 때만 `terraform force-unlock`을 한다.
2. dev-cluster 워크플로 → **Run workflow** → action `unlock`, lock_id `2cb54a00-5295-c880-e7cb-7f66acbc2138`.
3. 다시 **Run workflow** → action `destroy`. '지우기 전 정리'는 경고를 남기고 건너뛰고, 남은 노드 그룹·클러스터·NAT를 지운 뒤 '남은 리소스 확인' 표가 모두 "없음"인지 본다.

```bash
gh workflow run dev-cluster.yml --repo sesac-freshlink/infra -f action=unlock -f lock_id=2cb54a00-5295-c880-e7cb-7f66acbc2138
gh workflow run dev-cluster.yml --repo sesac-freshlink/infra -f action=destroy
```

## 재발 방지

- 마지막 단계 '끊긴 작업의 잠금 풀기'(`if: cancelled() || failure()`)가 잠금 파일의 `Who`가 이 러너(`whoami@hostname`)일 때만 잠금을 푼다. PC나 다른 곳이 건 잠금은 건드리지 않는다.
- '지우기 전 정리'는 kubectl이 들어가지 못하면 건너뛴다. 이때는 Helm(컨트롤러)이 module.eks보다 먼저 지워져 클러스터 안에서 정리할 것이 없다.
- `nat-on`·`nat-off`와 정리 단계의 NAT 켜기는 `-target`으로 NAT 세 개(`aws_eip.nat`, `aws_nat_gateway.this`, `aws_route.app_nat`)만 바꾼다.
- destroy 도중에는 취소하지 않는다. 멈춰야 하면 끝난 뒤 다시 돌린다.

## 참고 링크

- https://developer.hashicorp.com/terraform/language/backend/s3#state-locking
- https://developer.hashicorp.com/terraform/cli/commands/force-unlock
