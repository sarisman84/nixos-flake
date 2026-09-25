# shellcheck shell=bash
# Git CLI shortcut commands.

# Dispatches to the appropriate branch subcommand.
branch() {
    local cmd="$1"
    shift

    case "$cmd" in
        create)
            _vc_create "$@"
            ;;
        switch)
            _vc_switch "$@"
            ;;
        list)
            _vc_list "$@"
            ;;
        merge)
            _vc_merge "$@"
            ;;
        -h | --help)
            echo "Shortcuts for Git CLI branch commands."
            echo "Usage: branch {create|switch|list|merge} [args..]"
            echo "  branch list --remote   fetch and list remote branches"
            return 1
            ;;
        *)
            echo "Unknown subcommand: $cmd"
            return 1
            ;;
    esac
}

# Dispatches to the appropriate repo subcommand.
repo() {
    local cmd="$1"
    shift

    case "$cmd" in
        link)
            _vc_repoLink "$@"
            ;;
        -h | --help)
            echo "Shortcuts for Git CLI repository commands."
            echo "Usage: repo {link} [args..]"
            return 1
            ;;
        *)
            echo "Unknown subcommand: $cmd"
            return 1
            ;;
    esac
}

# Stage all changes and commit with the remaining args as the message.
commit() {
    local cmd="$1"

    case "$cmd" in
        -h | --help)
            echo "Command: commit - [message body]"
            echo "Adds all changed and new files and commits a short message."
            echo "Uses: 'git add .' and 'git commit -m' under the hood."
            return 1
            ;;
        *)
            git add .
            git commit -m "$*"
            ;;
    esac
}

# Push to the remote.
push() {
    case "$1" in
        -h | --help)
            echo "Command: push"
            echo "Shorthand for 'git push'"
            return 1
            ;;
        *)
            git push
            ;;
    esac
}

# Pull with rebase to keep history linear.
pull() {
    case "$1" in
        -h | --help)
            echo "Command: pull"
            echo "Shorthand for 'git pull --rebase'"
            return 1
            ;;
        *)
            git pull --rebase
            ;;
    esac
}

# Show the working tree status.
check() {
    case "$1" in
        -h | --help)
            echo "Command: check"
            echo "Shorthand for 'git status'."
            return 1
            ;;
        *)
            git status
            ;;
    esac
}

# Create a new branch and push it to origin with upstream tracking.
_vc_create() {
    git switch -c "$*"
    git push --set-upstream origin "$*"
}

# List local branches, or fetch and list remote branches with --remote.
_vc_list() {
    if [ "$1" = "--remote" ]; then
        git fetch origin --prune 2>/dev/null
        git branch -r --format='%(refname:short)' | grep -v 'HEAD$' | sed 's|^origin/||' | sort -u
    else
        git branch
    fi
}

# Switch to the given branch.
_vc_switch() {
    git switch "$*"
}

# Add origin as the remote for the given URL.
_vc_repoLink() {
    git remote add origin "$*"
}

# Merge the given branch into the current branch.
_vc_merge() {
    git merge "$1"
}
