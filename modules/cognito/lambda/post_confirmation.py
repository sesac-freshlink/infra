"""Cognito Post Confirmation 트리거.

직접 가입한 사용자(confirmSignUp)를 SELF_SIGNUP_GROUP(CUSTOMER) 그룹에 넣는다.
- 화면이 clientMetadata로 역할을 넘겨도 보지 않는다(자기 가입으로 점주·관리자가 되는 것을 막는다).
- 비밀번호 찾기 확인(PostConfirmation_ConfirmForgotPassword)에도 같은 트리거가 돌므로 그때는 아무것도 하지 않는다.
- 그룹은 추가만 하고 빼지 않는다. 점주·관리자는 AdminCreateUser로 만들며 이 트리거가 돌지 않는다.
"""

import os

import boto3

cognito = boto3.client("cognito-idp")
GROUP = os.environ["SELF_SIGNUP_GROUP"]


def handler(event, context):
    if event.get("triggerSource") == "PostConfirmation_ConfirmSignUp":
        cognito.admin_add_user_to_group(
            UserPoolId=event["userPoolId"],
            Username=event["userName"],
            GroupName=GROUP,
        )
    # Cognito 트리거는 받은 event를 그대로 돌려줘야 가입이 이어진다
    return event
