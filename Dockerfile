FROM ubuntu:20.04 AS base

USER root

ENV HOME /alfalfa

# Need to set the lang to use Python 3.8 with Poetry
ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV ROOT_DIR /usr/local
ENV BUILD_DIR $HOME/build


RUN apt-get update \
    && apt-get install -y \
    ca-certificates \
    curl \
    gdebi-core \
    vim \
    wget \
    git \
    # openjdk-8-jdk \
    liblapack-dev \
    gfortran \
    libgfortran4 \
    cmake \
    python3-venv \
    python3-pip \
    libblas-dev \
    ruby-full \
    && rm -rf /var/lib/apt/lists/*


WORKDIR $HOME
# Use set in update-alternatives instead of config to
# provide non-interactive input.
# RUN update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java \
#     && update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac \
#     && curl -SLO http://openstudio-resources.s3.amazonaws.com/bcvtb-linux.tar.gz \
#     && tar -xzf bcvtb-linux.tar.gz \
#     && rm bcvtb-linux.tar.gz

WORKDIR $BUILD_DIR

ENV OPENSTUDIO_DOWNLOAD_FILENAME OpenStudio-3.8.0-rc1+2d5664af4d-Ubuntu-22.04-x86_64.deb
ENV OPENSTUDIO_DOWNLOAD_URL https://github.com/NREL/OpenStudio/releases/download/v3.8.0-rc1/OpenStudio-3.8.0-rc1+2d5664af4d-Ubuntu-22.04-x86_64.deb

ENV ENERGYPLUS_VERSION 24.1.0
ENV ENERGYPLUS_TAG v24.1.0
ENV ENERGYPLUS_SHA 9d7789a3ac
ENV ENERGYPLUS_DIR /usr/local/EnergyPlus

# mlep / external interface needs parts of EnergyPlus that are not included with OpenStudio
# expandobjects, runenergyplus might be two examples, but the need to install EnergyPlus separately from OpenStudio
# might be revaluated
ENV ENERGYPLUS_DOWNLOAD_BASE_URL https://github.com/NREL/EnergyPlus/releases/download/$ENERGYPLUS_TAG
ENV ENERGYPLUS_DOWNLOAD_FILENAME EnergyPlus-$ENERGYPLUS_VERSION-$ENERGYPLUS_SHA-Linux-Ubuntu20.04-x86_64.tar.gz
ENV ENERGYPLUS_DOWNLOAD_URL $ENERGYPLUS_DOWNLOAD_BASE_URL/$ENERGYPLUS_DOWNLOAD_FILENAME

# We would rather use the self extracting tarball distribution of EnergyPlus, but there appears to
# be a bug in the installation script so using the tar.gz manually here and making our own links
RUN curl -SLO $ENERGYPLUS_DOWNLOAD_URL \
    && mkdir $ENERGYPLUS_DIR \
    && tar -C $ENERGYPLUS_DIR/ --strip-components=1 -xzf $ENERGYPLUS_DOWNLOAD_FILENAME \
    && ln -s $ENERGYPLUS_DIR/energyplus /usr/local/bin/ \
    && ln -s $ENERGYPLUS_DIR/ExpandObjects /usr/local/bin/ \
    && ln -s $ENERGYPLUS_DIR/runenergyplus /usr/local/bin/ \
    && rm $ENERGYPLUS_DOWNLOAD_FILENAME

RUN curl -SLO $OPENSTUDIO_DOWNLOAD_URL \
    && gdebi -n $OPENSTUDIO_DOWNLOAD_FILENAME \
    && rm -f $OPENSTUDIO_DOWNLOAD_FILENAME \
    && cd /usr/local/openstudio* \
    && rm -rf EnergyPlus \
    && ln -s $ENERGYPLUS_DIR EnergyPlus

# Install commands for Spawn
ENV SPAWN_VERSION=0.3.0-69040695f9
RUN wget https://spawn.s3.amazonaws.com/custom/Spawn-$SPAWN_VERSION-Linux.tar.gz \
    && tar -C /usr/local/ -xzf Spawn-$SPAWN_VERSION-Linux.tar.gz \
    && ln -s /usr/local/Spawn-$SPAWN_VERSION-Linux/bin/spawn-$SPAWN_VERSION /usr/local/bin/ \
    && rm Spawn-$SPAWN_VERSION-Linux.tar.gz

## MODELICA
ENV FMIL_TAG 2.4
ENV FMIL_HOME $ROOT_DIR/fmil

ENV SUNDIALS_HOME $ROOT_DIR
ENV SUNDIALS_TAG v4.1.0

ENV ASSIMULO_TAG Assimulo-3.4.3

ENV PYFMI_TAG PyFMI-2.12.0

ENV SUPERLU_HOME $ROOT_DIR/SuperLU_MT_3.1

COPY requirements.txt $BUILD_DIR
RUN pip install -r requirements.txt && \
    rm requirements.txt

# Install Assimulo for PyFMI
RUN curl -SLO https://github.com/modelon-community/Assimulo/releases/download/Assimulo-3.4.3/Assimulo-3.4.3-cp38-cp38-linux_x86_64.whl \
    && pip install Assimulo-3.4.3-cp38-cp38-linux_x86_64.whl

# Install PyFMI
RUN curl -SLO https://github.com/modelon-community/PyFMI/releases/download/PyFMI-2.11.0/PyFMI-2.11.0-cp38-cp38-linux_x86_64.whl \
    && pip install PyFMI-2.11.0-cp38-cp38-linux_x86_64.whl

ENV PYTHONPATH=/usr/local/lib/python3.8/dist-packages/Assimulo-3.2.9-py3.8-linux-x86_64.egg:/usr/local/lib/python3.8/dist-packages/PyFMI-2.9.5-py3.8-linux-x86_64.egg:${ENERGYPLUS_DIR}

ENV SEPARATE_PROCESS_JVM /usr/lib/jvm/java-8-openjdk-amd64/
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/
