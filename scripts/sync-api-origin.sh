#!/usr/bin/env bash
# CloudFront /api/* 오리진을 지금 gateway ALB 주소로 맞춘다 (할 일 13).
# ALB는 클러스터 안의 AWS Load Balancer Controller가 gateway Ingress를 보고 만들어서, 클러스터를 새로 만들 때마다 주소가 바뀐다.
# dev-cluster.yml의 create 단계와 수동 버튼(api-origin)이 부른다. kubectl이 그 클러스터를 보고 있어야 한다.
#   사용: scripts/sync-api-origin.sh <env>   (예: dev)
set -euo pipefail

ENV_NAME="${1:?env가 필요하다 (dev | prod)}"
COMMENT="freshlink-${ENV_NAME}-frontend"   # modules/frontend의 배포 comment
NAMESPACE=freshlink
INGRESS=gateway
ORIGIN_ID=api

# 1) gateway Ingress의 ALB 주소. ArgoCD가 gateway를 올리고 컨트롤러가 ALB를 만들 때까지 기다린다(최대 15분)
host=""
for _ in $(seq 1 90); do
  host=$(kubectl -n "$NAMESPACE" get ingress "$INGRESS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$host" ] && break
  sleep 10
done
if [ -z "$host" ]; then
  echo "::error::${NAMESPACE}/${INGRESS} Ingress에 ALB 주소가 15분 안에 생기지 않았다. ArgoCD에서 gateway 상태를 본다"
  exit 1
fi
echo "gateway ALB: ${host}"

# 2) CloudFront 배포 찾기
dist=$(aws cloudfront list-distributions --output text \
  --query "DistributionList.Items[?Comment=='${COMMENT}'].Id | [0]")
if [ -z "$dist" ] || [ "$dist" = "None" ]; then
  echo "::error::Comment가 ${COMMENT}인 CloudFront 배포가 없다. envs/${ENV_NAME}/persistent를 먼저 apply한다"
  exit 1
fi

# 3) 오리진 주소가 다르면 바꾼다. CloudFront → ALB는 HTTP(80). ALB에는 인증서가 없다
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
aws cloudfront get-distribution-config --id "$dist" > "$tmp/current.json"
etag=$(jq -r '.ETag' "$tmp/current.json")
current=$(jq -r --arg id "$ORIGIN_ID" '.DistributionConfig.Origins.Items[] | select(.Id == $id) | .DomainName' "$tmp/current.json")
if [ "$current" = "$host" ]; then
  echo "이미 ${host}를 가리킨다. 바꿀 것 없음"
  exit 0
fi

jq --arg id "$ORIGIN_ID" --arg host "$host" '
  .DistributionConfig
  | .Origins.Items |= map(
      if .Id == $id then
        .DomainName = $host
        | .CustomOriginConfig.OriginProtocolPolicy = "http-only"
      else . end)
' "$tmp/current.json" > "$tmp/new.json"

aws cloudfront update-distribution --id "$dist" --if-match "$etag" \
  --distribution-config "file://$tmp/new.json" --query 'Distribution.Status' --output text
echo "CloudFront ${dist} /api/* 오리진: ${current} → ${host} (전 세계 반영까지 몇 분 걸린다)"
