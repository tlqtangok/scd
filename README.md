# scd
Smart Command Dispatch System

# usage 

there is a build-version of ubuntu-x64 version there.
one may run following command to generate it.
```
cd rel
bash startup.sh
```

then you will see file `slave`, `submit` there !


if you have many machines to dispatch your commands. such as on machine A0, A1, A2, you don't have to login in via ssh to run your command there. just use scd's `slave` here !

```
./slave
```

you also need a machines to sumit you command (the same or not the same as previous machine, it doesnot matter). let's called it B machine.
on B, run
```
./submit
```

then you can sumit your command in the prompt.
your command will be consumed by one of you slave.

a log file will saved on each slave. 

