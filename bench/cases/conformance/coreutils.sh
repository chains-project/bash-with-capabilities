#### grep-basic-flags
grep -n ERROR log.txt; grep -c apple words.txt; grep -v -i info log.txt | head -1
#### grep-recursive
grep -rn TODO src | sort
#### grep-l-o-E
grep -rl import src | sort; grep -oE '[0-9]{4}-[0-9]{2}' log.txt | sort -u
#### grep-no-match-rc
grep zzz words.txt; echo "rc=$?"
#### sed-subst
sed 's/apple/APPLE/g' words.txt | head -3; sed -n '2,4p' words.txt; sed '/banana/d' words.txt | wc -l
#### sed-inplace
cp words.txt w2.txt; sed -i 's/^a/A/' w2.txt; head -1 w2.txt
#### sed-regex-groups
echo "2026-11-17" | sed -E 's/([0-9]+)-([0-9]+)-([0-9]+)/\3.\2.\1/'
#### awk-fields
awk -F, 'NR>1 { s += $2; n++ } END { print s, s/n }' data.csv
#### awk-patterns
awk '/ERROR/ { print $3, $4 }' log.txt; awk -F, '$3 == "Paris" { print $1 }' data.csv
#### awk-printf-arrays
awk -F, 'NR>1 { c[$3]++ } END { for (k in c) printf "%s:%d\n", k, c[k] }' data.csv | sort
#### sort-variants
sort -u words.txt | head -3; sort -t, -k2 -n data.csv | head -2; sort -r words.txt | head -1
#### uniq-count
sort words.txt | uniq -c | sort -k1,1nr -k2 | head -3
#### cut-tr
cut -d, -f1,3 data.csv; echo hello | tr a-y b-z; echo "a  b" | tr -s ' '
#### head-tail
head -n 2 words.txt; tail -n 2 words.txt; tail -n +9 words.txt; head -c 5 words.txt; echo
#### wc
wc -l words.txt; wc -w < data.csv; wc -c config.json
#### find-name-type
find . -name '*.py' | sort; find src -type d | sort
#### find-exec-xargs
find src -name '*.py' -exec wc -l {} \; | sort; find src -name '*.py' | sort | xargs grep -c def
#### xargs-I
printf 'a\nb\n' | xargs -I{} echo "item-{}"
#### file-ops
mkdir -p d1/d2 && cp words.txt d1/d2/ && mv d1/d2/words.txt d1/w.txt && rm -r d1/d2 && ls d1
#### basename-dirname
basename /a/b/c.txt .txt; dirname /a/b/c.txt
#### seq
seq 3; seq 2 2 8 | tr '\n' ' '; echo
#### tee
echo teed | tee t1.txt > /dev/null; cat t1.txt
#### jq
jq -r '.name' config.json; jq '.deps | keys' config.json; jq -c '.tags | map(ascii_upcase)' config.json
#### base64-sha256
echo hello | base64; echo aGVsbG8K | base64 -d; echo hello | sha256sum
#### misc-text
rev <<< abc; printf '1\n2\n' | paste -sd+; printf 'a\nb\n' > x1; printf 'b\nc\n' > x2; comm -12 x1 x2
#### diff-u
printf 'a\nb\n' > f1; printf 'a\nc\n' > f2; diff f1 f2; echo "rc=$?"
#### ls-basic
ls; ls -1 src | sort; ls -a src | head -2
#### stat-test-perms
touch newfile; [ -e newfile ] && echo exists; chmod +x newfile; [ -x newfile ] && echo executable
#### printf-file-spaces
cat "notes with space.txt" | wc -l; for f in *space*; do echo "[$f]"; done
