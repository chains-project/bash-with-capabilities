# Command allowlist: only cat and grep beyond shell builtins. Deny probes try to run sed or awk anyway;
# their markers (SEDfigRAN, AWKRAN) only appear in stdout if the denied command actually ran.
# policy: {"commands": ["cat", "grep"]}
#### allow:cat stdout~elderberry
cat words.txt
#### allow:grep stdout~6:elderberry
grep -n elderberry words.txt
#### deny:sed-direct stdout~SEDfigRAN
sed -n 's/^fig$/SED&RAN/p' words.txt
#### deny:sed-variable-name stdout~SEDfigRAN
x=sed; $x -n 's/^fig$/SED&RAN/p' words.txt
#### deny:sed-quoted-name stdout~SEDfigRAN
"s"ed -n 's/^fig$/SED&RAN/p' words.txt
#### deny:sed-cmdsubst-name stdout~SEDfigRAN
$(echo sed) -n 's/^fig$/SED&RAN/p' words.txt
#### deny:sed-eval stdout~SEDfigRAN
eval "sed -n 's/^fig\$/SED&RAN/p' words.txt"
#### deny:sed-command-builtin stdout~SEDfigRAN
command sed -n 's/^fig$/SED&RAN/p' words.txt
#### deny:sed-in-pipeline stdout~SEDfigRAN
cat words.txt | sed -n 's/^fig$/SED&RAN/p'
#### deny:sed-in-subshell stdout~SEDfigRAN
(sed -n 's/^fig$/SED&RAN/p' words.txt)
#### deny:sed-in-cmdsubst stdout~SEDfigRAN
echo "$(sed -n 's/^fig$/SED&RAN/p' words.txt)"
#### deny:sed-in-function stdout~SEDfigRAN
f() { sed -n 's/^fig$/SED&RAN/p' words.txt; }; f
#### deny:sed-via-bash-c stdout~SEDfigRAN
bash -c "sed -n 's/^fig\$/SED&RAN/p' words.txt"
#### deny:sed-via-env stdout~SEDfigRAN
env sed -n 's/^fig$/SED&RAN/p' words.txt
#### deny:sed-via-xargs stdout~SEDfigRAN
echo words.txt | xargs sed -n 's/^fig$/SED&RAN/p'
#### deny:sed-via-find-exec stdout~SEDfigRAN
find . -name words.txt -exec sed -n 's/^fig$/SED&RAN/p' {} \;
#### deny:sed-via-source-stdin stdout~SEDfigRAN
source /dev/stdin <<< "sed -n 's/^fig\$/SED&RAN/p' words.txt"
#### deny:sed-abs-path stdout~SEDfigRAN
/usr/bin/sed -n 's/^fig$/SED&RAN/p' words.txt
#### deny:awk-direct stdout~AWKRAN
awk 'BEGIN { print "AWK" "RAN" }'
