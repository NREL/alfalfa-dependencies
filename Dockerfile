ARG PYTHON_VERSION=3.10.14
ARG DEBIAN_VERSION=bookworm
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} as modelica-dependencies
ARG SUNDIALS_VERSION=v2.7.0
ARG ASSIMULO_VERSION=3.5.2
RUN apt update \
  && apt install -y \
  cmake \
  liblapack-dev \
  libsuitesparse-dev \
  libhypre-dev \
  curl \
  git \
  build-essential

RUN python3 -m pip install \
  Cython \
  numpy \
  scipy \
  matplotlib \
  nose-py3 \
  setuptools==69.1.0

RUN ln -s /usr/lib/$(uname -m)-linux-gnu/libblas.so /usr/lib/$(uname -m)-linux-gnu/libblas_OPENMP.so

WORKDIR /build

RUN curl -fSsL https://portal.nersc.gov/project/sparse/superlu/superlu_mt_3.1.tar.gz | tar xz \
  && cd SuperLU_MT_3.1 \
  && make CFLAGS="-O2 -fPIC -fopenmp" BLASLIB="-lblas" PLAT="_OPENMP" MPLIB="-fopenmp" lib -j1 \
  && cp -v ./lib/libsuperlu_mt_OPENMP.a /usr/lib \
  && cp -v ./SRC/*.h /usr/include

RUN git clone --depth 1 -b ${SUNDIALS_VERSION} https://github.com/LLNL/sundials.git \
  && cd sundials \
  && echo "target_link_libraries(sundials_idas_shared lapack blas superlu_mt_OPENMP)" >> src/idas/CMakeLists.txt \
  && echo "target_link_libraries(sundials_kinsol_shared lapack blas superlu_mt_OPENMP)" >> src/kinsol/CMakeLists.txt \
  && mkdir build && cd build \
  && cmake \
  -LAH \
  -DSUPERLUMT_BLAS_LIBRARIES=blas \
  -DSUPERLUMT_LIBRARIES=blas \
  -DSUPERLUMT_INCLUDE_DIR=/usr/include \
  -DSUPERLUMT_LIBRARY=/usr/lib/libsuperlu_mt_OPENMP.a \
  -DSUPERLUMT_THREAD_TYPE=OpenMP \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DSUPERLUMT_ENABLE=ON \
  -DLAPACK_ENABLE=ON \
  -DEXAMPLES_ENABLE=OFF \
  -DEXAMPLES_ENABLE_C=OFF \
  -DBUILD_STATIC_LIBS=OFF \
  .. \
  && make -j4 \
  && make install

RUN git clone --depth 1 -b Assimulo-${ASSIMULO_VERSION} https://github.com/modelon-community/Assimulo.git \
  && cd Assimulo \
  && python3 setup.py install --user --sundials-home=/usr --blas-home=/usr/lib/$(uname -m)-linux-gnu --lapack-home=/usr/lib/$(uname -m)-linux-gnu --superlu-home=/usr \
  && python3 setup.py bdist_wheel

RUN git clone --depth 1 -b 2.4.1 https://github.com/modelon-community/fmi-library.git \
  && cd fmi-library \
  && sed -i "/CMAKE_INSTALL_PREFIX/d" CMakeLists.txt \
  && mkdir fmi_build && cd fmi_build \
  && mkdir fmi_library \
  && cmake -DCMAKE_INSTALL_PREFIX=/build/fmi-libary/fmi_library .. \
  && make -j4 \
  && make install

RUN git clone --depth 1 -b PyFMI-2.13.1 https://github.com/modelon-community/PyFMI.git \
  && cd PyFMI \
  && python3 setup.py bdist_wheel --fmil-home=/build/fmi-libary/fmi_library

WORKDIR /artifacts

RUN cp /build/Assimulo/build/dist/* . \
  && cp /build/PyFMI/dist/* .

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} as energyplus-dependencies
ARG OPENSTUDIO_VERSION=3.8.0
ARG OPENSTUDIO_VERSION_SHA=f953b6fcaf
ARG ENERGYPLUS_VERSION=24.1.0
ARG ENERGYPLUS_VERSION_SHA=9d7789a3ac

RUN apt update \
  && apt install -y \
  curl

WORKDIR /artifacts
RUN export ARCHITECTURE=x86_64 \
  && if [ "$(uname -m)" = "aarch64" ]; then export ARCHITECTURE=arm64; fi \
  && curl -SfL https://github.com/NREL/EnergyPlus/releases/download/v${ENERGYPLUS_VERSION}/EnergyPlus-${ENERGYPLUS_VERSION}-${ENERGYPLUS_VERSION_SHA}-Linux-Ubuntu22.04-${ARCHITECTURE}.tar.gz -o energyplus.tar.gz \
  && curl -SfL https://github.com/NREL/OpenStudio/releases/download/v${OPENSTUDIO_VERSION}/OpenStudio-${OPENSTUDIO_VERSION}+${OPENSTUDIO_VERSION_SHA}-Ubuntu-22.04-${ARCHITECTURE}.deb -o openstudio.deb \
  && curl -SfL http://openstudio-resources.s3.amazonaws.com/bcvtb-linux.tar.gz -o bcvtb.tar.gz

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} as dual-python

  ENV PYTHON_VERSION 3.8.19
  ENV GPG_KEY E3FF2839C048B25C084DEBE9B26995E310250568

  RUN set -eux; \
      \
      savedAptMark="$(apt-mark showmanual)"; \
      apt-get update; \
      apt-get install -y --no-install-recommends \
          dpkg-dev \
          gcc \
          gnupg \
          libbluetooth-dev \
          libbz2-dev \
          libc6-dev \
          libdb-dev \
          libexpat1-dev \
          libffi-dev \
          libgdbm-dev \
          liblzma-dev \
          libncursesw5-dev \
          libreadline-dev \
          libsqlite3-dev \
          libssl-dev \
          make \
          tk-dev \
          uuid-dev \
          wget \
          xz-utils \
          zlib1g-dev \
      ; \
      \
      wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz"; \
      wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc"; \
      GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$GPG_KEY"; \
      gpg --batch --verify python.tar.xz.asc python.tar.xz; \
      gpgconf --kill all; \
      rm -rf "$GNUPGHOME" python.tar.xz.asc; \
      mkdir -p /usr/src/python; \
      tar --extract --directory /usr/src/python --strip-components=1 --file python.tar.xz; \
      rm python.tar.xz; \
      \
      cd /usr/src/python; \
      gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
      ./configure \
          --build="$gnuArch" \
          --enable-loadable-sqlite-extensions \
          --enable-optimizations \
          --enable-option-checking=fatal \
          --enable-shared \
          --with-system-expat \
          --without-ensurepip \
      ; \
      nproc="$(nproc)"; \
      EXTRA_CFLAGS="$(dpkg-buildflags --get CFLAGS)"; \
      LDFLAGS="$(dpkg-buildflags --get LDFLAGS)"; \
      LDFLAGS="${LDFLAGS:--Wl},--strip-all"; \
      make -j "$nproc" \
          "EXTRA_CFLAGS=${EXTRA_CFLAGS:-}" \
          "LDFLAGS=${LDFLAGS:-}" \
          "PROFILE_TASK=${PROFILE_TASK:-}" \
      ; \
  # https://github.com/docker-library/python/issues/784
  # prevent accidental usage of a system installed libpython of the same version
      rm python; \
      make -j "$nproc" \
          "EXTRA_CFLAGS=${EXTRA_CFLAGS:-}" \
          "LDFLAGS=${LDFLAGS:--Wl},-rpath='\$\$ORIGIN/../lib'" \
          "PROFILE_TASK=${PROFILE_TASK:-}" \
          python \
      ; \
      make altinstall; \
      \
      cd /; \
      rm -rf /usr/src/python; \
      \
      find /usr/local -depth \
          \( \
              \( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
              -o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name 'libpython*.a' \) \) \
              -o \( -type f -a -name 'wininst-*.exe' \) \
          \) -exec rm -rf '{}' + \
      ; \
      \
      ldconfig; \
      \
      apt-mark auto '.*' > /dev/null; \
      apt-mark manual $savedAptMark; \
      find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
          | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
          | sort -u \
          | xargs -r dpkg-query --search \
          | cut -d: -f1 \
          | sort -u \
          | xargs -r apt-mark manual \
      ; \
      apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
      rm -rf /var/lib/apt/lists/*; \
      \
      python3.8 --version

  RUN python3.8 -m ensurepip --altinstall


FROM dual-python as alfalfa-dependencies

ENV ENERGYPLUS_DIR /usr/local/EnergyPlus
ENV HOME /alfalfa

WORKDIR /artifacts

RUN apt update \
  && apt install -y \
  gdebi-core \
  openjdk-17-jdk \
  && rm -rf /var/lib/apt/lists/*

# RUN update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java \
#   && update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac

RUN --mount=type=bind,from=modelica-dependencies,source=/artifacts,target=/artifacts pip3 install *.whl

RUN --mount=type=bind,from=energyplus-dependencies,source=/artifacts,target=/artifacts mkdir ${ENERGYPLUS_DIR} \
  && tar -C $ENERGYPLUS_DIR/ --strip-components=1 -xzf energyplus.tar.gz \
  && ln -s $ENERGYPLUS_DIR/energyplus /usr/local/bin/ \
  && ln -s $ENERGYPLUS_DIR/ExpandObjects /usr/local/bin/ \
  && ln -s $ENERGYPLUS_DIR/runenergyplus /usr/local/bin/

RUN --mount=type=bind,from=energyplus-dependencies,source=/artifacts,target=/artifacts apt update \
  && gdebi -n openstudio.deb \
  && cd /usr/local/openstudio* \
  && rm -rf EnergyPlus \
  && ln -s ${ENERGYPLUS_DIR} EnergyPlus \
  && rm -rf /var/lib/apt/lists/*

WORKDIR $HOME

# Only the xml lib component of bcvtb is actaully required for communication, so we just extract that to save space
RUN --mount=type=bind,from=energyplus-dependencies,source=/artifacts,target=/artifacts tar -xzf /artifacts/bcvtb.tar.gz bcvtb/lib/xml
