test: tinyfts
	./tests.tcl

tinyfts: Makefile tools/titlecat tools/wrap tinyfts-dev.tcl vendor/tacit/tacit-css.min.tcl vendor/wapp/wapp.tcl
	printf '#! /usr/bin/env tclsh\n# tinyfts single-file bundle.\n' > $@
	./tools/titlecat vendor/tacit/tacit-css.min.tcl vendor/wapp/wapp.tcl tinyfts-dev.tcl >> $@
	chmod +x $@

vendor/tacit/tacit-css.min.tcl: vendor/tacit/tacit-css.min.css Makefile tools/wrap
	./tools/wrap $< tinyfts 'dict set state css' > $@

clean:
	-rm tinyfts vendor/tacit/tacit-css.min.tcl

.PHONY: clean test
