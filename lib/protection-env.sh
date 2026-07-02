# Read this file first when changing the env wrapper.
# Purpose: catch "env [VAR=val ...] <tool> ..." spellings so the protected
#          wrappers still trigger when an agent tries to route around them via
#          env. Covers the delete (rm/cmd), git, curl and PowerShell wrappers.
# Scope: relies on the rm()/cmd()/cmd.exe(), git()/git.exe(), curl()/curl.exe()
#        and powershell() (plus *.exe/pwsh) wrappers from the delete, git, http
#        and ps slices, plus the toggle helpers from protection-core.sh.

_ss_is_env_assignment() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
}

# Agents and tools sometimes spell executables as *.exe or route them through
# "env". Catch the simple env forms here; complex env options fall back
# unchanged because emulating GNU env fully would be more dangerous.
# env_cmd_lower is already lower-cased, so a single lower-case case arm covers
# every spelling variant (Powershell.exe, RM, Cmd, ...); the original spelling
# in $env_cmd is preserved for the block diagnostics.
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
            rm)
                (
                    for assignment in "${env_assignments[@]}"; do
                        export "$assignment"
                    done
                    rm "$@"
                )
                return $?
                ;;
            cmd|cmd.exe)
                (
                    for assignment in "${env_assignments[@]}"; do
                        export "$assignment"
                    done
                    cmd "$@"
                )
                return $?
                ;;
            powershell|powershell.exe|pwsh|pwsh.exe)
                (
                    for assignment in "${env_assignments[@]}"; do
                        export "$assignment"
                    done
                    _ss_powershell_command_name="env $env_cmd" powershell "$@"
                )
                return $?
                ;;
            git|git.exe)
                (
                    for assignment in "${env_assignments[@]}"; do
                        export "$assignment"
                    done
                    _ss_git_command_name="env $env_cmd" git "$@"
                )
                return $?
                ;;
            curl|curl.exe)
                (
                    for assignment in "${env_assignments[@]}"; do
                        export "$assignment"
                    done
                    _ss_curl_command_name="env $env_cmd" curl "$@"
                )
                return $?
                ;;
        esac
    fi

    command env "${original_args[@]}"
}
