FROM python:2.7
MAINTAINER gregbkr@outlook.com

# Duply
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    duply \
    ncftp \
    pwgen \
    sshfs \
    python-boto \
    python-pip \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*
ENV HOME /root

# Tahoe
RUN git clone https://github.com/tahoe-lafs/tahoe-lafs.git tahoe-lafs && \
        cd /tahoe-lafs && \
        git pull --depth=100 && \
        pip install . && \
        rm -rf ~/.cache/
RUN tahoe --version

#expose 3456
WORKDIR /root

CMD [ "tahoe", "start", ".tahoe/", "--nodaemon", "--logfile=-" ]
#CMD /usr/local/bin/tahoe start /root/.tahoe/ -n --pidfile /root/twistd.pid

