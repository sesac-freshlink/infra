# dev CSP를 enforce로 바꾼 뒤 카카오맵 스크립트가 막힘

- 날짜: 2026-11-02
- 작성: 김진아
- 관련: infra [#68](https://github.com/sesac-freshlink/infra/pull/68)(dev CSP enforce), [#69](https://github.com/sesac-freshlink/infra/pull/69)(`t1.kakaocdn.net` 추가, 머지 커밋 `273ed2e`)

## 증상

고객 점포 상세 화면(`/customer/stores/:storeId/info`)에서 카카오맵이 뜨지 않았다. 김경우가 알려 줬다. 브라우저 콘솔에 아래 모양의 CSP 위반이 찍혔다(경로 뒷부분은 생략):

```text
Refused to load the script 'https://t1.kakaocdn.net/...' because it violates the following Content Security Policy directive: "script-src 'self' https://js.tosspayments.com https://dapi.kakao.com https://t1.daumcdn.net".
```

## 환경·발생 조건

- 묶음/위치: `envs/dev/persistent`, `modules/frontend` (CloudFront 응답 헤더 정책)
- 어떤 작업 중이었나: 같은 날 dev CSP를 `Content-Security-Policy-Report-Only`에서 `Content-Security-Policy`(enforce)로 바꾼 직후.

## 원인

- 카카오 지도 SDK는 `dapi.kakao.com/v2/maps/sdk.js`를 받은 뒤 지도 본체 스크립트를 `t1.kakaocdn.net`에서 받는다. 10/30 infra #60에서는 예전 주소 `t1.daumcdn.net`만 넣었다.
- Report-Only 기간에 위반을 모을 때 고객 화면(카카오맵)은 dev 고객 시드 계정이 없어 지나가 보지 못했다. 그래서 enforce 전에 이 위반을 못 봤다.

## 해결

`modules/frontend/main.tf`의 `script-src`에 `https://t1.kakaocdn.net`을 더했다.

```text
script-src 'self' https://js.tosspayments.com https://dapi.kakao.com https://t1.kakaocdn.net https://t1.daumcdn.net
```

```powershell
cd envs\dev\persistent
terraform plan -out=tfplan     # 0 to add, 1 to change, 0 to destroy (응답 헤더 정책만)
terraform apply tfplan
curl.exe -sI https://dev.getfreshlink.com/ | Select-String content-security-policy   # t1.kakaocdn.net 확인
```

브라우저는 강력 새로고침(Ctrl+Shift+R) 뒤 지도가 떴다(김경우 확인).

## 재발 방지

- prod는 같은 모듈이라 prod persistent apply 때 같이 들어간다(.github 할 일 문서 "prod 릴리스 때 할 일"에 적음).
- enforce로 바꾸기 전에는 Report-Only 상태로 **모든 역할(관리자·점주·고객)** 화면을 지나가 본다. 계정이 없어 못 본 화면이 있으면 enforce를 미루거나 그 화면 담당자에게 먼저 확인을 받는다.
- 외부 SDK(지도·결제)는 첫 스크립트 주소만이 아니라 그 SDK가 다시 부르는 주소도 확인한다(개발자 도구 Network에서 `JS` 필터).
