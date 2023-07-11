function pkgctl {
    local cmd cmd_file code
	cmd_file=$(mktemp --tmpdir "pkgctl.outcmd.XXXXXXXXXX")

    if PKGCTL_OUTCMD="${cmd_file}" command pkgctl "$@"; then
        cmd=$(<"$cmd_file")
        command rm -f "$cmd_file"
        eval "$cmd"
    else
        code=$?
        command rm -f "$cmd_file"
        return "$code"
    fi
}

#\builtin alias pkgctl=__pkgctl

# =============================================================================
#
# To initialize pkgctl, add this to your configuration (usually ~/.zshrc):
#
# eval "$(pkgctl init bash)"
