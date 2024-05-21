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
    openjdk-8-jdk \
    libgfortran4 \
    python3-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*


WORKDIR $HOME
# Use set in update-alternatives instead of config to
# provide non-interactive input.
RUN update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java \
    && update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac \
    && curl -SLO http://openstudio-resources.s3.amazonaws.com/bcvtb-linux.tar.gz \
    && tar -xzf bcvtb-linux.tar.gz \
    && rm bcvtb-linux.tar.gz

WORKDIR $BUILD_DIR

ENV OPENSTUDIO_DOWNLOAD_URL https://github.com/NREL/OpenStudio/releases/download/v3.8.0/OpenStudio-3.8.0+f953b6fcaf-Ubuntu-20.04-x86_64.deb

# mlep / external interface needs parts of EnergyPlus that are not included with OpenStudio
# expandobjects, runenergyplus might be two examples, but the need to install EnergyPlus separately from OpenStudio
# might be revaluated
ENV ENERGYPLUS_DIR /usr/local/EnergyPlus
ENV ENERGYPLUS_DOWNLOAD_URL https://github.com/NREL/EnergyPlus/releases/download/v24.1.0/EnergyPlus-24.1.0-9d7789a3ac-Linux-Ubuntu20.04-x86_64.tar.gz

# We would rather use the self extracting tarball distribution of EnergyPlus, but there appears to
# be a bug in the installation script so using the tar.gz manually here and making our own links
RUN curl -SL $ENERGYPLUS_DOWNLOAD_URL -o energyplus.tar.gz\
    && mkdir $ENERGYPLUS_DIR \
    && tar -C $ENERGYPLUS_DIR/ --strip-components=1 -xzf energyplus.tar.gz \
    && ln -s $ENERGYPLUS_DIR/energyplus /usr/local/bin/ \
    && ln -s $ENERGYPLUS_DIR/ExpandObjects /usr/local/bin/ \
    && ln -s $ENERGYPLUS_DIR/runenergyplus /usr/local/bin/ \
    && rm energyplus.tar.gz

RUN curl -SL $OPENSTUDIO_DOWNLOAD_URL -o openstudio.deb\
    && gdebi -n openstudio.deb \
    && rm -f openstudio.deb \
    && cd /usr/local/openstudio* \
    && rm -rf EnergyPlus \
    && ln -s $ENERGYPLUS_DIR EnergyPlus

# Install commands for Spawn
ENV SPAWN_VERSION=0.3.0-69040695f9
RUN curl -SL https://spawn.s3.amazonaws.com/custom/Spawn-$SPAWN_VERSION-Linux.tar.gz -o spawn.tar.gz \
    && tar -C /usr/local/ -xzf spawn.tar.gz \
    && ln -s /usr/local/Spawn-$SPAWN_VERSION-Linux/bin/spawn-$SPAWN_VERSION /usr/local/bin/ \
    && rm spawn.tar.gz

## MODELICA
# Modelica requires libgfortran3 which is not in apt for 20.04
RUN curl -SLO http://archive.ubuntu.com/ubuntu/pool/universe/g/gcc-6/gcc-6-base_6.4.0-17ubuntu1_amd64.deb \
    && curl -SLO http://archive.ubuntu.com/ubuntu/pool/universe/g/gcc-6/libgfortran3_6.4.0-17ubuntu1_amd64.deb \
    && dpkg -i gcc-6-base_6.4.0-17ubuntu1_amd64.deb \
    && dpkg -i libgfortran3_6.4.0-17ubuntu1_amd64.deb \
    && ln -s /usr/lib/x86_64-linux-gnu/libffi.so.7 /usr/lib/x86_64-linux-gnu/libffi.so.6 \
    && rm *.deb

COPY requirements.txt $BUILD_DIR
RUN pip install -r requirements.txt && \
    rm requirements.txt

# Install Assimulo for PyFMI
RUN curl -SLO https://github.com/modelon-community/Assimulo/releases/download/Assimulo-3.4.3/Assimulo-3.4.3-cp38-cp38-linux_x86_64.whl \
    && pip install Assimulo-3.4.3-cp38-cp38-linux_x86_64.whl \
    && rm Assimulo-3.4.3-cp38-cp38-linux_x86_64.whl

# Install PyFMI
RUN curl -SLO https://github.com/modelon-community/PyFMI/releases/download/PyFMI-2.11.0/PyFMI-2.11.0-cp38-cp38-linux_x86_64.whl \
    && pip install PyFMI-2.11.0-cp38-cp38-linux_x86_64.whl \
    && rm PyFMI-2.11.0-cp38-cp38-linux_x86_64.whl

ENV PYTHONPATH=${PYTHONPATH}:${ENERGYPLUS_DIR}

ENV SEPARATE_PROCESS_JVM /usr/lib/jvm/java-8-openjdk-amd64/
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/
