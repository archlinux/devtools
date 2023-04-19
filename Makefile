SHELL=/bin/bash

V=20230307
BUILDTOOLVER ?= $(V)

PREFIX = /usr/local
MANDIR = $(PREFIX)/share/man
DATADIR = $(PREFIX)/share/devtools
BUILDDIR = build

rwildcard=$(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

BINPROGS_SRC = $(wildcard src/*.in)
BINPROGS = $(addprefix $(BUILDDIR)/,$(patsubst src/%,bin/%,$(patsubst %.in,%,$(BINPROGS_SRC))))
LIBRARY_SRC = $(call rwildcard,src/lib,*.sh)
LIBRARY = $(addprefix $(BUILDDIR)/,$(patsubst src/%,%,$(patsubst %.in,%,$(LIBRARY_SRC))))
MAKEPKG_CONFIGS=$(wildcard config/makepkg/*)
PACMAN_CONFIGS=$(wildcard config/pacman/*)
SETARCH_ALIASES = $(wildcard config/setarch-aliases.d/*)
MANS = $(addprefix $(BUILDDIR)/,$(patsubst %.asciidoc,%,$(wildcard doc/man/*.asciidoc)))

COMMITPKG_LINKS = \
	core-testingpkg \
	core-stagingpkg \
	extrapkg \
	extra-testingpkg \
	extra-stagingpkg \
	multilibpkg \
	multilib-testingpkg \
	multilib-stagingpkg \
	kde-unstablepkg \
	gnome-unstablepkg

ARCHBUILD_LINKS = \
	extra-x86_64-build \
	extra-x86_64_v3-build \
	testing-x86_64-build \
	testing-x86_64_v3-build \
	staging-x86_64-build \
	staging-x86_64_v3-build \
	multilib-build \
	multilib-testing-build \
	multilib-staging-build \
	kde-unstable-x86_64-build \
	gnome-unstable-x86_64-build

COMPLETIONS = $(addprefix $(BUILDDIR)/,$(patsubst %.in,%,$(wildcard contrib/completion/*/*)))


all: binprogs library conf completion man
binprogs: $(BINPROGS)
library: $(LIBRARY)
completion: $(COMPLETIONS)
man: $(MANS)


ifneq ($(wildcard *.in),)
	$(error Legacy in prog file found: $(wildcard *.in) - please migrate to src/*)
endif
ifneq ($(wildcard pacman-*.conf),)
	$(error Legacy pacman config file found: $(wildcard pacman-*.conf) - please migrate to config/pacman/*)
endif
ifneq ($(wildcard makepkg-*.conf),)
	$(error Legacy makepkg config files found: $(wildcard makepkg-*.conf) -  please migrate to config/makepkg/*)
endif
ifneq ($(wildcard setarch-aliases.d/*),)
	$(error Legacy setarch aliase found: $(wildcard setarch-aliases.d/*) - please migrate to config/setarch-aliases.d/*)
endif


edit = sed \
	-e "s|@pkgdatadir[@]|$(DATADIR)|g" \
	-e "s|@buildtoolver[@]|$(BUILDTOOLVER)|g"
GEN_MSG = @echo "GEN $(patsubst $(BUILDDIR)/%,%,$@)"

define buildInScript
$(1)/%: $(2)%$(3)
	$$(GEN_MSG)
	@mkdir -p $$(dir $$@)
	@$(RM) "$$@"
	@cat $$< | $(edit) >$$@
	@chmod $(4) "$$@"
	@bash -O extglob -n "$$@"
endef

$(eval $(call buildInScript,build/bin,src/,.in,755))
$(eval $(call buildInScript,build/lib,src/lib/,,644))
$(foreach completion,$(wildcard contrib/completion/*),$(eval $(call buildInScript,build/$(completion),$(completion)/,.in,444)))

$(BUILDDIR)/doc/man/%: doc/man/%.asciidoc doc/asciidoc.conf doc/man/include/footer.asciidoc
	$(GEN_MSG)
	@mkdir -p $(BUILDDIR)/doc/man
	@a2x --no-xmllint --asciidoc-opts="-f doc/asciidoc.conf" -d manpage -f manpage --destination-dir=$(BUILDDIR)/doc/man -a pkgdatadir=$(DATADIR) $<

conf:
	@install -d $(BUILDDIR)/makepkg.conf.d $(BUILDDIR)/pacman.conf.d
	@cp -a $(MAKEPKG_CONFIGS) $(BUILDDIR)/makepkg.conf.d
	@cp -a $(PACMAN_CONFIGS) $(BUILDDIR)/pacman.conf.d

clean:
	rm -rf $(BUILDDIR)

install: all
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -dm0755 $(DESTDIR)$(DATADIR)/setarch-aliases.d
	install -dm0755 $(DESTDIR)$(DATADIR)/makepkg.conf.d
	install -dm0755 $(DESTDIR)$(DATADIR)/pacman.conf.d
	install -m0755 ${BINPROGS} $(DESTDIR)$(PREFIX)/bin
	install -dm0755 $(DESTDIR)$(DATADIR)/lib
	cp -ra $(BUILDDIR)/lib/* $(DESTDIR)$(DATADIR)/lib
	for conf in $(notdir $(MAKEPKG_CONFIGS)); do install -Dm0644 $(BUILDDIR)/makepkg.conf.d/$$conf $(DESTDIR)$(DATADIR)/makepkg.conf.d/$${conf##*/}; done
	for conf in $(notdir $(PACMAN_CONFIGS)); do install -Dm0644 $(BUILDDIR)/pacman.conf.d/$$conf $(DESTDIR)$(DATADIR)/pacman.conf.d/$${conf##*/}; done
	for a in ${SETARCH_ALIASES}; do install -m0644 $$a -t $(DESTDIR)$(DATADIR)/setarch-aliases.d; done
	for l in ${COMMITPKG_LINKS}; do ln -sf commitpkg $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do ln -sf archbuild $(DESTDIR)$(PREFIX)/bin/$$l; done
	ln -sf find-libdeps $(DESTDIR)$(PREFIX)/bin/find-libprovides
	install -Dm0644 $(BUILDDIR)/contrib/completion/bash/devtools $(DESTDIR)$(PREFIX)/share/bash-completion/completions/devtools
	for f in $(notdir $(BINPROGS)); do ln -sf devtools $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$$f; done
	install -Dm0644 $(BUILDDIR)/contrib/completion/zsh/_devtools $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	for manfile in $(MANS); do \
		install -Dm644 $$manfile -t $(DESTDIR)$(MANDIR)/man$${manfile##*.}; \
	done;

uninstall:
	for f in $(notdir $(BINPROGS)); do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in $(notdir $(LIBRARY)); do rm -f $(DESTDIR)$(DATADIR)/lib/$$f; done
	rm -rf $(DESTDIR)$(DATADIR)/lib
	for conf in $(notdir $(MAKEPKG_CONFIGS)); do rm -f $(DESTDIR)$(DATADIR)/makepkg.conf.d/$${conf##*/}; done
	for conf in $(notdir $(PACMAN_CONFIGS)); do rm -f $(DESTDIR)$(DATADIR)/pacman.conf.d/$${conf##*/}; done
	for f in $(notdir $(SETARCH_ALIASES)); do rm -f $(DESTDIR)$(DATADIR)/setarch-aliases.d/$$f; done
	for l in ${COMMITPKG_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/devtools
	for f in $(notdir $(BINPROGS)); do rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$$f; done
	rm -f $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	rm -f $(DESTDIR)$(PREFIX)/bin/find-libprovides
	for manfile in $(notdir $(MANS)); do rm -f $(DESTDIR)$(MANDIR)/man$${manfile##*.}/$${manfile}; done;
	rmdir --ignore-fail-on-non-empty \
		$(DESTDIR)$(DATADIR)/setarch-aliases.d \
		$(DESTDIR)$(DATADIR)/makepkg.conf.d \
		$(DESTDIR)$(DATADIR)/pacman.conf.d \
		$(DESTDIR)$(DATADIR)

TODAY=$(shell date +"%Y%m%d")
tag:
	@sed -E "s|^V=[0-9]{8}|V=$(TODAY)|" -i Makefile
	@git commit --gpg-sign --message "Version $(TODAY)" Makefile
	@git tag --sign --message "Version $(TODAY)" $(TODAY)

dist:
	git archive --format=tar --prefix=devtools-$(V)/ $(V) | gzip > devtools-$(V).tar.gz
	gpg --detach-sign --use-agent devtools-$(V).tar.gz

upload:
	scp devtools-$(V).tar.gz devtools-$(V).tar.gz.sig repos.archlinux.org:/srv/ftp/other/devtools/

check: $(BINPROGS_SRC) $(LIBRARY_SRC) contrib/completion/bash/devtools.in config/makepkg/x86_64.conf contrib/makepkg/PKGBUILD.proto
	shellcheck $^

.PHONY: all binprogs library completion conf man clean install uninstall tag dist upload check
.DELETE_ON_ERROR:
