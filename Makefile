all:scd_submit scd_slave

scd_submit: scd.PL
	@cp scd.PL submit.PL
	@echo generate scd submit
scd_slave: scd.PL
	@cp scd.PL slave.PL
	@echo generate scd slave
clean:
	rm -f submit.PL slave.PL 
