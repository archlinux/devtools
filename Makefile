V=0.9.13

all:

install:
	# commitpkg/checkpkg and friends
	install -d -m755 $(DESTDIR)/usr/bin
	install -m 755 checkpkg $(DESTDIR)/usr/bin
	install -m 755 commitpkg $(DESTDIR)/usr/bin
	ln -sf commitpkg $(DESTDIR)/usr/bin/extrapkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/corepkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/testingpkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/stagingpkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/communitypkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/community-testingpkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/community-stagingpkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/multilibpkg
	ln -sf commitpkg $(DESTDIR)/usr/bin/multilib-testingpkg
	# arch{co,release,rm}
	install -m 755 archco $(DESTDIR)/usr/bin
	install -m 755 communityco $(DESTDIR)/usr/bin
	install -m 755 archrelease $(DESTDIR)/usr/bin
	install -m 755 archrm $(DESTDIR)/usr/bin
	# new chroot tools, only usable by root
	install -d -m 755 $(DESTDIR)/usr/sbin
	install -m 755 mkarchroot $(DESTDIR)/usr/sbin
	install -m 755 makechrootpkg $(DESTDIR)/usr/sbin
	install -m 755 archbuild $(DESTDIR)/usr/bin
	ln -sf archbuild $(DESTDIR)/usr/bin/extra-i686-build
	ln -sf archbuild $(DESTDIR)/usr/bin/extra-x86_64-build
	ln -sf archbuild $(DESTDIR)/usr/bin/testing-i686-build
	ln -sf archbuild $(DESTDIR)/usr/bin/testing-x86_64-build
	ln -sf archbuild $(DESTDIR)/usr/bin/staging-i686-build
	ln -sf archbuild $(DESTDIR)/usr/bin/staging-x86_64-build
	ln -sf archbuild $(DESTDIR)/usr/bin/multilib-build
	ln -sf archbuild $(DESTDIR)/usr/bin/multilib-testing-build
	# Additional packaging helper scripts
	install -m 755 lddd $(DESTDIR)/usr/bin
	install -m 755 finddeps $(DESTDIR)/usr/bin
	install -m 755 rebuildpkgs $(DESTDIR)/usr/bin
	# install default config
	install -d -m755 $(DESTDIR)/usr/share/devtools
	install -m 644 makepkg-i686.conf $(DESTDIR)/usr/share/devtools
	install -m 644 makepkg-x86_64.conf $(DESTDIR)/usr/share/devtools
	install -m 644 pacman-extra.conf $(DESTDIR)/usr/share/devtools
	install -m 644 pacman-testing.conf $(DESTDIR)/usr/share/devtools
	install -m 644 pacman-staging.conf $(DESTDIR)/usr/share/devtools
	install -m 644 pacman-multilib.conf $(DESTDIR)/usr/share/devtools
	install -m 644 pacman-multilib-testing.conf $(DESTDIR)/usr/share/devtools

uninstall:
	# remove all files we installed
	rm $(DESTDIR)/usr/bin/checkpkg
	rm $(DESTDIR)/usr/bin/commitpkg
	rm $(DESTDIR)/usr/bin/extrapkg
	rm $(DESTDIR)/usr/bin/corepkg
	rm $(DESTDIR)/usr/bin/testingpkg
	rm $(DESTDIR)/usr/bin/stagingpkg
	rm $(DESTDIR)/usr/bin/communitypkg
	rm $(DESTDIR)/usr/bin/community-testingpkg
	rm $(DESTDIR)/usr/bin/community-stagingpkg
	rm $(DESTDIR)/usr/bin/multilibpkg
	rm $(DESTDIR)/usr/bin/multilib-testingpkg
	rm $(DESTDIR)/usr/sbin/mkarchroot
	rm $(DESTDIR)/usr/sbin/makechrootpkg
	rm $(DESTDIR)/usr/bin/extra-i686-build
	rm $(DESTDIR)/usr/bin/extra-x86_64-build
	rm $(DESTDIR)/usr/bin/testing-i686-build
	rm $(DESTDIR)/usr/bin/testing-x86_64-build
	rm $(DESTDIR)/usr/bin/staging-i686-build
	rm $(DESTDIR)/usr/bin/staging-x86_64-build
	rm $(DESTDIR)/usr/bin/multilib-build
	rm $(DESTDIR)/usr/bin/multilib-testing-build
	rm $(DESTDIR)/usr/bin/lddd
	rm $(DESTDIR)/usr/bin/finddeps
	rm $(DESTDIR)/usr/bin/archco
	rm $(DESTDIR)/usr/bin/archrelease
	rm $(DESTDIR)/usr/bin/archrm
	rm $(DESTDIR)/usr/bin/communityco
	rm $(DESTDIR)/usr/bin/rebuildpkgs
	rm $(DESTDIR)/usr/share/devtools/makepkg-i686.conf
	rm $(DESTDIR)/usr/share/devtools/makepkg-x86_64.conf
	rm $(DESTDIR)/usr/share/devtools/pacman-extra.conf
	rm $(DESTDIR)/usr/share/devtools/pacman-testing.conf
	rm $(DESTDIR)/usr/share/devtools/pacman-staging.conf
	rm $(DESTDIR)/usr/share/devtools/pacman-multilib.conf
	rm $(DESTDIR)/usr/share/devtools/pacman-multilib-testing.conf

dist:
	git archive --format=tar --prefix=devtools-$(V)/ $(V) | gzip -9 > devtools-$(V).tar.gz
