V=20220621
BUILDTOOLVER ?= $(V)

PREFIX = /usr/local
MANDIR = $(PREFIX)/share/man
BUILDDIR = build

BINPROGS = \
	archco \
	arch-nspawn \
	archrelease \
	archbuild \
	checkpkg \
	commitpkg \
	crossrepomove\
	diffpkg \
	export-pkgbuild-keys \
	finddeps \
	find-libdeps \
	lddd \
	makerepropkg \
	mkarchroot \
	makechrootpkg \
	offload-build \
	rebuildpkgs \
	sogrep
BINPROGS := $(addprefix $(BUILDDIR)/bin/,$(BINPROGS))

CONFIGFILES = \
	makepkg-x86_64.conf \
	makepkg-x86_64_v3.conf \
	pacman-extra.conf \
	pacman-extra-x86_64_v3.conf \
	pacman-testing.conf \
	pacman-testing-x86_64_v3.conf \
	pacman-staging.conf \
	pacman-staging-x86_64_v3.conf \
	pacman-multilib.conf \
	pacman-multilib-testing.conf \
	pacman-multilib-staging.conf \
	pacman-kde-unstable.conf \
	pacman-gnome-unstable.conf

SETARCH_ALIASES = \
	x86_64_v3

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

CROSSREPOMOVE_LINKS = \
	extra2community \
	community2extra

COMPLETIONS = \
	bash_completion \
	zsh_completion
COMPLETIONS := $(addprefix $(BUILDDIR)/completion/,$(COMPLETIONS))

BASHCOMPLETION_LINKS = \
	archco \
	communityco

MANS = \
	archbuild.1 \
	arch-nspawn.1 \
	export-pkgbuild-keys.1 \
	makechrootpkg.1 \
	lddd.1 \
	checkpkg.1 \
	diffpkg.1 \
	offload-build.1 \
	sogrep.1 \
	makerepropkg.1 \
	mkarchroot.1 \
	find-libdeps.1 \
	find-libprovides.1 \
	devtools.7
MANS := $(addprefix $(BUILDDIR)/doc/,$(MANS))


all: binprogs completion man
binprogs: $(BINPROGS)
completion: $(COMPLETIONS)
man: $(MANS)

edit = sed -e "s|@pkgdatadir[@]|$(PREFIX)/share/devtools|g"

$(BUILDDIR)/bin/% $(BUILDDIR)/completion/%: %.in Makefile $(wildcard lib/*.sh)
	@echo "GEN $(notdir $@)"
	@mkdir -p $(dir $@)
	@$(RM) "$@"
	@{ echo -n 'm4_changequote([[[,]]])'; cat $<; } | m4 -P --define=m4_devtools_version=$(BUILDTOOLVER) | $(edit) >$@
	@chmod a-w "$@"
	@chmod +x "$@"
	@bash -O extglob -n "$@"

$(BUILDDIR)/doc/%: doc/%.asciidoc doc/asciidoc.conf doc/footer.asciidoc
	@mkdir -p $(BUILDDIR)/doc
	a2x --no-xmllint --asciidoc-opts="-f doc/asciidoc.conf" -d manpage -f manpage --destination-dir=$(BUILDDIR)/doc -a pkgdatadir=$(PREFIX)/share/devtools $<

clean:
	rm -rf $(BUILDDIR)

install: all
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -dm0755 $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d
	install -m0755 ${BINPROGS} $(DESTDIR)$(PREFIX)/bin
	install -m0644 ${CONFIGFILES} $(DESTDIR)$(PREFIX)/share/devtools
	for a in ${SETARCH_ALIASES}; do install -m0644 setarch-aliases.d/$$a $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d; done
	for l in ${COMMITPKG_LINKS}; do ln -sf commitpkg $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do ln -sf archbuild $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${CROSSREPOMOVE_LINKS}; do ln -sf crossrepomove $(DESTDIR)$(PREFIX)/bin/$$l; done
	ln -sf find-libdeps $(DESTDIR)$(PREFIX)/bin/find-libprovides
	install -Dm0644 $(BUILDDIR)/bash_completion $(DESTDIR)$(PREFIX)/share/bash-completion/completions/devtools
	for l in ${BASHCOMPLETION_LINKS}; do ln -sf devtools $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$$l; done
	install -Dm0644 $(BUILDDIR)/zsh_completion $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	ln -sf archco $(DESTDIR)$(PREFIX)/bin/communityco
	for manfile in $(MANS); do \
		install -Dm644 $$manfile -t $(DESTDIR)$(MANDIR)/man$${manfile##*.}; \
	done;

uninstall:
	for f in $(notdir $(BINPROGS)); do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${CONFIGFILES}; do rm -f $(DESTDIR)$(PREFIX)/share/devtools/$$f; done
	for f in ${SETARCH_ALIASES}; do rm -f $(DESTDIR)$(PREFIX)/share/devtools/setarch-aliases.d/$$f; done
	for l in ${COMMITPKG_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${CROSSREPOMOVE_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${BASHCOMPLETION_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$$l; done
	rm $(DESTDIR)$(PREFIX)/share/bash-completion/completions/devtools
	rm $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	rm -f $(DESTDIR)$(PREFIX)/bin/communityco
	rm -f $(DESTDIR)$(PREFIX)/bin/find-libprovides
	for manfile in $(notdir $(MANS)); do rm -f $(DESTDIR)$(MANDIR)/man$${manfile##*.}/$${manfile}; done;

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

check: $(BINPROGS) $(BUILDDIR)/bash_completion makepkg-x86_64.conf PKGBUILD.proto
	shellcheck $^

.PHONY: all completion man clean install uninstall dist upload check tag
.DELETE_ON_ERROR:
