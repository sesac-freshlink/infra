"""인프라 오류 SNS 쪽지를 Discord 오류 채널 웹훅 메시지로 바꿔 보낸다.

받는 쪽지 세 가지:
- CloudWatch 경보 (AlarmName 있음): ALARM이면 알리고, OK는 ALARM에서 돌아왔을 때만 알린다.
- 비용 이상 감지 (anomalyId 있음)
- 켜고 끄기 워크플로 실패 (source = "github-actions", dev-cluster.yml이 aws sns publish로 보낸다)

웹훅 주소는 Secrets Manager 비밀(SECRET_ID)의 JSON {"url": ...}에서 읽는다. 값이 아직 없으면 로그만 남기고 끝낸다.
"""
import json
import os
import urllib.parse
import urllib.request

import boto3

SECRET_ID = os.environ["SECRET_ID"]
ENV_NAME = os.environ.get("ENV_NAME", "")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")

_secrets = boto3.client("secretsmanager")


def _webhook_url():
    try:
        value = _secrets.get_secret_value(SecretId=SECRET_ID)["SecretString"]
    except _secrets.exceptions.ResourceNotFoundException:
        return None
    url = json.loads(value).get("url", "")
    return url if url.startswith("https://") else None


def _alarm_link(name):
    quoted = urllib.parse.quote(name, safe="")
    return f"https://{REGION}.console.aws.amazon.com/cloudwatch/home?region={REGION}#alarmsV2:alarm/{quoted}"


def _alarm_text(alarm):
    name = alarm.get("AlarmName", "?")
    new, old = alarm.get("NewStateValue"), alarm.get("OldStateValue")
    if new == "ALARM":
        return (
            f":rotating_light: **[{ENV_NAME}] 인프라 경보** `{name}`\n"
            f"{alarm.get('AlarmDescription') or ''}\n"
            f"이유: {alarm.get('NewStateReason', '')[:500]}\n"
            f"<{_alarm_link(name)}>"
        )
    if new == "OK" and old == "ALARM":
        return f":white_check_mark: **[{ENV_NAME}] 정상으로 돌아왔습니다** `{name}`"
    # 새로 만든 경보의 INSUFFICIENT_DATA → OK 같은 것은 보내지 않는다(클러스터를 만들 때마다 오지 않게)
    return None


def _anomaly_text(a):
    impact = a.get("impact", {})
    total = impact.get("totalImpact", impact.get("maxImpact", "?"))
    causes = ", ".join(
        f"{c.get('service', '?')}({c.get('usageType', '')})" for c in a.get("rootCauses", [])[:3]
    ) or "?"
    return (
        f":money_with_wings: **[계정 전체] AWS 비용 이상 감지** 예상보다 {total} USD 더 나옴\n"
        f"기간: {a.get('anomalyStartDate', '?')} ~ {a.get('anomalyEndDate', '?')}\n"
        f"원인 후보: {causes}\n"
        f"<{a.get('anomalyDetailsLink', 'https://console.aws.amazon.com/cost-management/home#/anomaly-detection')}>"
    )


def _workflow_text(w):
    return (
        f":x: **[{w.get('env', ENV_NAME)}] 워크플로 실패** {w.get('title', '')}\n"
        f"{w.get('details', '')}\n"
        f"<{w.get('url', '')}>"
    )


def _text(message):
    try:
        body = json.loads(message)
    except (TypeError, ValueError):
        return f":warning: **[{ENV_NAME}] 인프라 알림**\n{str(message)[:1500]}"
    if "AlarmName" in body:
        return _alarm_text(body)
    if "anomalyId" in body:
        return _anomaly_text(body)
    if body.get("source") == "github-actions":
        return _workflow_text(body)
    return f":warning: **[{ENV_NAME}] 인프라 알림**\n```{json.dumps(body, ensure_ascii=False)[:1500]}```"


def _post(url, content):
    body = json.dumps({"content": content[:1900]}).encode()
    # Discord는 기본 Python User-Agent를 403으로 막는다
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "freshlink-infra-alert/1.0"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        return res.status


def handler(event, _context):
    url = _webhook_url()
    if not url:
        print(f"{SECRET_ID}에 웹훅 주소가 없어 보내지 않았다. scripts/set-error-webhook.ps1로 넣는다.")
        return

    for record in event.get("Records", []):
        content = _text(record["Sns"]["Message"])
        if content is None:
            print(f"건너뜀: {record['Sns'].get('Subject', '')}")
            continue
        print(f"Discord {_post(url, content)}: {content.splitlines()[0]}")
