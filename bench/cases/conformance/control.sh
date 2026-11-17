#### if-elif-else
for n in 1 5 10; do if [ $n -lt 3 ]; then echo small; elif [ $n -lt 8 ]; then echo mid; else echo big; fi; done
#### for-in-list
for x in a b c; do echo "item $x"; done
#### for-c-style
for ((i=0; i<3; i++)); do echo $i; done
#### while-read-file
while IFS=, read -r name age city; do echo "$name is $age"; done < data.csv
#### until-loop
i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done
#### case-patterns
for f in a.txt b.py c.tar.gz Makefile; do case $f in *.txt) echo text;; *.py|*.sh) echo script;; *.tar.*) echo archive;; *) echo other;; esac; done
#### case-fallthrough
case x in x) echo one;& y) echo two;; z) echo three;; esac
#### break-continue-nested
for i in 1 2 3; do for j in 1 2 3; do [ $j -eq 2 ] && continue; [ $i -eq 3 ] && break 2; echo "$i$j"; done; done
#### and-or-chain
true && echo yes || echo no; false && echo yes || echo no; false || false || echo last
#### negation
! false && echo negated; ! true; echo $?
#### function-local-return
g=global; f() { local g=local; echo "$g"; return 3; }; f; echo "rc=$? g=$g"
#### function-recursion
fact() { if [ $1 -le 1 ]; then echo 1; else echo $(( $1 * $(fact $(( $1 - 1 ))) )); fi; }; fact 6
#### function-keyword-syntax
function hi { echo "hi $1"; }; hi there
#### subshell-isolation
x=1; (x=2; echo "in $x"); echo "out $x"
#### group-redirect
{ echo a; echo b; } > g.txt; wc -l < g.txt
#### loop-pipe-subshell
n=0; printf '1\n2\n3\n' | while read l; do n=$((n+l)); done; echo "n=$n"
#### while-true-break
x=3; while :; do x=$((x-1)); [ $x -eq 0 ] && break; done; echo done
