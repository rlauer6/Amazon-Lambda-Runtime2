#-*- mode: makefile; -*-
SHELL := /bin/bash

.SHELLFLAGS := -ec

VERSION := $(shell cat VERSION)

%.pm: %.pm.in
	sed -e 's/[@]PACKAGE_VERSION[@]/$(VERSION)/' < $< > $@

%.pl: %.pl.in
	sed -e 's/[@]PACKAGE_VERSION[@]/$(VERSION)/' < $< > $@

PERL_MODULES = \
    lib/Amazon/Lambda/Runtime.pm \
    lib/Amazon/Lambda/Context.pm

BIN_FILES = \
    bin/plambda.pl \
    bin/bootstrap

TARBALL = Amazon-Lambda-Runtime2-$(VERSION).tar.gz

DEPS = \
    buildspec.yml \
    $(PERL_MODULES) \
    $(BIN_FILES) \
    requires \
    test-requires \
    README.md

all: $(TARBALL)

$(TARBALL): $(DEPS)
	make-cpan-dist.pl -b $<

README.md: lib/Amazon/Lambda/Runtime.pm
	pod2markdown $< > $@

bin/bootstrap: bin/bootstrap.in
	sed -e 's/[@]PACKAGE_VERSION[@]/$(VERSION)/' < $< > $@

include version.mk

include release-notes.mk

clean:
	rm -f $(PERL_MODULES) $(BIN_FILES) *.tmp extra-files resources *.tar.gz
	rm -f release-*.{lst,diffs}
