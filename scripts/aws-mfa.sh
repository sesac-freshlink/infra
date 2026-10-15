#!/usr/bin/env bash
# 팀원 PC용(Git Bash·WSL·macOS): MFA 코드로 12시간짜리 임시 자격을 받아 AWS CLI 프로필 freshlink-dev에 넣는다.
# 준비: aws configure --profile freshlink   (본인 액세스 키를 넣은 기본 프로필)
# 사용: ./scripts/aws-mfa.sh   이후 aws ... --profile freshlink-dev, Spring 앱은 AWS_PROFILE=freshlink-dev
set -euo pipefail
SRC="${SOURCE_PROFILE:-freshlink}"
DST="${TARGET_PROFILE:-freshlink-dev}"
DUR="${DURATION_SECONDS:-43200}"

user_arn=$(aws sts get-caller-identity --profile "$SRC" --query Arn --output text)
user_name="${user_arn##*/}"
serial=$(aws iam list-mfa-devices --user-name "$user_name" --profile "$SRC" --query 'MFADevices[0].SerialNumber' --output text)
[ -n "$serial" ] && [ "$serial" != "None" ] || { echo "MFA 기기가 없다. 콘솔에서 MFA를 먼저 등록한다." >&2; exit 1; }

read -rp "MFA 앱의 6자리 코드: " code
read -r ak sk st exp < <(aws sts get-session-token --serial-number "$serial" --token-code "$code" \
  --duration-seconds "$DUR" --profile "$SRC" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' --output text)

aws configure set aws_access_key_id "$ak" --profile "$DST"
aws configure set aws_secret_access_key "$sk" --profile "$DST"
aws configure set aws_session_token "$st" --profile "$DST"
aws configure set region ap-northeast-2 --profile "$DST"
echo "프로필 $DST 준비 완료. 만료: $exp"
