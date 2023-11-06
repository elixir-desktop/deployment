DESTDIR=
LIBDIR=lib
PKGCONFIGDIR=usr/lib/pkgconfig
INCLUDEDIR=usr/include

all: clean build

gendir:
	mkdir -p $(DESTDIR)/$(LIBDIR) 2>/dev/null || true
	mkdir -p $(DESTDIR)/$(SBINDIR) 2>/dev/null || true
	mkdir -p $(DESTDIR)/$(INCLUDEDIR)/selinux 2>/dev/null || true
	mkdir -p $(DESTDIR)/$(INCLUDEDIR)/semanage 2>/dev/null || true
	mkdir -p $(DESTDIR)/$(INCLUDEDIR)/sepol 2>/dev/null || true
	mkdir -p $(DESTDIR)/$(PKGCONFIGDIR) 2>/dev/null || true

build:
	mkdir build 2>/dev/null || true
	gcc -O3 -s -shared -o build/libselinux.so -Wl,--version-script,src/lib/libselinux.map -Isrc/lib/ src/lib/selinux/* src/dummy/dummy.c
	gcc -O3 -s -shared -o build/libsemanage.so -Wl,--version-script,src/lib/libsemanage.map -Isrc/lib/ src/lib/semanage/* src/dummy/dummy.c
	gcc -O3 -s -shared -o build/libsepol.so -Wl,--version-script,src/lib/libsepol.map -Isrc/lib/ src/lib/sepol/*.c src/dummy/dummy.c
	gcc -O3 -s -o build/dummy src/dummy/dummy.c

install: gendir install-lib

install-lib:
	install build/libselinux.so $(DESTDIR)/$(LIBDIR)/libselinux.so.1
	install build/libsemanage.so $(DESTDIR)/$(LIBDIR)/libsemanage.so.1
	install build/libsepol.so $(DESTDIR)/$(LIBDIR)/libsepol.so.1
	ln -s libselinux.so.1 $(DESTDIR)/$(LIBDIR)/libselinux.so || true
	ln -s libsemanage.so.1 $(DESTDIR)/$(LIBDIR)/libsemanage.so || true
	ln -s libsepol.so.1 $(DESTDIR)/$(LIBDIR)/libsepol.so || true
	install src/pkgconfig/selinux.pc $(DESTDIR)/$(PKGCONFIGDIR)/libselinux.pc
	cp -prfv src/header/semanage/*.h $(DESTDIR)/$(INCLUDEDIR)/semanage/
	cp -prfv src/header/selinux/*.h $(DESTDIR)/$(INCLUDEDIR)/selinux/
	cp -prfv src/header/sepol/* $(DESTDIR)/$(INCLUDEDIR)/sepol/

clean:
	rm -rf build

remove:
	rm -f $(DESTDIR)/$(LIBDIR)/libselinux.so.1
	rm -f $(DESTDIR)/$(LIBDIR)/libselinux.so
	rm -f $(DESTDIR)/$(LIBDIR)/libsemanage.so.1
	rm -f $(DESTDIR)/$(LIBDIR)/libsemanage.so
	rm -f $(DESTDIR)/$(PKGCONFIGDIR)/libselinux.pc
	rm -rf $(DESTDIR)/$(INCLUDEDIR)/selinux
	rm -rf $(DESTDIR)/$(INCLUDEDIR)/semanage
