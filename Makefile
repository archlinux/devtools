all:

install:
	# extrapkg/checkpkg and friends
	mkdir -p $(DESTDIR)/usr/bin
	install -m 755 checkpkg $(DESTDIR)/usr/bin
	install -m 755 extrapkg $(DESTDIR)/usr/bin
	ln -sf extrapkg $(DESTDIR)/usr/bin/corepkg
	ln -sf extrapkg $(DESTDIR)/usr/bin/testingpkg
	ln -sf extrapkg $(DESTDIR)/usr/bin/unstablepkg
	# new chroot tools, only usable by root
	mkdir -p $(DESTDIR)/usr/sbin
	install -m 755 mkarchroot $(DESTDIR)/usr/sbin
	install -m 755 makechrootpkg $(DESTDIR)/usr/sbin
	#Additional packaging helper scripts
	install -m 755 lddd $(DESTDIR)/usr/bin
	install -m 755 finddeps $(DESTDIR)/usr/bin

uninstall:
	# remove all files we installed
	rm $(DESTDIR)/usr/bin/checkpkg
	rm $(DESTDIR)/usr/bin/extrapkg
	rm $(DESTDIR)/usr/bin/corepkg
	rm $(DESTDIR)/usr/bin/testingpkg
	rm $(DESTDIR)/usr/bin/unstablepkg
	rm $(DESTDIR)/usr/sbin/mkarchroot
	rm $(DESTDIR)/usr/sbin/makechrootpkg
	rm $(DESTDIR)/usr/bin/lddd
	rm $(DESTDIR)/usr/bin/finddeps
