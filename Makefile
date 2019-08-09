V=20191016

PREFIX = /usr/local
MANDIR = $(PREFIX)/share/man

IN_PROGS = \
	archco \
	arch-nspawn \
	archrelease \
	archbuild \
	checkpkg \
	commitpkg \
	crossrepomove\
	finddeps \
	find-libdeps \
	lddd \
	mkarchroot \
	makechrootpkg \
	rebuildpkgs \
	sogrep

BINPROGS = \
	$(IN_PROGS) \
	offload-build \

CONFIGFILES = \
	makepkg-x86_64.conf \
	pacman-extra.conf \
	pacman-testing.conf \
	pacman-staging.conf \
	pacman-multilib.conf \
	pacman-multilib-testing.conf \
	pacman-multilib-staging.conf \
	pacman-kde-unstable.conf \
	pacman-gnome-unstable.conf

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
	testing-x86_64-build \
	staging-x86_64-build \
	multilib-build \
	multilib-testing-build \
	multilib-staging-build \
	kde-unstable-x86_64-build \
	gnome-unstable-x86_64-build

CROSSREPOMOVE_LINKS = \
	extra2community \
	community2extra

BASHCOMPLETION_LINKS = \
	archco \
	communityco


MANS = \
	doc/lddd.1 \
	doc/checkpkg.1 \
	doc/offload-build.1 \
	doc/sogrep.1 \
	doc/mkarchroot.1 \
	doc/find-libdeps.1 \
	doc/find-libprovides.1


all: $(BINPROGS) bash_completion zsh_completion man
man: $(MANS)

edit = sed -e "s|@pkgdatadir[@]|$(PREFIX)/share/devtools|g"

%: %.in Makefile lib/common.sh
	@echo "GEN $@"
	@$(RM) "$@"
	@{ echo -n 'm4_changequote([[[,]]])'; cat $@.in; } | m4 -P | $(edit) >$@
	@chmod a-w "$@"
	@chmod +x "$@"
	@bash -O extglob -n "$@"

$(MANS): doc/asciidoc.conf doc/footer.asciidoc

doc/%: doc/%.asciidoc
	a2x --no-xmllint --asciidoc-opts="-f doc/asciidoc.conf" -d manpage -f manpage -D doc $<

clean:
	rm -f $(IN_PROGS) bash_completion zsh_completion $(MANS)

install:
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -dm0755 $(DESTDIR)$(PREFIX)/share/devtools
	install -m0755 ${BINPROGS} $(DESTDIR)$(PREFIX)/bin
	install -m0644 ${CONFIGFILES} $(DESTDIR)$(PREFIX)/share/devtools
	for l in ${COMMITPKG_LINKS}; do ln -sf commitpkg $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do ln -sf archbuild $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${CROSSREPOMOVE_LINKS}; do ln -sf crossrepomove $(DESTDIR)$(PREFIX)/bin/$$l; done
	ln -sf find-libdeps $(DESTDIR)$(PREFIX)/bin/find-libprovides
	install -Dm0644 bash_completion $(DESTDIR)/usr/share/bash-completion/completions/devtools
	for l in ${BASHCOMPLETION_LINKS}; do ln -sf devtools $(DESTDIR)/usr/share/bash-completion/completions/$$l; done
	install -Dm0644 zsh_completion $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	ln -sf archco $(DESTDIR)$(PREFIX)/bin/communityco
	for manfile in $(MANS); do \
		install -Dm644 $$manfile -t $(DESTDIR)$(MANDIR)/man$${manfile##*.}; \
	done;

uninstall:
	for f in ${BINPROGS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${CONFIGFILES}; do rm -f $(DESTDIR)$(PREFIX)/share/devtools/$$f; done
	for l in ${COMMITPKG_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${CROSSREPOMOVE_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	rm $(DESTDIR)/usr/share/bash-completion/completions/devtools
	rm $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_devtools
	rm -f $(DESTDIR)$(PREFIX)/bin/communityco
	rm -f $(DESTDIR)$(PREFIX)/bin/find-libprovides
	for manfile in $(MANS); do \
		rm -f $(DESTDIR)$(MANDIR)/man$${manfile##*.}/$${manfile#doc/}; \
	done;

TODAY=$(shell date +"%Y%m%d")
tag:
	@sed -E "s|^V=[0-9]{8}|V=$(TODAY)|" -i Makefile
	@git commit --gpg-sign --message "Version $(TODAY)" Makefile
	@git tag --sign --message "Version $(TODAY)" $(TODAY)

dist:
	git archive --format=tar --prefix=devtools-$(V)/ $(V) | gzip -9 > devtools-$(V).tar.gz
	gpg --detach-sign --use-agent devtools-$(V).tar.gz

upload:
	scp devtools-$(V).tar.gz devtools-$(V).tar.gz.sig repos.archlinux.org:/srv/ftp/other/devtools/

check: $(BINPROGS) bash_completion makepkg-x86_64.conf PKGBUILD.proto
	shellcheck $^

.PHONY: all clean install uninstall dist upload check tag
.DELETE_ON_ERROR:
