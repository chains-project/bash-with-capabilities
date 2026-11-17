#### indexed-basic
a=(one two three); echo "${a[0]}" "${a[2]}" "${#a[@]}"
#### indexed-append-slice
a=(1 2 3); a+=(4 5); echo "${a[@]:1:3}"; a[10]=x; echo "${!a[@]}"
#### indexed-quoted-iter
a=("a b" "c d"); for x in "${a[@]}"; do echo "[$x]"; done
#### assoc
declare -A m; m[k1]=v1; m[k2]=v2; echo "${m[k2]}" "${#m[@]}"; for k in $(printf '%s\n' "${!m[@]}" | sort); do echo "$k=${m[$k]}"; done
#### mapfile
mapfile -t lines < words.txt; echo "${#lines[@]}" "${lines[3]}"
#### array-from-cmd
files=($(ls src/*.py)); echo "${#files[@]}"
#### unset-element
a=(a b c); unset 'a[1]'; echo "${a[@]}" "${#a[@]}"
