FROM us-central1-docker.pkg.dev/navneet-410819/whoami6443-hub/ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && apt-get install -y curl jq && apt-get autoremove -y \
   && apt-get purge -y --auto-remove \
   && rm -rf /var/lib/apt/lists/*
RUN curl -k -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /usr/local/bin -xvzf - govc
RUN curl -k -LO "https://dl.k8s.io/release/$(curl -k -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

ADD https://github.com/krallin/tini/releases/download/v0.19.0/tini /sbin/tini
RUN chmod +x /sbin/tini
COPY server.sh /bin
RUN chmod +x /bin/server.sh
ENV GOVMOMI_HOME=/tmp

RUN useradd multinic --uid 9999 -m -U --home-dir /home/multinic -s /bin/bash
USER multinic

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/server.sh"]