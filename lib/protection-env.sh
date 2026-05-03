# Read this file first when changing the env wrapper.
# Purpose: catch "env [VAR=val ...] git ..." spellings so the git wrappers
#          still trigger when an agent tries to route around them via env.
# Scope: relies on the git()/git.exe() wrappers from protection-git.sh and
#        the toggle helpers from protection-core.sh.

_ss_is_env_assignment() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
}

# Agents and tools sometimes spell the executable as "git.exe" or route it
# through "env". Catch the simple env forms here; complex env options fall
# back unchanged because emulating GNU env fully would be more dangerous.
env() {
    local -a original_args=("$@")
    local -a env_assignments=()
    local env_cmd env_cmd_lower assignment

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --)
                shift
                break
                ;;
            -*)
                command env "${original_args[@]}"
                return $?
                ;;
        esac

        if _ss_is_env_assignment "$1"; then
            env_assignments+=("$1")
            shift
            continue
        fi

        break
    done

    if [ "$#" -gt 0 ]; then
        env_cmd="$1"
        env_cmd_lower="${env_cmd,,}"
        shift
        case "$env_cmd_lower" in
            git|git.exe)
                (
                    for assignment in "${env_assignments[@]}"; do
                        export "$assignment"
                    done
                    _ss_git_command_name="env $env_cmd" git "$@"
                )
                return $?
                ;;
        esac
    fi

    command env "${original_args[@]}"
}
