#!/usr/bin/env bash
# gateway ALB 5xx 경보를 지금 ALB에 맞춘다 (README 4-24).
# ALB는 클러스터 안의 AWS Load Balancer Controller가 만들어서 Terraform이 이름을 모르고, 클러스터를 새로 만들 때마다 바뀐다.
# 같은 경보 이름(freshlink-<env>-alb-5xx)으로 put-metric-alarm을 다시 부르면 차원만 새 ALB로 바뀐다(경보는 하나로 유지).
# 인프라 오류 SNS 주제(envs/<env>/persistent modules/infra-alert)가 없는 환경은 건너뛴다.
# dev-cluster.yml의 create 단계와 수동 버튼(api-origin)이 sync-api-origin.sh 다음에 부른다. kubectl이 그 클러스터를 보고 있어야 한다.
#   사용: scripts/sync-alb-alarm.sh <env>   (예: prod)
set -euo pipefail

ENV_NAME="${1:?env가 필요하다 (dev | prod)}"
NAMESPACE=freshlink
INGRESS=gateway
ALARM="freshlink-${ENV_NAME}-alb-5xx"
THRESHOLD=10 # 5분 동안 ALB 5xx + 대상(서비스) 5xx 합계

account=$(aws sts get-caller-identity --query Account --output text)
region="${AWS_REGION:-ap-northeast-2}"
topic="arn:aws:sns:${region}:${account}:freshlink-${ENV_NAME}-infra-alert"
if ! aws sns get-topic-attributes --topic-arn "$topic" >/dev/null 2>&1; then
  echo "${topic}가 없어 ALB 경보를 건너뛴다(이 환경은 인프라 오류 알림을 켜지 않았다)"
  exit 0
fi

host=$(kubectl -n "$NAMESPACE" get ingress "$INGRESS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
[ -n "$host" ] || { echo "::error::${NAMESPACE}/${INGRESS} Ingress에 ALB 주소가 없다"; exit 1; }
lb_arn=$(aws elbv2 describe-load-balancers --output text \
  --query "LoadBalancers[?DNSName=='${host}'].LoadBalancerArn | [0]")
[ -n "$lb_arn" ] && [ "$lb_arn" != "None" ] || { echo "::error::${host} ALB를 찾지 못했다"; exit 1; }
lb_dim="${lb_arn#*:loadbalancer/}" # app/<이름>/<ID>

metric() { # $1 id, $2 지표 이름
  printf '{"Id":"%s","ReturnData":false,"MetricStat":{"Metric":{"Namespace":"AWS/ApplicationELB","MetricName":"%s","Dimensions":[{"Name":"LoadBalancer","Value":"%s"}]},"Period":300,"Stat":"Sum"}}' \
    "$1" "$2" "$lb_dim"
}
metrics="[$(metric elb HTTPCode_ELB_5XX_Count),$(metric target HTTPCode_Target_5XX_Count),{\"Id\":\"total\",\"Label\":\"5xx\",\"ReturnData\":true,\"Expression\":\"FILL(elb,0)+FILL(target,0)\"}]"

aws cloudwatch put-metric-alarm \
  --alarm-name "$ALARM" \
  --alarm-description "gateway ALB 5xx(ALB 자체 + 서비스 응답)가 5분에 ${THRESHOLD}개 이상이다. Grafana 로그(README 4-14)에서 어느 API가 실패하는지 본다(README 4-24)" \
  --metrics "$metrics" \
  --evaluation-periods 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --threshold "$THRESHOLD" \
  --treat-missing-data notBreaching \
  --alarm-actions "$topic" \
  --ok-actions "$topic"
echo "경보 ${ALARM}: ALB ${lb_dim}, 5분 5xx ${THRESHOLD}개 이상이면 Discord 오류 채널"
