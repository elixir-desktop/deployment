#build with pkgconfig
gcc -o test `pkg-config --cflags --libs libselinux` test.c
#build with force link libselinux
gcc -o test2 -lselinux test.c
