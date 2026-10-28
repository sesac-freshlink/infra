"""CloudWatch 경보(SNS)를 Discord 채널 웹훅 메시지로 바꿔 보낸다.

웹훅 주소는 Secrets Manager 비밀(SECRET_ID)의 JSON {"url": ...}에서 읽는다.
값이 아직 없으면 로그만 남기고 끝낸다.
"""
import json
import os
import urllib.request

import boto3

SECRET_ID = os.environ["SECRET_ID"]
ENV_NAME = os.environ.get("ENV_NAME", "")

_secrets = boto3.client("secretsmanager")


def _webhook_url():
    try:
        value = _secrets.get_secret_value(SecretId=SECRET_ID)["SecretString"]
    except _secrets.exceptions.ResourceNotFoundException:
        return None
    url = json.loads(value).get("url", "")
    return url if url.startswith("https://") else None


def _text(alarm):
    queue = next(
        (d["value"] for d in alarm.get("Trigger", {}).get("Dimensions", []) if d.get("name") == "QueueName"),
        alarm.get("AlarmName", "?"),
    )
    if alarm.get("NewStateValue") == "ALARM":
        return (
            f":rotating_light: **[{ENV_NAME}] DLQ에 쪽지가 쌓였습니다**\n"
            f"큐: `{queue}`\n"
            f"이유: {alarm.get('NewStateReason', '')}\n"
            "할 일: 서비스 로그로 원인을 고친 뒤 infra README 4-16 순서로 재처리합니다."
        )
    if alarm.get("NewStateValue") == "OK":
        return f":white_check_mark: **[{ENV_NAME}] DLQ가 비었습니다**\n큐: `{queue}`"
    return f"[{ENV_NAME}] DLQ 경보 상태 {alarm.get('NewStateValue')}: `{queue}`"


def handler(event, _context):
    url = _webhook_url()
    if not url:
        print(f"{SECRET_ID}에 웹훅 주소가 없어 보내지 않았다. scripts/set-dlq-webhook.ps1로 넣는다.")
        return

    for record in event.get("Records", []):
        alarm = json.loads(record["Sns"]["Message"])
        body = json.dumps({"content": _text(alarm)}).encode()
        # Discord는 기본 Python User-Agent를 403으로 막는다
        req = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json", "User-Agent": "freshlink-dlq-alert/1.0"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as res:
            print(f"Discord {res.status}: {alarm.get('AlarmName')} {alarm.get('NewStateValue')}")
