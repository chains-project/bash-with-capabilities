#### redirect-write-append
echo one > o.txt; echo two >> o.txt; cat o.txt
#### redirect-stderr
ls nosuchfile 2>/dev/null; echo "rc=$?"; { echo out; echo err >&2; } 2>&1 | sort
#### redirect-both
{ echo out; echo err >&2; } &> both.txt; sort both.txt
#### redirect-stdin
wc -l < words.txt
#### heredoc
cat <<EOF
x=$((1+1))
  indented
EOF
#### heredoc-quoted
cat <<'EOF'
no $expansion `here`
EOF
#### heredoc-strip-tabs
cat <<-EOF
	tab stripped
	EOF
#### herestring
tr a-z A-Z <<< "shout"
#### pipeline
cat words.txt | sort | uniq -c | sort -rn | head -2
#### pipestatus
true | false | true; echo "${PIPESTATUS[@]}"
#### pipefail
set -o pipefail; false | true; echo $?
#### process-subst
diff <(printf 'a\nb\n') <(printf 'a\nc\n'); echo "rc=$?"
#### read-builtin
read -r a b <<< "first rest of line"; echo "$a|$b"
#### exec-fd
exec 3> fd.txt; echo via-fd >&3; exec 3>&-; cat fd.txt
#### noclobber
set -C; echo a > nc.txt; echo b > nc.txt 2>/dev/null; echo "rc=$?"; cat nc.txt
#### dev-null-read
cat /dev/null | wc -c
