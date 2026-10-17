// CloudFront Function (viewer-request, 기본 동작에만). React 라우트(/owner/inventory 등)는 S3에 파일이 없어서
// 확장자가 없는 경로를 /index.html로 바꾼다. /assets/index-abc.js 같은 파일 경로는 그대로 둔다.
function handler(event) {
  var request = event.request;
  var last = request.uri.split('/').pop();
  if (last.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
