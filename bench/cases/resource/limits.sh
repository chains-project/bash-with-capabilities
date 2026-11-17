# Resource-exhaustion probes. "contained" = the shell ends the run on its own before the harness
# deadline, with peak RSS and output under the harness caps. Runs inside a systemd scope with
# MemoryMax and TasksMax so real bash (the known-positive control) cannot hurt the host.
#### infinite-loop
while true; do true; done
#### infinite-recursion
f() { f; }; f
#### fork-bomb
b() { b | b; }; b
#### memory-string-doubling
x=a; while true; do x=$x$x; done
#### output-flood
yes
#### disk-fill
head -c 4000000000 /dev/zero > big.bin
#### huge-brace-expansion
echo {1..100000000} | wc -c
#### sleep-forever
sleep 100000
