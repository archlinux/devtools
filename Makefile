V=0.9.20

BINPROGS = \
	checkpkg \
	commitpkg \
	archco \
	communityco \
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
	install -dm0755 $(DESTDIR)/usr/bin
	install -dm0755 $(DESTDIR)/usr/sbin
	install -dm0755 $(DESTDIR)/usr/share/devtools
	install -m0755 ${BINPROGS} $(DESTDIR)/usr/bin
	install -m0755 ${SBINPROGS} $(DESTDIR)/usr/sbin
	install -m0644 ${CONFIGFILES} $(DESTDIR)/usr/share/devtools
	for l in ${COMMITPKG_LINKS}; do ln -sf commitpkg $(DESTDIR)/usr/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do ln -sf archbuild $(DESTDIR)/usr/bin/$$l; done

uninstall:
	for f in ${BINPROGS}; do rm -f $(DESTDIR)/usr/bin/$$f; done
	for f in ${SBINPROGS}; do rm -f $(DESTDIR)/usr/sbin/$$f; done
	for f in ${CONFIGFILES}; do rm -f $(DESTDIR)/usr/share/devtools/$$f; done
	for l in ${COMMITPKG_LINKS}; do rm -f $(DESTDIR)/usr/bin/$$l; done
	for l in ${ARCHBUILD_LINKS}; do rm -f $(DESTDIR)/usr/bin/$$l; done

dist:
	git archive --format=tar --prefix=devtools-$(V)/ $(V) | gzip -9 > devtools-$(V).tar.gz

upload:
	scp devtools-$(V).tar.gz gerolde.archlinux.org:/srv/ftp/other/devtools/

.PHONY: all install uninstall dist upload
