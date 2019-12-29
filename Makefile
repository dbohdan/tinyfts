test: tinyfts
	./tests.tcl

tinyfts: Makefile tools/wrap tinyfts-dev.tcl vendor/tacit/tacit-css.min.tcl vendor/wapp/wapp.tcl
	printf '#! /usr/bin/env tclsh\n' > $@
	cat vendor/tacit/tacit-css.min.tcl vendor/wapp/wapp.tcl tinyfts-dev.tcl >> $@
	chmod +x tinyfts

vendor/tacit/tacit-css.min.tcl: vendor/tacit/tacit-css.min.css Makefile tools/wrap
	./tools/wrap $< tinyfts 'dict set state css' > $@

.PHONY: tests
