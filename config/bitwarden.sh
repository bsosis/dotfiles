# Bitwarden CLI helpers for secret management
# Usage: Run 'load_secrets' once per session, then submit jobs with 'sbatch --export=ALL'

_bw_ensure_unlocked() {
    if [[ -z "${BW_SESSION:-}" ]]; then
        local session
        while true; do
            session="$(bw unlock --raw)"
            if [[ -n "$session" ]]; then
                export BW_SESSION="$session"
                return 0
            fi
            echo "Incorrect password, please try again." >&2
        done
    fi
}

# Helper to load a single secret silently
_bw_load_one() {
    local _env_var="$1" _bw_item="$2" _val
    _val="$(bw get notes "$_bw_item")" || return 1
    [[ -n "$_val" ]] || return 1
    export "$_env_var"="$_val"
}

load_secrets() {
    if ! _bw_ensure_unlocked; then
        return 1
    fi

    # Load secret names from config file
    if [[ ! -f "$VAST_PREFIX/.bitwarden_secrets" ]]; then
        echo "Error: $VAST_PREFIX/.bitwarden_secrets not found." >&2
        echo "Run setup_bitwarden.sh to configure your secrets." >&2
        return 1
    fi

    local loaded=0 failed=0
    while IFS='=' read -r env_var bw_item || [[ -n "$env_var" ]]; do
        # Skip empty lines and comments
        [[ -z "$env_var" || "$env_var" == \#* ]] && continue
        if _bw_load_one "$env_var" "$bw_item" >/dev/null 2>&1; then
            ((loaded++))
        else
            ((failed++))
        fi
    done < "$VAST_PREFIX/.bitwarden_secrets"

    if [[ $failed -gt 0 ]]; then
        echo "Loaded $loaded secrets ($failed failed)." >&2
        return 1
    fi
    echo "Loaded $loaded secrets."
}

# List of secret env vars for explicit SLURM export (populated by load_secrets)
_get_secret_vars() {
    [[ -f "$VAST_PREFIX/.bitwarden_secrets" ]] || return
    grep -v '^#' "$VAST_PREFIX/.bitwarden_secrets" | grep -v '^$' | cut -d'=' -f1 | tr '\n' ',' | sed 's/,$//'
}
