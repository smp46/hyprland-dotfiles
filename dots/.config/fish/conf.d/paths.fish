# User PATH entries (ported from the old zsh config).
# Runs for every fish, including the login shell SDDM uses to build the
# Hyprland session environment. fish_add_path skips dirs that don't exist,
# so this is safe on machines without some of these toolchains.
fish_add_path -g ~/.local/bin ~/go/bin ~/.ghcup/bin ~/.cargo/bin
fish_add_path -g -a ~/android-studio/bin

# nvm is bash/zsh-only: put its default Node on PATH directly.
# Resolves an alias like "22" to the newest installed v22.x, falling back to
# the newest installed version for aliases such as "node" or "lts/*".
if test -d ~/.nvm/versions/node
    set -l want ""
    test -f ~/.nvm/alias/default; and set want (string trim < ~/.nvm/alias/default)
    set -l candidates ~/.nvm/versions/node/v$want*
    test (count $candidates) -eq 0; and set candidates ~/.nvm/versions/node/v*
    if test (count $candidates) -gt 0
        set -l node_dir (printf '%s\n' $candidates | sort -V | tail -n1)
        fish_add_path -g $node_dir/bin
        set -gx NVM_DIR ~/.nvm
    end
end
