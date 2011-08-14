V=0.9.25

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
	rebuildpkgs

SBINPROGS = \
	mkarchroot \
	makechrootpkg

CONFIGFILES = \
	makepkg-i686.conf \
	makepkg-x86_64.conf \
	pacman-extra.conf \
	pacman-testing.conf \
	pacman-staging.conf \
	pacman-multilib.conf \
	pacman-multilib-testing.conf

COMMITPKG_LINKS = \
	extrapkg \
	corepkg \
	testingpkg \
	stagingpkg \
	communitypkg \
	community-testingpkg \
	community-stagingpkg \
	multilibpkg \
	multilib-testingpkg

ARCHBUILD_LINKS = \
	extra-i686-build \
	extra-x86_64-build \
	testing-i686-build \
	testing-x86_64-build \
	staging-i686-build \
	staging-x86_64-build \
	multilib-build \
	multilib-testing-build

all:

install:
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -dm0755 $(DESTDIR)$(PREFIX)/sbin
	install -dm0755 $(DESTDIR)$(PREFIX)/share/devtools
	install -m0755 ${BINPROGS} $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${SBINPROGS} $(DESTDIR)$(PREFIX)/sbin
	install -m0644 ${CONFIGFILES} $(DESTDIR)$(PREFIX)/share/devtools
	for l in ${COMMITPKG_LINKS}; do ln -sf commitpkg $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do ln -sf archbuild $(DESTDIR)$(PREFIX)/bin/$$l; done
	install -Dm0644 bash_completion $(DESTDIR)/etc/bash_completion.d/devtools
	ln -sf archco $(DESTDIR)$(PREFIX)/bin/communityco

uninstall:
	for f in ${BINPROGS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${SBINPROGS}; do rm -f $(DESTDIR)$(PREFIX)/sbin/$$f; done
	for f in ${CONFIGFILES}; do rm -f $(DESTDIR)$(PREFIX)/share/devtools/$$f; done
	for l in ${COMMITPKG_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$l; done
	rm $(DESTDIR)/etc/bash_completion.d/devtools
	rm -f $(DESTDIR)$(PREFIX)/bin/communityco

dist:
	git archive --format=tar --prefix=devtools-$(V)/ $(V) | gzip -9 > devtools-$(V).tar.gz

upload:
	scp devtools-$(V).tar.gz gerolde.archlinux.org:/srv/ftp/other/devtools/

.PHONY: all install uninstall dist upload
