"""매일 아침 비용 메일: 어제 비용, 이번 달 누계, 프로젝트 시작부터 총 비용을 SNS 주제로 보낸다.

Cost Explorer의 하루는 UTC 기준이다. 크레딧·환불은 빼고 센다(예산 include_credit=false와 같은 기준).
"""
import json
import os
from datetime import date, datetime, timedelta, timezone

import boto3

# Cost Explorer API는 us-east-1에만 있다
ce = boto3.client("ce", region_name="us-east-1")
sns = boto3.client("sns")

TOPIC_ARN = os.environ["TOPIC_ARN"]
PROJECT_START = date.fromisoformat(os.environ["PROJECT_START"])
MONTHLY_LIMITS = json.loads(os.environ["MONTHLY_LIMITS"])  # {"2026-10": 160, ...}
TOTAL_BUDGET = float(os.environ["TOTAL_BUDGET"])
TOP_SERVICES = 5

WITHOUT_CREDIT = {"Not": {"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Credit", "Refund"]}}}


def get_cost(start, end, granularity, group_by=None):
    """[start, end) 구간 결과를 페이지를 넘겨 모두 모은다."""
    kwargs = {
        "TimePeriod": {"Start": start.isoformat(), "End": end.isoformat()},
        "Granularity": granularity,
        "Metrics": ["UnblendedCost"],
        "Filter": WITHOUT_CREDIT,
    }
    if group_by:
        kwargs["GroupBy"] = [{"Type": "DIMENSION", "Key": group_by}]
    results = []
    while True:
        resp = ce.get_cost_and_usage(**kwargs)
        results.extend(resp["ResultsByTime"])
        token = resp.get("NextPageToken")
        if not token:
            return results
        kwargs["NextPageToken"] = token


def month_limit(month):
    """monthly_limits에 없는 달은 마지막 달 금액을 쓴다(budget 모듈과 같은 규칙)."""
    if month in MONTHLY_LIMITS:
        return float(MONTHLY_LIMITS[month])
    return float(MONTHLY_LIMITS[sorted(MONTHLY_LIMITS)[-1]])


def usd(amount):
    return f"US${amount:,.2f}"


def build_report(today):
    yesterday = today - timedelta(days=1)
    month_start = yesterday.replace(day=1)
    month = yesterday.strftime("%Y-%m")

    # 어제 하루, 서비스별
    services = []
    for r in get_cost(yesterday, today, "DAILY", "SERVICE"):
        for g in r["Groups"]:
            services.append((g["Keys"][0], float(g["Metrics"]["UnblendedCost"]["Amount"])))
    yesterday_total = sum(a for _, a in services)
    services.sort(key=lambda s: s[1], reverse=True)

    # 프로젝트 시작부터 어제까지, 달별
    by_month = {}
    for r in get_cost(PROJECT_START, today, "MONTHLY"):
        by_month[r["TimePeriod"]["Start"][:7]] = float(r["Total"]["UnblendedCost"]["Amount"])
    month_total = by_month.get(month, 0.0)
    project_total = sum(by_month.values())
    limit = month_limit(month)

    subject = f"[FreshLink 비용] {yesterday:%m/%d} {usd(yesterday_total)} · 총 {usd(project_total)}"
    lines = [
        f"어제({yesterday:%Y-%m-%d}) 비용: {usd(yesterday_total)}",
        f"{yesterday.month}월 누계({month_start:%m/%d}~{yesterday:%m/%d}): {usd(month_total)} / 예산 {usd(limit)} ({month_total / limit * 100:.1f}%)",
        f"총 비용({PROJECT_START:%Y-%m-%d}부터): {usd(project_total)} / 지원금 {usd(TOTAL_BUDGET)} ({project_total / TOTAL_BUDGET * 100:.1f}%)",
        "",
        f"어제 많이 쓴 서비스 (상위 {TOP_SERVICES}):",
    ]
    shown = [s for s in services if s[1] >= 0.005][:TOP_SERVICES]
    lines += [f"  - {name}: {usd(amount)}" for name, amount in shown] or ["  - 없음"]
    lines += [
        "",
        "참고",
        "- 하루는 UTC 기준(한국 시간 오전 9시~다음 날 오전 9시)이다.",
        "- Cost Explorer는 최대 하루 늦게 채워져서, 어제 값은 내일 메일에서 조금 늘 수 있다.",
        "- 크레딧·환불은 빼고 센 실제 사용 금액이다(AWS Budgets 예산과 같은 기준).",
    ]
    return subject, "\n".join(lines)


def handler(event, context):
    today = datetime.now(timezone.utc).date()
    subject, body = build_report(today)
    sns.publish(TopicArn=TOPIC_ARN, Subject=subject, Message=body)
    print(subject)
    return {"subject": subject, "body": body}
