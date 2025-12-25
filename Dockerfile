ARG GLIBC_VERSION="2.42"
ARG GCC_VERSION="13.2.0"
ARG TARGET_ROOT="/opt/target-root"

FROM debian:bullseye-slim AS build

ARG TARGET_ROOT
ARG GCC_VERSION
ARG GLIBC_VERSION

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    bison \
    gawk \
    python3 \
    flex \
    texinfo \
    file \
    ca-certificates \
    && mkdir -p ${TARGET_ROOT} 

RUN wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz -Ogcc-bootstrap.tar.gz \
    && tar -zxf gcc-bootstrap.tar.gz \
    && mv gcc-${GCC_VERSION} gcc-bootstrap \
    && cd gcc-bootstrap \
    && ./contrib/download_prerequisites \
    && mkdir build \
    && cd build \
    && ../configure \
        --with-glibc-version=${GLIBC_VERSION} \
        --prefix=/usr \
        --disable-multilib \
        --disable-libsanitizer \
        --enable-languages=c,c++ \
        --disable-bootstrap \
    && make -j$(nproc) \
    && mkdir /gcc-bootstrap-toolchain \
    && make install DESTDIR=/gcc-bootstrap-toolchain \
    && cd ../.. \
    && rm -rf gcc-bootstrap \
    && mv gcc-bootstrap.tar.gz gcc-${GCC_VERSION}.tar.gz

RUN wget https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.gz \
    && tar -zxf glibc-${GLIBC_VERSION}.tar.gz \
    && mkdir glibc-build \
    && cd glibc-build \
    && CC="/gcc-bootstrap-toolchain/usr/bin/gcc" CXX="/gcc-bootstrap-toolchain/usr/bin/g++" ../glibc-${GLIBC_VERSION}/configure --prefix=/usr --host=x86_64-linux-gnu --disable-werror \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf glibc-build glibc-${GLIBC_VERSION} glibc-${GLIBC_VERSION}.tar.gz

RUN if [ -d ${TARGET_ROOT}/usr/lib64 ]; then \
        mkdir -p ${TARGET_ROOT}/usr/lib && \
        cp -r ${TARGET_ROOT}/usr/lib64/* ${TARGET_ROOT}/usr/lib/ && \
        rm -rf ${TARGET_ROOT}/usr/lib64 && \
        ln -s lib ${TARGET_ROOT}/usr/lib64; \
    fi

RUN cp -rL /usr/include/linux ${TARGET_ROOT}/usr/include \
    && cp -rL /usr/include/asm-generic ${TARGET_ROOT}/usr/include \
    && cp -rL /usr/include/x86_64-linux-gnu/asm ${TARGET_ROOT}/usr/include

    # downloaded in previous step
RUN tar -zxf gcc-${GCC_VERSION}.tar.gz \
    && cd gcc-${GCC_VERSION} \
    && ./contrib/download_prerequisites \
    && mkdir build \
    && cd build \
    && ../configure \
        --target=x86_64-linux-gnu \
        --with-glibc-version=${GLIBC_VERSION} \
        --prefix=/usr \
        --disable-multilib \
        --disable-libsanitizer \
        --enable-languages=c,c++ \
        --with-sysroot=/ \
        --with-build-sysroot=${TARGET_ROOT} \
        --disable-bootstrap \
        --with-native-system-header-dir=/usr/include \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd ../.. \
    && rm -rf gcc-${GCC_VERSION} gcc-${GCC_VERSION}.tar.gz

RUN ln -s x86_64-linux-gnu-gcc ${TARGET_ROOT}/usr/bin/gcc
RUN ln -s x86_64-linux-gnu-g++ ${TARGET_ROOT}/usr/bin/g++

# install bash
RUN wget https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz \
    && tar -zxf bash-5.2.tar.gz \
    && cd bash-5.2 \
    && export LD_LIBRARY_PATH=${TARGET_ROOT}/usr/lib \
    && ./configure \
        --host=x86_64-linux-gnu \
        --prefix=/usr \
        --without-bash-malloc \
        CC="${TARGET_ROOT}/usr/bin/gcc --sysroot=${TARGET_ROOT}" \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf bash-5.2 bash-5.2.tar.gz 

# prepare tar, wget, gzip

RUN wget https://ftp.gnu.org/gnu/coreutils/coreutils-9.5.tar.gz \
    && tar -zxf coreutils-9.5.tar.gz \
    && cd coreutils-9.5 \
    && export LD_LIBRARY_PATH=${TARGET_ROOT}/usr/lib \
    && FORCE_UNSAFE_CONFIGURE=1 ./configure \
        --prefix=/usr \
        --host=x86_64-linux-gnu \
        CC="${TARGET_ROOT}/usr/bin/gcc --sysroot=${TARGET_ROOT}"

    # we ignore the resulting error because make might fail during manpage generation, but it isn't important
RUN cd coreutils-9.5 && make -j$(nproc)

RUN cd coreutils-9.5 && make install-exec DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf coreutils-9.5 coreutils-9.5.tar.gz

RUN wget https://ftp.gnu.org/gnu/sed/sed-4.9.tar.gz \
    && tar -zxf sed-4.9.tar.gz \
    && cd sed-4.9 \
    && export LD_LIBRARY_PATH=${TARGET_ROOT}/usr/lib \
    && ./configure \
        --prefix=/usr \
        --host=x86_64-linux-gnu \
        CC="${TARGET_ROOT}/usr/bin/gcc --sysroot=${TARGET_ROOT}" \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf sed-4.9 sed-4.9.tar.gz

RUN wget https://ftp.gnu.org/gnu/make/make-4.4.tar.gz \
    && tar -zxf make-4.4.tar.gz \
    && cd make-4.4 \
    && export LD_LIBRARY_PATH=${TARGET_ROOT}/usr/lib \
    && ./configure \
        --prefix=/usr \
        --host=x86_64-linux-gnu \
        CC="${TARGET_ROOT}/usr/bin/gcc --sysroot=${TARGET_ROOT}" \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf make-4.4 make-4.4.tar.gz

RUN wget https://ftp.gnu.org/gnu/binutils/binutils-2.45.tar.gz \
    && tar -zxf binutils-2.45.tar.gz \
    && cd binutils-2.45 \
    && export LD_LIBRARY_PATH=${TARGET_ROOT}/usr/lib \
    && ./configure \
        --prefix=/usr \
        # gprofng doesn't play nice with the compilation options
        --disable-gprofng \
        --target=x86_64-linux-gnu \
        --host=x86_64-linux-gnu \
        CC_FOR_TARGET="${TARGET_ROOT}/usr/bin/gcc --sysroot=${TARGET_ROOT}" \
        LD_FOR_TARGET="${TARGET_ROOT}/usr/bin/ld --sysroot=${TARGET_ROOT}"  \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf binutils-2.42 binutils-2.42.tar.gz

RUN wget https://ftp.gnu.org/gnu/grep/grep-3.11.tar.gz \
    && tar -zxf grep-3.11.tar.gz \
    && cd grep-3.11 \
    && export LD_LIBRARY_PATH=${TARGET_ROOT}/usr/lib \
    && ./configure \
        --prefix=/usr \
        --host=x86_64-linux-gnu \
        CC="${TARGET_ROOT}/usr/bin/gcc --sysroot=${TARGET_ROOT}" \
    && make -j$(nproc) \
    && make install DESTDIR=${TARGET_ROOT} \
    && cd .. \
    && rm -rf grep-3.11 grep-3.11.tar.gz

WORKDIR ${TARGET_ROOT}

RUN wget https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz && tar -zxf wget-1.25.0.tar.gz
RUN wget https://ftp.gnu.org/gnu/gzip/gzip-1.14.tar.gz && tar -zxf gzip-1.14.tar.gz
RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.5.4/openssl-3.5.4.tar.gz && tar -zxf openssl-3.5.4.tar.gz
RUN wget https://ftp.gnu.org/gnu/tar/tar-1.35.tar.gz && tar -zxf tar-1.35.tar.gz
RUN wget https://www.cpan.org/src/5.0/perl-5.42.0.tar.gz && tar -zxf perl-5.42.0.tar.gz
RUN wget https://ftp.gnu.org/gnu/gawk/gawk-3.0.2.tar.gz && tar -zxf gawk-3.0.2.tar.gz
RUN wget https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz && tar -zxf pkg-config-0.29.2.tar.gz
RUN wget https://ftp.gnu.org/gnu/diffutils/diffutils-3.12.tar.gz && tar -zxf diffutils-3.12.tar.gz
RUN wget https://curl.se/download/curl-8.17.0.tar.gz && tar -zxf curl-8.17.0.tar.gz
RUN wget https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz && tar -zxf libpsl-0.21.5.tar.gz
RUN wget https://www.zlib.net/zlib-1.3.1.tar.gz && tar -zxf zlib-1.3.1.tar.gz
RUN wget https://download.gnome.org/sources/glib/2.87/glib-2.87.0.tar.xz && tar -xf glib-2.87.0.tar.xz
RUN wget https://www.python.org/ftp/python/3.14.2/Python-3.14.2.tgz && tar -zxf Python-3.14.2.tgz
RUN wget https://ftp.gnu.org/gnu/findutils/findutils-4.10.0.tar.xz && tar -xf findutils-4.10.0.tar.xz
RUN wget https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz && tar -xf bzip2-1.0.8.tar.gz

RUN ln -s usr/lib ${TARGET_ROOT}/lib 
RUN ln -s usr/lib64 ${TARGET_ROOT}/lib64
RUN ln -s usr/bin ${TARGET_ROOT}/bin
RUN ln -s usr/sbin ${TARGET_ROOT}/sbin

RUN ln -s bash ${TARGET_ROOT}/usr/bin/sh

RUN ln -s /usr/bin/gcc ${TARGET_ROOT}/usr/bin/cc
RUN ln -s /usr/bin/g++ ${TARGET_ROOT}/usr/bin/c++

RUN echo $(getent passwd root) > ${TARGET_ROOT}/etc/passwd && echo $(getent group 0) > ${TARGET_ROOT}/etc/group

RUN mkdir  ${TARGET_ROOT}/tmp

FROM scratch

ARG TARGET_ROOT

COPY --from=build ${TARGET_ROOT} /
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# build zlib first as it's needed by other packages
RUN cd /zlib-1.3.1 && ./configure --prefix=/usr && make -j$(nproc) && make install

RUN rm -rf /zlib-1.3.1

# build awk inside the container
RUN cd /gawk-3.0.2 && ./configure && make -j$(nproc) && make install

RUN rm -rf /gawk-3.0.2

# build perl inside the container
RUN cd /perl-5.42.0 && ./Configure -des -Dprefix=/usr && make -j$(nproc) && make install

RUN rm -rf /perl-5.42.0

# build openssl inside the container
RUN cd /openssl-3.5.4 && ./Configure --prefix=/usr --openssldir=/etc/ssl && make -j$(nproc) && make install

RUN rm -rf /openssl-3.5.4

# build diff
RUN cd /diffutils-3.12 && ./configure --prefix=/usr && make -j$(nproc) && make install

RUN rm -rf /diffutils-3.12

# build bz2
RUN cd /bzip2-1.0.8 \
    && make -j$(nproc) CFLAGS="-fPIC" \
    && make install PREFIX=/usr \
    && cd / \
    && rm -rf /bzip2-1.0.8 /bzip2-1.0.8.tar.gz

# build python
RUN cd /Python-3.14.2 && ./configure --prefix=/usr && make -j$(nproc) && make install

RUN rm -rf /Python-3.14.2

# build libpsl
RUN cd /libpsl-0.21.5 && ./configure --prefix=/usr && make -j$(nproc) && make install

RUN rm -rf /libpsl-0.21.5

# build gzip
RUN cd /gzip-1.14 && ./configure --prefix=/usr && make -j$(nproc) && make install

RUN rm -rf /gzip-1.14

# build tar
RUN cd /tar-1.35 && FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr && make -j$(nproc) && make install

RUN rm -rf /tar-1.35

# build curl
RUN cd /curl-8.17.0 && ./configure --prefix=/usr --with-openssl --with-libpsl && make -j$(nproc) && make install

RUN rm -rf /curl-8.17.0

# install meson
RUN pip3 install meson

# build ninja from source
RUN curl -L https://github.com/ninja-build/ninja/archive/refs/tags/v1.13.2.tar.gz -o ninja-1.13.2.tar.gz \
    && tar -zxf ninja-1.13.2.tar.gz \
    && cd ninja-1.13.2 \
    && python3 configure.py --bootstrap \
    && install -m755 ninja /usr/bin/ninja \
    && cd / \
    && rm -rf ninja-1.13.2 ninja-1.13.2.tar.gz

# build glib
RUN cd /glib-2.87.0 && meson setup build --prefix=/usr && ninja -C build && ninja -C build install

RUN rm -rf /glib-2.87.0

# install pkg-config by specifying glib built above
RUN cd /pkg-config-0.29.2 && \
    GLIB_CFLAGS="-I/usr/include/glib-2.0 -I/usr/lib/glib-2.0/include" \
    GLIB_LIBS="-L/usr/lib -lglib-2.0" \
    ./configure --prefix=/usr && \
    make -j$(nproc) && \
    make install

# install wget
RUN cd /wget-1.25.0 && ./configure --prefix=/usr --with-ssl=openssl && make -j$(nproc) && make install

RUN rm -rf /wget-1.25.0

RUN rm -rf /pkg-config-0.29.2

CMD ["/bin/bash"]