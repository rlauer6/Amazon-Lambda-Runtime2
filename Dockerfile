# Perl Lambda Runtime POC
# Base: debian:trixie-slim

FROM debian:trixie-slim

# Install build tools and runtime deps
RUN apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends \
        perl libssl3 libexpat1 zlib1g ca-certificates \
        gcc make libssl-dev libexpat-dev zlib1g-dev libperl-dev curl && \
    curl -fsSL https://cpanmin.us | perl - App::cpanminus && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PERL_CPANM_OPT="-n -v --no-man-pages --mirror-only --mirror https://cpan.openbedrock.net/orepan2 --mirror https://cpan.metacpan.org"

RUN cpanm --notest --no-man-pages Amazon::Lambda::Runtime && \
    mkdir -p /var/runtime && \
    ln -s /usr/local/bin/bootstrap /var/runtime/bootstrap && \
    # purge build tools
    apt-get purge -y gcc make libssl-dev libexpat-dev libperl-dev curl && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /root/.cpanm /tmp/*.tar.gz

WORKDIR /var/task

COPY HelloLambda.pm /var/task/

ENTRYPOINT ["/var/runtime/bootstrap"]

CMD ["HelloLambda.handler"]
