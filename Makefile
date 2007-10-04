all:

install:
	mkdir -p $(DESTDIR)/usr/bin
	install -m 755 checkpkg $(DESTDIR)/usr/bin
	install -m 755 extrapkg $(DESTDIR)/usr/bin
	install -m 755 mkarchroot $(DESTDIR)/usr/bin
	ln -s extrapkg $(DESTDIR)/usr/bin/corepkg
	ln -s extrapkg $(DESTDIR)/usr/bin/testingpkg
	ln -s extrapkg $(DESTDIR)/usr/bin/unstablepkg
