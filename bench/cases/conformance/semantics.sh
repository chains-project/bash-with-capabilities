#### set-e
set -e; echo before; false; echo after
#### set-e-conditional-exempt
set -e; if false; then :; fi; false || true; echo survived
#### set-u
set -u; echo "${undefined_var}"; echo after
#### exit-code-propagation
(exit 7); echo $?
#### command-not-found
nosuchcommand_xyz 2>/dev/null; echo "rc=$?"
#### trap-exit
trap 'echo cleanup' EXIT; echo body
#### eval
cmd='echo evaluated $((2+2))'; eval "$cmd"
#### test-operators
[ -f words.txt ] && echo file; [ -d src ] && echo dir; [ -s empty.txt ] || echo emptyfile; [ abc = abc ] && echo streq; [ 3 -gt 2 ] && echo numgt
#### double-bracket
s=hello123; [[ $s == hel* ]] && echo glob; [[ $s =~ ^([a-z]+)([0-9]+)$ ]] && echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; [[ -n $s && ! -z $s ]] && echo both
#### arith-command
((3 > 2)) && echo true; ((0)); echo $?
#### shift-getopts
f() { while getopts "ab:" o; do case $o in a) echo A;; b) echo "B=$OPTARG";; esac; done; shift $((OPTIND-1)); echo "rest=$*"; }; f -a -b val x y
#### declare-integer-readonly
declare -i n=5; n+=3; echo $n; readonly r=1; (r=2) 2>/dev/null; echo "rc=$?"
#### command-v
command -v echo; type -t cd; command -v nosuchcmd_xyz || echo missing
#### nullglob
shopt -s nullglob; x=(*.nomatch); echo "${#x[@]}"
#### export-env
export FOO=bar; bash_child() { printenv FOO; }; bash_child; FOO2=inline printenv FOO2
#### cd-pwd-relative
cd src && cd lib && basename "$(pwd)" && cd .. && basename "$PWD"
#### source-file
printf 'sourced_var=ok\n' > lib.sh; . ./lib.sh; source lib.sh; echo $sourced_var
#### xtrace
set -x; echo traced 2>/dev/null; set +x
