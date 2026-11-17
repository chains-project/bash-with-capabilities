# Path grants: src/ read-only, out/ read-write, nothing else (words.txt and secrets/ are not granted).
# secrets/key.txt holds a per-run token (@TOKEN@). host+P / host-P / hostchg P: P created / removed / changed.
# policy: {"fs": {"src": "ro", "out": "rw"}}
#### allow:read-src stdout~from lib.helper
cat src/main.py
#### allow:write-out host+out/a.txt
echo hi > out/a.txt
#### allow:copy-src-to-out host+out/u.py
cat src/util.py > out/u.py
#### deny:read-secret stdout~@TOKEN@
cat secrets/key.txt
#### deny:read-secret-src-dotdot stdout~@TOKEN@
cat src/../secrets/key.txt
#### deny:read-secret-out-dotdot stdout~@TOKEN@
cat out/../secrets/key.txt
#### deny:read-secret-glob stdout~@TOKEN@
cat secr*/*
#### deny:read-secret-grep-r stdout~@TOKEN@
grep -r TOKEN- .
#### deny:read-secret-cd stdout~@TOKEN@
cd secrets && cat key.txt
#### deny:read-secret-symlink-in-out stdout~@TOKEN@
ln -s ../secrets out/s; cat out/s/key.txt
#### deny:read-secret-input-redirect stdout~@TOKEN@
while read -r l; do echo "$l"; done < secrets/key.txt
#### deny:read-secret-host-abs-path stdout~@TOKEN@
cat @WORK@/secrets/key.txt
#### deny:read-ungranted-file stdout~elderberry
cat words.txt
#### deny:write-src host+src/new.txt
echo x > src/new.txt
#### deny:append-src hostchg src/main.py
echo x >> src/main.py
#### deny:rm-src host-src/util.py
rm src/util.py
#### deny:mv-src-to-out host-src/util.py
mv src/util.py out/
#### deny:sed-inplace-src hostchg src/main.py
sed -i 's/import/IMPORT/' src/main.py
#### deny:touch-src host+src/t
touch src/t
#### deny:write-ungranted-root host+new.txt
echo x > new.txt
#### deny:write-out-dotdot host+escaped.txt
echo x > out/../escaped.txt
#### deny:mkdir-ungranted host+newdir
mkdir newdir
#### deny:overwrite-secret hostchg secrets/key.txt
echo x > secrets/key.txt
