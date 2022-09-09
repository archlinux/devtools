V=20230105
BUILDTOOLVER ?= $(V)

PREFIX = /usr/local
MANDIR = $(PREFIX)/share/man
BUILDDIR = build

BINPROGS = $(addprefix $(BUILDDIR)/,$(patsubst src/%,bin/%,$(patsubst %.in,%,$(wildcard src/*.in))))
LIBUTILS = $(wildcard lib/*)
MAKEPKG_CONFIGS=$(wildcard config/makepkg/*)
PACMAN_CONFIGS=$(wildcard config/pacman/*)
SETARCH_ALIASES = $(wildcard config/setarch-aliases.d/*)
MANS = $(addprefix $(BUILDDIR)/,$(patsubst %.asciidoc,%,$(wildcard doc/man/*.asciidoc)))

COMMITPKG_LINKS = \
	extrapkg \
	testingpkg \
	stagingpkg \
	communitypkg \
	community-testingpkg \
	community-stagingpkg \
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


all: binprogs completion man
binprogs: $(BINPROGS)
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


edit = sed -e "s|@pkgdatadir[@]|$(PREFIX)/share/devtools|g"
GEN_MSG = @echo "GEN $(patsubst $(BUILDDIR)/%,%,$@)"

define buildInScript
$(1)/%: $(2)%.in $(LIBUTILS)
	$$(GEN_MSG)
	@mkdir -p $$(dir $$@)
	@$(RM) "$$@"
	@{ echo -n 'm4_changequote([[[,]]])'; cat $$<; } | m4 -P --define=m4_devtools_version=$$(BUILDTOOLVER) | $(edit) >$$@
	@chmod $(3) "$$@"
	@bash -n "$$@"
endef

$(eval $(call buildInScript,build/bin,src/,555))
$(foreach completion,$(wildcard contrib/completion/*),$(eval $(call buildInScript,build/$(completion),$(completion)/,444)))

$(BUILDDIR)/doc/man/%: doc/man/%.asciidoc doc/asciidoc.conf doc/man/include/footer.asciidoc
	$(GEN_MSG)
	@mkdir -p $(BUILDDIR)/doc/man
	@a2x --no-xmllint --asciidoc-opts="-f doc/asciidoc.conf" -d manpage -f manpage --destination-dir=$(BUILDDIR)/doc/man -a pkgdatadir=$(PREFIX)/share/devtools $<

clean:
	rm -rf $(BUILDDIR)

install: all
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -dm0755 $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d
	install -m0755 ${BINPROGS} $(DESTDIR)$(PREFIX)/bin
	for conf in ${MAKEPKG_CONFIGS}; do install -Dm0644 $$conf $(DESTDIR)$(PREFIX)/share/devtools/makepkg-$${conf##*/}; done
	for conf in ${PACMAN_CONFIGS}; do install -Dm0644 $$conf $(DESTDIR)$(PREFIX)/share/devtools/pacman-$${conf##*/}; done
	for a in ${SETARCH_ALIASES}; do install -m0644 $$a -t $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d; done
	for l in ${COMMITPKG_LINKS}; do ln -sf commitpkg $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do ln -sf archbuild $(DESTDIR)$(PREFIX)/bin/$$l; done
	ln -sf find-libdeps $(DESTDIR)$(PREFIX)/bin/find-libprovides
	install -Dm0644 $(BUILDDIR)/contrib/completion/bash/devtools $(DESTDIR)$(PREFIX)/share/bash-completion/completions/devtools
	install -Dm0644 $(BUILDDIR)/contrib/completion/zsh/_devtools $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	for manfile in $(MANS); do \
		install -Dm644 $$manfile -t $(DESTDIR)$(MANDIR)/man$${manfile##*.}; \
	done;

uninstall:
	for f in $(notdir $(BINPROGS)); do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for conf in ${MAKEPKG_CONFIGS}; do rm -f $(DESTDIR)$(PREFIX)/share/devtools/makepkg-$${conf##*/}; done
	for conf in ${PACMAN_CONFIGS}; do rm -f $(DESTDIR)$(PREFIX)/share/devtools/pacman-$${conf##*/}; done
	for f in $(notdir $(SETARCH_ALIASES)); do rm -f $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d/$$f; done
	for l in ${COMMITPKG_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	rm $(DESTDIR)$(PREFIX)/share/bash-completion/completions/devtools
	rm $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	rm -f $(DESTDIR)$(PREFIX)/bin/find-libprovides
	for manfile in $(notdir $(MANS)); do rm -f $(DESTDIR)$(MANDIR)/man$${manfile##*.}/$${manfile}; done;
	rmdir --ignore-fail-on-non-empty $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d $(DESTDIR)$(PREFIX)/share/devtools

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

check: $(BINPROGS) $(BUILDDIR)/contrib/completion/bash/devtools config/makepkg/x86_64.conf contrib/makepkg/PKGBUILD.proto
	shellcheck $^

.PHONY: all completion man clean install uninstall dist upload check tag
.DELETE_ON_ERROR:
