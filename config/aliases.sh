# Custom aliases

# Zellij needs local (non-NFS) cache for plugin filesystem entries (Unix sockets)
zellij() {
    XDG_CACHE_HOME="/tmp/cache-$(id -u)" command zellij "$@"
}
