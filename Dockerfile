ARG PYTHON_VERSION=3.10.14
ARG DEBIAN_VERSION=bookworm
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} as modelica-dependencies
ARG SUNDIALS_VERSION=v2.7.0
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

RUN git clone --depth 1 -b Assimulo-3.5.2 https://github.com/modelon-community/Assimulo.git \
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
  && if [ $(uname -m) == "aarch64" ]; then export ARCHITECTURE=arm64; fi \
  && curl -SfL https://github.com/NREL/EnergyPlus/releases/download/v${ENERGYPLUS_VERSION}/EnergyPlus-${ENERGYPLUS_VERSION}-${ENERGYPLUS_VERSION_SHA}-Linux-Ubuntu22.04-${ARCHITECTURE}.tar.gz -o energyplus.tar.gz \
  && curl -SfL https://github.com/NREL/OpenStudio/releases/download/v${OPENSTUDIO_VERSION}/OpenStudio-${OPENSTUDIO_VERSION}+${OPENSTUDIO_VERSION_SHA}-Ubuntu-22.04-${ARCHITECTURE}.deb -o openstudio.deb

FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} as alfalfa-dependencies

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
