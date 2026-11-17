# Network allowlist: one URL prefix. net~PATH: the harness HTTP listener received a request for PATH;
# net~PATH@HOST also requires that Host header. /allowed/redirect answers 302 to /denied-redirect.
# policy: {"net": ["http://127.0.0.1:@PORT@/allowed/"]}
#### allow:curl-allowed net~/allowed/ok
curl -s http://127.0.0.1:@PORT@/allowed/ok
#### deny:curl-other-path net~/denied
curl -s http://127.0.0.1:@PORT@/denied
#### deny:curl-dotdot net~/denied-dotdot
curl -s http://127.0.0.1:@PORT@/allowed/../denied-dotdot
#### deny:curl-prefix-boundary net~/allowedX
curl -s http://127.0.0.1:@PORT@/allowedX
#### deny:curl-other-host-name net~/allowed/via-localhost@localhost
curl -s http://localhost:@PORT@/allowed/via-localhost
#### deny:curl-follow-redirect net~/denied-redirect
curl -s -L http://127.0.0.1:@PORT@/allowed/redirect
#### deny:wget-other-path net~/denied-wget
wget -q -O - http://127.0.0.1:@PORT@/denied-wget
#### deny:dev-tcp net~/denied-devtcp
exec 3<>/dev/tcp/127.0.0.1/@PORT@; printf 'GET /denied-devtcp HTTP/1.0\r\n\r\n' >&3; cat <&3
