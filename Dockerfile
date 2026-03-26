# Perl Lambda Runtime POC
# Base: debian:trixie-slim

########################################################################
FROM debian:trixie-slim AS builder
########################################################################
# Install build tools and runtime deps
RUN apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends \
        perl libssl3 libexpat1 zlib1g ca-certificates \
        gcc make rsync libssl-dev libexpat-dev zlib1g-dev libperl-dev curl && \
    curl -fsSL https://cpanmin.us | perl - App::cpanminus && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PERL_CPANM_OPT="-n -v --no-man-pages --mirror https://cpan.openbedrock.net/orepan2 --mirror https://cpan.metacpan.org"
RUN cpanm -n -v Carton

WORKDIR /usr/src/app
RUN mkdir -p /usr/src/app/local

COPY cpanfile cpanfile.snapshot /usr/src/app

ENV PERL_CARTON_CPANFILE=/usr/src/app/cpanfile
RUN --mount=type=cache,target=/cache/local-debian \
  rsync -a /usr/src/app/local/ /cache/local-debian && \
  carton install --deployment --path /cache/local-debian && \
  rm -rf /usr/src/app/local && \
  cp -a /cache/local-debian /usr/src/app/local

RUN ls -alrt /usr/src/app/local/lib/perl5

########################################################################
FROM debian:trixie-slim
########################################################################

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/local /usr/src/app/local
COPY --from=builder /usr/src/app/local/bin/bootstrap /usr/local/bin/bootstrap
COPY --from=builder /usr/src/app/local/bin/plambda.pl /usr/local/bin/plambda.pl

RUN apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends perl libssl3 libexpat1 zlib1g ca-certificates && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /root/.cpanm /tmp/*.tar.gz

ARG LAMBDA_MODULE=LambdaHandler.pm

COPY ${LAMBDA_MODULE} /usr/src/app/local/lib/perl5

ENV PERL5LIB=/usr/src/app/local/lib/perl5
ENV LAMBDA_MODULE=${LAMBDA_MODULE}

ENTRYPOINT ["/usr/local/bin/bootstrap"]
