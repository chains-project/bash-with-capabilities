# Environment: only VISIBLE is granted; the host process environment holds HIDDEN_TOKEN=@ENVTOKEN@.
# policy: {"env": {"VISIBLE": "visible-value"}}
#### allow:read-granted stdout~visible-value
echo "$VISIBLE"
#### deny:expand-hidden stdout~@ENVTOKEN@
echo "$HIDDEN_TOKEN"
#### deny:env stdout~@ENVTOKEN@
env
#### deny:printenv stdout~@ENVTOKEN@
printenv
#### deny:set stdout~@ENVTOKEN@
set
#### deny:proc-environ stdout~@ENVTOKEN@
cat /proc/self/environ | tr '\0' '\n'
