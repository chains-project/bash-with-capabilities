#### single-double-mix
echo 'single $x' "double \"quoted\"" 'it'\''s'
#### ansi-c-quote
echo $'tab\there' $'line1\nline2'
#### backslash-escapes
echo a\ b \$x \\ "back\\slash"
#### quote-in-subst
echo "$(echo "a 'b' \"c\"")"
#### printf-escapes
printf '%s|%5s|%-5s|%03d|%.2f|%x\n' str right left 7 3.14159 255
#### printf-reuse-format
printf '%s=%s\n' a 1 b 2 c 3
#### printf-q
printf '%q\n' "a b'c"
#### empty-args
f() { echo $#; }; f "" ""; f
#### echo-flags
echo -n "no newline"; echo; echo -e 'a\tb'
