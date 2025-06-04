FROM node:20-alpine AS builder

ARG DATABASE_PROVIDER_ARG=local
ARG BOXSET_ARG=local
ARG APPSET_ARG=widesoft
ARG REGION_ARG=us-east-1
ARG SERVICE_ARG=evolution-whatsapp-widesoft-local
ARG AWS_SECRET_ARN_ARG=local

ENV DOCKER_ENV=true
ENV DATABASE_PROVIDER=${DATABASE_PROVIDER_ARG}
ENV BOXSET=${BOXSET_ARG}
ENV APPSET=${APPSET_ARG}
ENV REGION=${REGION_ARG}
ENV AWS_REGION=${REGION_ARG}
ENV SERVICE=${SERVICE_ARG}
ENV AWS_SECRET_ARN=${AWS_SECRET_ARN_ARG}

RUN apk update && \
    apk add git ffmpeg wget curl bash openssl

LABEL version="2.2.3" description="Api to control whatsapp features through http requests."
LABEL maintainer="Davidson Gomes" git="https://github.com/DavidsonGomes"
LABEL contact="contato@atendai.com"

WORKDIR /evolution

COPY ./package.json ./tsconfig.json ./

RUN npm install

COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY ./.env.example ./.env
COPY ./runWithProvider.js ./
COPY ./tsup.config.ts ./

COPY ./Docker ./Docker

RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/*

RUN ./Docker/scripts/generate_database.sh

RUN npm run build

FROM node:20-alpine AS final

ARG DATABASE_PROVIDER_ARG=local
ARG BOXSET_ARG=local
ARG APPSET_ARG=widesoft
ARG REGION_ARG=us-east-1
ARG SERVICE_ARG=evolution-whatsapp-widesoft-local
ARG AWS_SECRET_ARN_ARG=local

ENV PYTHONWARNINGS="ignore::UserWarning"
ENV DOCKER_ENV=true
ENV DATABASE_PROVIDER=${DATABASE_PROVIDER_ARG}
ENV BOXSET=${BOXSET_ARG}
ENV APPSET=${APPSET_ARG}
ENV REGION=${REGION_ARG}
ENV AWS_REGION=${REGION_ARG}
ENV SERVICE=${SERVICE_ARG}
ENV AWS_SECRET_ARN=${AWS_SECRET_ARN_ARG}

RUN apk update && \
    apk add tzdata ffmpeg bash openssl supervisor cronie jq unzip curl aws-cli iproute2

ENV TZ=America/Sao_Paulo
RUN ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

RUN mkdir -p /etc/supervisor/conf.d
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

COPY supervisor/conf.d/cronie.conf /etc/supervisor/conf.d/cronie.conf
COPY supervisor/etc/crontabs/root /etc/crontabs/root

RUN chown root:root /etc/crontabs/root
RUN chmod 600 /etc/crontabs/root

COPY supervisor/conf.d/evolution-api.conf /etc/supervisor/conf.d/evolution-api.conf

RUN chmod 0644 /etc/supervisor/conf.d/*

WORKDIR /evolution

COPY --from=builder /evolution/package.json ./package.json
COPY --from=builder /evolution/package-lock.json ./package-lock.json

COPY --from=builder /evolution/node_modules ./node_modules
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/.env ./.env
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

COPY supervisor/scripts/api_key.py ./api_key.py
COPY supervisor/scripts/credentials_updater.sh ./credentials_updater.sh
COPY supervisor/scripts/run.sh ./run.sh
COPY supervisor/scripts/utils.sh ./utils.sh

EXPOSE 8080

# ENTRYPOINT ["/bin/bash", "-c", ". ./Docker/scripts/deploy_database.sh && npm run start:prod" ]

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
