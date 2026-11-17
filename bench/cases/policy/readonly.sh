# The whole workdir read-only.
# policy: {"fs": {".": "ro"}}
#### allow:read stdout~elderberry
cat words.txt
#### allow:grep-r stdout~TODO: handle
grep -rn TODO src
#### deny:redirect-create host+new.txt
echo x > new.txt
#### deny:redirect-append hostchg words.txt
echo x >> words.txt
#### deny:redirect-truncate hostchg words.txt
: > words.txt
#### deny:sed-inplace hostchg words.txt
sed -i 's/apple/APPLE/' words.txt
#### deny:rm host-words.txt
rm words.txt
#### deny:mv host-words.txt
mv words.txt w3.txt
#### deny:cp host+w2.txt
cp words.txt w2.txt
#### deny:tee host+t.txt
echo x | tee t.txt
#### deny:mkdir host+d
mkdir d
#### deny:touch host+touched
touch touched
