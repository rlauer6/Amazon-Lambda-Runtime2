#-*- mode: makefile; -*-
SHELL := /bin/bash

.SHELLFLAGS := -ec

VERSION := $(shell cat VERSION)

%.pm: %.pm.in
	sed -e 's/[@]PACKAGE_VERSION[@]/$(VERSION)/' < $< > $@

%.pl: %.pl.in
	sed -e 's/[@]PACKAGE_VERSION[@]/$(VERSION)/' < $< > $@
	chmod +x $@

PERL_MODULES = \
    lib/Amazon/Lambda/Runtime.pm \
    lib/Amazon/Lambda/Runtime/Context.pm \
    lib/Amazon/Lambda/Runtime/Event.pm \
    lib/Amazon/Lambda/Runtime/Event/Base.pm \
    lib/Amazon/Lambda/Runtime/Event/S3.pm \
    lib/Amazon/Lambda/Runtime/Event/SNS.pm \
    lib/Amazon/Lambda/Runtime/Event/SQS.pm \
    lib/Amazon/Lambda/Runtime/Event/EventBridge.pm \
    lib/Amazon/Lambda/Runtime/Writer.pm

BIN_FILES = \
    bin/plambda.pl \
    bin/bootstrap

TARBALL = Amazon-Lambda-Runtime-$(VERSION).tar.gz

DEPS = \
    buildspec.yml \
    $(PERL_MODULES) \
    $(BIN_FILES) \
    requires \
    test-requires \
    LambdaHandler.pm.in \
    README.md

all: $(TARBALL)

$(TARBALL): $(DEPS)
	make-cpan-dist.pl -b $<

README.md: lib/Amazon/Lambda/Runtime.pm
	pod2markdown $< > $@

bin/bootstrap: bin/bootstrap.in
	sed -e 's/[@]PACKAGE_VERSION[@]/$(VERSION)/' < $< > $@
	chmod +x $@

include version.mk

include release-notes.mk

CLEANFILES = \
    $(BIN_FILES) \
    $(PERL_MODULES) \
    *.tar.gz \
    *.tmp \
    extra-files \
    provides \
    resources \
    resources \
    release-*.{lst,diffs}

clean:
	rm -f $(CLEANFILES)
