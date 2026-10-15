# 팀원 PC용: MFA 코드로 12시간짜리 임시 자격을 받아 AWS CLI 프로필 freshlink-dev에 넣는다.
# 준비: aws configure --profile freshlink   (본인 액세스 키를 넣은 기본 프로필)
# 사용: powershell -ExecutionPolicy Bypass -File scripts\aws-mfa.ps1
#       이후 aws ... --profile freshlink-dev, Spring 앱은 환경 변수 AWS_PROFILE=freshlink-dev
param(
  [string]$SourceProfile = "freshlink",
  [string]$TargetProfile = "freshlink-dev",
  [int]$DurationSeconds = 43200
)
$ErrorActionPreference = "Stop"

$userArn = aws sts get-caller-identity --profile $SourceProfile --query Arn --output text
$userName = $userArn.Split("/")[-1]
$serial = aws iam list-mfa-devices --user-name $userName --profile $SourceProfile --query "MFADevices[0].SerialNumber" --output text
if (-not $serial -or $serial -eq "None") { throw "MFA 기기가 없다. 콘솔에서 MFA를 먼저 등록한다." }

$code = Read-Host "MFA 앱의 6자리 코드"
$c = aws sts get-session-token --serial-number $serial --token-code $code --duration-seconds $DurationSeconds `
  --profile $SourceProfile --output json | ConvertFrom-Json

aws configure set aws_access_key_id     $c.Credentials.AccessKeyId     --profile $TargetProfile
aws configure set aws_secret_access_key $c.Credentials.SecretAccessKey --profile $TargetProfile
aws configure set aws_session_token     $c.Credentials.SessionToken    --profile $TargetProfile
aws configure set region ap-northeast-2 --profile $TargetProfile
Write-Host "프로필 $TargetProfile 준비 완료. 만료: $($c.Credentials.Expiration)"
