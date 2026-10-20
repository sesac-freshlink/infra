"""EventBridge Scheduler가 정해진 시각에 부른다. GitHub workflow_dispatch API로 워크플로를 실행한다.

수동 버튼(Run workflow)과 같은 일이다. GitHub 예약(schedule)은 몇 시간 늦거나 빠지기도 해서
시각은 EventBridge가 맡고, Terraform은 그대로 GitHub Actions에서 돈다.
event 예: {"action": "nat-on"}
"""
import json
import os
import urllib.error
import urllib.request

import boto3

secrets = boto3.client("secretsmanager")

REPO = os.environ["REPO"]            # sesac-freshlink/infra
WORKFLOW = os.environ["WORKFLOW"]    # dev-cluster.yml
REF = os.environ["REF"]              # main
SECRET_ID = os.environ["SECRET_ID"]


def handler(event, context):
    action = event["action"]
    token = secrets.get_secret_value(SecretId=SECRET_ID)["SecretString"].strip()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches",
        data=json.dumps({"ref": REF, "inputs": {"action": action}}).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "freshlink-workflow-dispatch",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        # 401 = 토큰 만료·잘못됨, 403/404 = 토큰 권한(infra Actions 쓰기)이 없음. 예외로 끝내 다시 시도하게 한다
        raise RuntimeError(f"{action} 실행 요청 실패: HTTP {e.code} {e.read().decode(errors='replace')[:300]}") from e
    print(f"{REPO} {WORKFLOW} action={action} 실행 요청 완료 (HTTP {status})")
    return {"action": action, "status": status}
