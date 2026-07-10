#!/bin/sh

# Only interactive SSH sessions with a TTY receive the status panel.
# This guard is safe to source from /etc/profile.d: scp, rsync, and
# `ssh host command` do not have an interactive shell and produce no output.
case $- in
    *i*)
        if [ -n "${SSH_TTY:-}" ] && command -v ssh-status >/dev/null 2>&1; then
            ssh-status
        fi
        ;;
esac
