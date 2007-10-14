all:

install:
	# extrapkg/checkpkg and friends
	mkdir -p $(DESTDIR)/usr/bin
	install -m 755 checkpkg $(DESTDIR)/usr/bin
	install -m 755 extrapkg $(DESTDIR)/usr/bin
	ln -s extrapkg $(DESTDIR)/usr/bin/corepkg
	ln -s extrapkg $(DESTDIR)/usr/bin/testingpkg
	ln -s extrapkg $(DESTDIR)/usr/bin/unstablepkg
	# new chroot tools, only usable by root
	mkdir -p $(DESTDIR)/usr/sbin
	install -m 755 mkarchroot $(DESTDIR)/usr/sbin
	install -m 755 makechrootpkg $(DESTDIR)/usr/sbin
