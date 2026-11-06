# bash completion for void
#
# Install this file as:
#   ~/.local/share/bash-completion/completions/void
# or source it from ~/.bashrc:
#   source /path/to/void.bash

_void_services() {
    local cur=$1 dir
    for dir in /etc/sv/*; do
        [[ -d $dir ]] || continue
        [[ ${dir##*/} == "$cur"* ]] && COMPREPLY+=("${dir##*/}")
    done
}

# Catalog names come from the CLI itself so the list never drifts.
# The baked-in list is only a fallback for when the CLI cannot be run.
_void_repo_names() {
    local cur=$1 name names
    names=$("${COMP_WORDS[0]}" pkg repo available 2>/dev/null | awk 'NR > 1 && NF > 2 { print $1 }')
    if [[ -z $names ]]; then
        names="blackhole blackhole-ru hyprland librewolf noid sonicde kennel xlibre
               linuxnauta voiders neko lazy grvn vup-utilities vup-productivity
               vup-browsers vup-communication vup-emulators vup-education
               vup-networking vup-languages vup-language-servers
               vup-runtime-managers"
    fi
    for name in $names; do
        [[ $name == "$cur"* ]] && COMPREPLY+=("$name")
    done
}

_void_installed_packages() {
    local cur=$1 line name
    while IFS= read -r line; do
        name=${line#* }
        name=${name%% *}
        name=$(printf '%s' "$name" | sed -E 's/-[0-9][^-]*_[0-9]+$//')
        [[ -n $name && $name == "$cur"* ]] && COMPREPLY+=("$name")
    done < <(xbps-query -l 2>/dev/null)
}

_void() {
    local cur prev cmd sub
    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD-1]}

    if (( COMP_CWORD == 1 )); then
        mapfile -t COMPREPLY < <(compgen -W \
            "pkg svc update info logs status doctor cheat repo desktop help version install remove search" \
            -- "$cur")
        return 0
    fi

    cmd=${COMP_WORDS[1]}
    sub=${COMP_WORDS[2]:-}

    if [[ $cur == -* ]]; then
        case "$cmd" in
            pkg)
                case "$sub" in
                    install|upgrade|up|sysupgrade|full-upgrade|add)
                        mapfile -t COMPREPLY < <(compgen -W \
                            "-j --jobs -P --parallel --no-parallel -f --force -y --yes -n --dry-run -h --help" \
                            -- "$cur")
                        ;;
                    *)
                        mapfile -t COMPREPLY < <(compgen -W "-y --yes -n --dry-run -h --help" -- "$cur")
                        ;;
                esac
                ;;
            svc) mapfile -t COMPREPLY < <(compgen -W "-y --yes -n --dry-run -h --help --now --all" -- "$cur") ;;
            logs) mapfile -t COMPREPLY < <(compgen -W "-f --follow -n --lines --list -h --help" -- "$cur") ;;
            desktop) mapfile -t COMPREPLY < <(compgen -W "--user --no-icons --no-mime -n --dry-run -h --help" -- "$cur") ;;
            *) mapfile -t COMPREPLY < <(compgen -W "-n --dry-run -y --yes -q --quiet --no-color -h --help -V --version" -- "$cur") ;;
        esac
        return 0
    fi

    case "$cmd" in
        pkg)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W \
                    "install remove update upgrade search info list files owns deps revdeps hold unhold reconfigure autoremove clean repo help" \
                    -- "$cur")
                return 0
            fi
            case "$sub" in
                repo|repos|repositories)
                    if (( COMP_CWORD == 3 )); then
                        mapfile -t COMPREPLY < <(compgen -W \
                            "list available info add remove disable enable refresh help" \
                            -- "$cur")
                    else
                        case "${COMP_WORDS[3]:-}" in
                            info|add|remove|rm|del|disable|enable) _void_repo_names "$cur" ;;
                        esac
                    fi
                    ;;
                install|upgrade|up|sysupgrade|full-upgrade|add)
                    _void_installed_packages "$cur"
                    ;;
                remove|rm|info|show|files|owns|deps|revdeps|hold|unhold|reconfigure)
                    _void_installed_packages "$cur"
                    ;;
                list|ls)
                    mapfile -t COMPREPLY < <(compgen -W "--manual --orphans --hold --repos" -- "$cur")
                    ;;
            esac
            ;;
        svc|service|services)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W \
                    "list status start stop restart reload enable disable logs edit create help" \
                    -- "$cur")
                return 0
            fi
            case "$sub" in
                status|start|stop|restart|reload|enable|disable|logs|edit)
                    _void_services "$cur"
                    ;;
                list|ls)
                    mapfile -t COMPREPLY < <(compgen -W "--all" -- "$cur")
                    ;;
            esac
            ;;
        logs|log)
            _void_services "$cur"
            ;;
        repo|repositories)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W \
                    "list available info add remove disable enable refresh help" \
                    -- "$cur")
            else
                case "${COMP_WORDS[2]:-}" in
                    info|add|remove|rm|del|disable|enable) _void_repo_names "$cur" ;;
                esac
            fi
            ;;
        desktop|desktop-db)
            if (( COMP_CWORD == 2 )); then
                mapfile -t COMPREPLY < <(compgen -W "refresh help" -- "$cur")
            else
                mapfile -t COMPREPLY < <(compgen -W "--user --no-icons --no-mime" -- "$cur")
            fi
            ;;
        cheat|systemd|migrate)
            mapfile -t COMPREPLY < <(compgen -W "packages services logs system network tips" -- "$cur")
            ;;
        help)
            mapfile -t COMPREPLY < <(compgen -W "pkg svc logs repo desktop" -- "$cur")
            ;;
    esac
    return 0
}

complete -F _void void
