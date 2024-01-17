# Build AmneziaWG

FROM golang:1.20 as awg
ARG AWG_RELEASE="0.1.8"
RUN wget https://github.com/amnezia-vpn/amneziawg-go/archive/refs/tags/v${AWG_RELEASE}.tar.gz && \
    tar -xvzf v${AWG_RELEASE}.tar.gz && \
    cd amneziawg-go-${AWG_RELEASE} && \
    go mod download && \
    go mod verify && \
    go build -ldflags '-linkmode external -extldflags "-fno-PIC -static"' -v -o /usr/bin

# Build AmneziaWG tools

FROM alpine:3.15 as awg-tools
ARG AWGTOOLS_RELEASE="1.0.20231215"
RUN apk --no-cache add linux-headers build-base bash && \
    wget https://github.com/amnezia-vpn/amneziawg-tools/archive/refs/tags/v${AWGTOOLS_RELEASE}.zip && \
    unzip v${AWGTOOLS_RELEASE}.zip && \
    cd amneziawg-tools-${AWGTOOLS_RELEASE}/src && \
    make -e LDFLAGS=-static && \
    make install

# There's an issue with node:20-alpine.
# Docker deployment is canceled after 25< minutes.

FROM docker.io/library/node:18-alpine AS build_node_modules

# Copy Web UI
COPY src/ /app/
WORKDIR /app
RUN npm ci --omit=dev

# Copy build result to a new image.
# This saves a lot of disk space.
FROM docker.io/library/node:18-alpine
COPY --from=build_node_modules /app /app

# Move node_modules one directory up, so during development
# we don't have to mount it in a volume.
# This results in much faster reloading!
#
# Also, some node_modules might be native, and
# the architecture & OS of your development machine might differ
# than what runs inside of docker.
RUN mv /app/node_modules /node_modules

# Enable this to run `npm run serve`
RUN npm i -g nodemon

# Install Linux packages
RUN apk add --no-cache \
    dpkg \
    dumb-init \
    iptables \
    iptables-legacy \
    wireguard-tools

# Use iptables-legacy
RUN update-alternatives --install /sbin/iptables iptables /sbin/iptables-legacy 10 --slave /sbin/iptables-restore iptables-restore /sbin/iptables-legacy-restore --slave /sbin/iptables-save iptables-save /sbin/iptables-legacy-save

# Expose Ports
EXPOSE 51820/udp
EXPOSE 51821/tcp

# Set Environment
ENV DEBUG=Server,WireGuard

# Copy AmneziaWG binaries
COPY --from=awg /usr/bin/amnezia-wg /usr/bin/wireguard-go
COPY --from=awg-tools /usr/bin/wg /usr/bin/wg-quick /usr/bin/

# Run Web UI
WORKDIR /app
CMD ["/usr/bin/dumb-init", "node", "server.js"]
