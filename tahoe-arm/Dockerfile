FROM resin/rpi-raspbian:jessie 
MAINTAINER gregbkr@outlook.com

RUN apt-get update && \
    apt-get install -y git python-pip build-essential python-dev libffi-dev libssl-dev python-virtualenv

RUN git clone https://github.com/tahoe-lafs/tahoe-lafs
ADD . /tahoe-lafs
RUN \
  cd /tahoe-lafs && \
  git pull --depth=100 && \
  pip install . && \
  rm -rf ~/.cache/

RUN tahoe --version

WORKDIR /root
