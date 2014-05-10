V=20140510

PREFIX = /usr/local

BINPROGS = \
	checkpkg \
	commitpkg \
	archco \
	archrelease \
	archrm \
	archbuild \
	lddd \
	finddeps \
	rebuildpkgs \
	find-libdeps \
	crossrepomove\
	arch-nspawn \
	mkarchroot \
	makechrootpkg

CONFIGFILES = \
	makepkg-i686.conf \
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
	corepkg \
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
	extra-i686-build \
	extra-x86_64-build \
	testing-i686-build \
	testing-x86_64-build \
	staging-i686-build \
	staging-x86_64-build \
	multilib-build \
	multilib-testing-build \
	multilib-staging-build \
	kde-unstable-i686-build \
	kde-unstable-x86_64-build \
	gnome-unstable-i686-build \
	gnome-unstable-x86_64-build

CROSSREPOMOVE_LINKS = \
	extra2community \
	community2extra

BASHCOMPLETION_LINKS = \
	archco \
	communityco

all: $(BINPROGS) bash_completion zsh_completion

edit = sed -e "s|@pkgdatadir[@]|$(DESTDIR)$(PREFIX)/share/devtools|g"

%: %.in Makefile lib/common.sh
	@echo "GEN $@"
	@$(RM) "$@"
	@m4 -P $@.in | $(edit) >$@
	@chmod a-w "$@"
	@chmod +x "$@"
	@bash -O extglob -n "$@"

clean:
	rm -f $(BINPROGS) bash_completion zsh_completion

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

dist:
	git archive --format=tar --prefix=devtools-$(V)/ $(V) | gzip -9 > devtools-$(V).tar.gz
	gpg --detach-sign --use-agent devtools-$(V).tar.gz

upload:
	scp devtools-$(V).tar.gz devtools-$(V).tar.gz.sig nymeria.archlinux.org:/srv/ftp/other/devtools/

.PHONY: all clean install uninstall dist upload
