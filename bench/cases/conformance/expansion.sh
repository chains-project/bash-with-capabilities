#### param-default
unset x; echo "${x:-dflt}" "${x-unset}"; y=; echo "[${y:-empty}]" "[${y-set}]"
#### param-assign-default
unset x; : "${x:=assigned}"; echo "$x"
#### param-length
s=hello; echo ${#s}
#### param-strip-suffix-prefix
f=/a/b/archive.tar.gz; echo "${f%.*}" "${f%%.*}" "${f#*/}" "${f##*/}"
#### param-replace
s=banana; echo "${s/an/AN}" "${s//an/AN}" "${s/#b/B}" "${s/%a/A}"
#### param-case
s=Hello; echo "${s^^}" "${s,,}" "${s^}"
#### param-substring
s=abcdefgh; echo "${s:2:3}" "${s: -3}" "${s:5}"
#### param-indirect
ref=target; target=42; echo "${!ref}"
#### param-error-unset
unset x; ( : "${x:?is required}" ) 2>/dev/null; echo "rc=$?"
#### arith-basic
echo $((7 * 6)) $((17 / 5)) $((17 % 5)) $((2 ** 10)) $(( (1+2) * 3 ))
#### arith-vars-incr
i=5; ((i++)); ((i+=10)); echo $i; echo $((i > 10 ? 1 : 0))
#### arith-hex-octal
echo $((0x1f)) $((010)) $((2#101))
#### brace-range
echo {1..5} {a..e} {05..10..2}
#### brace-list
echo pre{A,B,C}post x{1,2}{a,b}
#### cmd-subst-nested
echo "outer $(echo "inner $(echo deep)")"
#### cmd-subst-backtick
echo `echo back` "$(echo dollar)"
#### cmd-subst-trailing-newlines
x=$(printf 'a\n\n\n'); echo "[$x]"
#### word-splitting
s="a  b   c"; for w in $s; do echo "<$w>"; done; for w in "$s"; do echo "<$w>"; done
#### ifs-custom
IFS=: read -r a b c <<< "x:y:z"; echo "$b"; s="1,2,3"; IFS=,; set -- $s; echo $#
#### positional-at-star
set -- "a b" c "d e"; for x in "$@"; do echo "[$x]"; done; echo "$*"; IFS=-; echo "$*"
#### glob-star
echo *.txt
#### glob-nomatch
echo *.nomatch
#### glob-question-class
echo ?ata.csv [cw]*.txt
#### glob-recursive-globstar
shopt -s globstar; echo src/**/*.py
#### tilde-and-dollar-literal
echo '$HOME' "\$HOME" '~'
#### special-vars
f() { echo "$#" "$1" "${@: -1}"; }; f one two three; false; echo $?
