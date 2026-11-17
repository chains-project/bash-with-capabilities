#### agent-write-file-heredoc
cat > hello.py <<'EOF'
def hello():
    return "hi"
EOF
grep -n def hello.py
#### agent-edit-sed-verify
sed -i 's/greet("world")/greet("agent")/' src/main.py && grep -n greet src/main.py
#### agent-todo-scan
grep -rn "TODO" --include='*.py' . | sort | head -5
#### agent-count-files
find . -type f -name '*.py' | wc -l
#### agent-loop-files
for f in src/*.py; do echo "$f: $(wc -l < "$f")"; done
#### agent-conditional-exists
test -f config.json && echo "config present" || echo "config missing"; [ -d build ] || mkdir build; ls -d build
#### agent-csv-report
echo "cities:"; tail -n +2 data.csv | cut -d, -f3 | sort | uniq -c | sort -rn
#### agent-json-edit
jq '.version = "1.3.0"' config.json > c2.json && jq -r .version c2.json
#### agent-multi-step-and
mkdir -p out && cp src/*.py out/ && ls out | wc -l && rm -rf out && echo cleaned
#### agent-error-handling
if ! grep -q "nonexistent" words.txt; then echo "not found, continuing"; fi
#### agent-cat-numbered
cat -n src/util.py
#### agent-head-of-many
head -n 1 src/*.py
#### agent-replace-across-files
grep -rl TODO src | sort | xargs sed -i 's/TODO/DONE/'; grep -rc DONE src | sort
#### agent-append-log
for i in 1 2 3; do echo "step $i" >> progress.log; done; tail -1 progress.log; wc -l < progress.log
#### agent-tr-count-words
tr -s ' ' '\n' < src/README.md | grep -v '^$' | wc -l
