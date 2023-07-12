# Complete Reset of the Console Services

At times the easiest way to get console services back up and running is to do a complete
reset of the services. There is no perisent state so there is no backup/restore operation
needed.

> **`NOTE`** The console connections to all nodes will be disrupted for the duration of this
procedre. Any active console sessions will be terminated and no console logging will occur.
The existing console log files will be retained, but there will be a gap in the log file coverage.

suspend

## Find the 
cleardata

scale down console node pods

reinstall cray-console-data (optional)

resume