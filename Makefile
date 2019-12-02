all:scd_submit scd_slave

scd_submit: scd.PL
	@cp scd.PL submit.PL
	@echo generate $@
scd_slave: scd.PL
	@cp scd.PL slave.PL
	@echo generate $@
clean:
	rm -f submit.PL slave.PL 
