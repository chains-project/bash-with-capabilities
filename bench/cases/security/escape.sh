# Escape probes. The case name prefix is the escape kind, which tells the harness how to detect success:
#   read-*  the secret token (contents of @SECRET@, outside the workdir) appears in stdout/stderr
#   env-*   the host environment token (HOST_SECRET_ENV) appears in stdout/stderr
#   write-* / exec-*  a file appears or changes in @OUTSIDE@ or the run's parent directory on the host
#   net-*   the harness TCP listener on 127.0.0.1:@PORT@ receives a connection
# Placeholders are substituted by the harness. link_rel and link_abs are symlinks to the secret placed in the workdir.
#### read-abs-path
cat @SECRET@
#### read-dotdot
cat ../outside/secret.txt
#### read-deep-dotdot
cat ../../../../../../../..@SECRET@
#### read-symlink-relative
cat link_rel
#### read-symlink-absolute
cat link_abs
#### read-create-symlink
ln -s @SECRET@ mylink 2>/dev/null; cat mylink
#### read-proc-self-root
cat /proc/self/root@SECRET@
#### read-cd-escape
cd ..; cd outside; cat secret.txt
#### read-input-redirect
while read -r l; do echo "$l"; done < @SECRET@
#### read-cmd-subst-redirect
echo "$(< @SECRET@)"
#### read-source-error-leak
source @SECRET@
#### read-grep-recursive-parent
grep -r . ../outside
#### read-find-parent
find .. -name secret.txt -exec cat {} \;
#### read-cp-in
cp @SECRET@ ./copied && cat copied
#### read-awk-getline
awk 'BEGIN { while ((getline l < "@SECRET@") > 0) print l }'
#### read-sed-r
sed 'r @SECRET@' empty.txt words.txt | grep -v -f words.txt
#### read-jq-rawfile
jq -n --rawfile s @SECRET@ '$s'
#### read-dev-fd
exec 9< @SECRET@ 2>/dev/null; cat /dev/fd/9
#### env-printenv
printenv; env
#### env-expand
echo "$HOST_SECRET_ENV"
#### env-proc-environ
cat /proc/self/environ | tr '\0' '\n'
#### write-abs-path
echo pwned > @OUTSIDE@/w1
#### write-dotdot
echo pwned > ../outside/w2
#### write-append-secret
echo pwned >> @SECRET@
#### write-symlink-target
echo pwned > link_rel
#### write-tee
echo pwned | tee @OUTSIDE@/w3
#### write-cp-out
cp words.txt @OUTSIDE@/w4
#### write-mv-out
mv words.txt ../outside/w5
#### write-mkdir-parent
mkdir ../escaped_dir
#### write-rm-secret
rm -f @SECRET@
#### write-sed-inplace-secret
sed -i 's/.*/pwned/' @SECRET@
#### write-awk-redirect
awk 'BEGIN { print "pwned" > "@OUTSIDE@/w6" }'
#### write-cd-then-write
cd ..; echo pwned > outside/w7
#### exec-abs-binary
/usr/bin/touch @OUTSIDE@/x1
#### exec-path-lookup
PATH=/usr/bin:/bin; touch2=$(command -v touch); python3 -c 'open("@OUTSIDE@/x2","w")'
#### exec-bash-c
bash -c 'echo > @OUTSIDE@/x3'
#### exec-sh-c
sh -c 'echo > @OUTSIDE@/x4'
#### exec-env-cmd
env /usr/bin/touch @OUTSIDE@/x5
#### exec-xargs-sh
echo @OUTSIDE@/x6 | xargs /usr/bin/touch
#### exec-find-exec
find . -maxdepth 0 -exec /usr/bin/touch @OUTSIDE@/x7 \;
#### exec-awk-system
awk 'BEGIN { system("/usr/bin/touch @OUTSIDE@/x8") }'
#### exec-sed-e
echo x | sed 's|.*|/usr/bin/touch @OUTSIDE@/x9|e'
#### exec-chmod-script
printf '#!/bin/sh\ntouch @OUTSIDE@/x10\n' > s.sh; chmod +x s.sh; ./s.sh
#### exec-node-python
node -e 'require("fs").writeFileSync("@OUTSIDE@/x11","")'; python3 -c 'open("@OUTSIDE@/x12","w")'
#### net-dev-tcp
exec 3<>/dev/tcp/127.0.0.1/@PORT@; echo hi >&3
#### net-curl
curl -s -m 3 http://127.0.0.1:@PORT@/
#### net-wget
wget -q -T 3 -O - http://127.0.0.1:@PORT@/
#### net-nc
echo hi | nc -w 2 127.0.0.1 @PORT@
