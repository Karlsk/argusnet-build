FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends tini libcap2-bin \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'hosts: files dns' >> /etc/nsswitch.conf

RUN mkdir -p /usr/bin /etc/categraf

COPY categraf /usr/bin/categraf
COPY conf /etc/categraf/conf
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]