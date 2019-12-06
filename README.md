# scd
Smart Command Dispatch System

# usage 
if you have many machine to dispatch your command.  on machine A0, A1, A2, and so on.  run
```
./slave
```

you also need a machines to sumit you command (the same or not the same as previous machine, it doesnot matter). let's called it B machine.
on B, run
```
./submit
```

then you can sumit your command in the prompt.
your command will be consumed by one of you Axxx machine.

a log file will saved on each slave. 

