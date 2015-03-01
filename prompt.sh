find_git_branch() {
  # Based on: http://stackoverflow.com/a/13003854/170413
  local branch
  if branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null); then
    if [[ "$branch" == "HEAD" ]]; then
      #branch='<detached>'
      # Or show the short hash
      branch='#'$(git rev-parse --short HEAD 2> /dev/null)
    fi
    git_branch=" [$branch]"
  else
    git_branch=""
  fi
}

find_git_dirty() {
  git_dirty=''
  git_dirty_count=''
  git_staged_mark=''
  git_staged_count=''

  # Optimization.  Requires that find_git_branch always runs before find_git_dirty in PROMPT_COMMAND or zsh's precmd hook.
  if [[ -z "$git_branch" ]]; then
    return
  fi

  # The following will abort the `git status` process if it is taking too long to complete.
  # This can happen on machines with slow disc access.
  # Hopefully each attempt will pull additional data into the FS cache, so on a later attempt it will complete in time.
  # On a large folder, this can take a lot of attempts, and rarely the cache will never fill!
  # However forcing data into the cache by running `git status` manually always seems to work.
  # To prevent that manual intervention, we may want to let the process to *continue* in the background.  (In which case we might also want to ensure that multiple attempts do not run in parallel, or at least use different tempfiles.)

  local gs_done_file=/tmp/done_gs.$USER.$$
  local gs_porc_file=/tmp/gs_porc.$USER.$$
  # We need to start a subshell here, otherwise the `wait` below will be applied to jobs which the user has backgrounded (observed in zsh).  We only want it to apply to the two parallel jobs we start here.
  (
    # This is needed to stop zsh from spamming four job info messages!
    [[ -n "$ZSH_NAME" ]] && unsetopt MONITOR
    ( git status --porcelain 2> /dev/null > "$gs_porc_file" ; touch "$gs_done_file" ) &
    local gs_shell_pid="$!"
    (
      # Keep checking if the `git status` has completed; and if it has, abort.
      # This number defines the length of the timeout (in tenths of a second).
      for X in `seq 1 10`; do
        sleep 0.1
        [[ -f "$gs_done_file" ]] && exit
      done
      # If the timeout is reached, kill the `git status`.
      # Killing the parent (...)& shell is not enough; we also need to kill the child `git status` process running inside it.
      # We must do this before killing the parent, because killing the parent first would leave the orphaned process with PPID 1.
      pkill -P "$gs_shell_pid"
      kill "$gs_shell_pid"
      # We may want to add 2>/dev/null to the two lines above, in case the process completes *just* before we issue the kill signal.
    ) &
    wait
  )
  if [[ ! -f "$gs_done_file" ]]; then
    git_dirty='#'
    return
  fi
  'rm' -f "$gs_done_file"

  # Without a timeout:
  #git status --porcelain 2> /dev/null > "$gs_porc_file"

  # I added the grep -v because I don't mind the odd file hanging around.  Some users may be more strict about this!
  #git_dirty_count=$(grep -c -v '^??' "$gs_porc_file")
  # The second grep hides staged files
  git_dirty_count=$(grep -v '^??' "$gs_porc_file" | grep -c -v '^M ')
  if [[ "$git_dirty_count" > 0 ]]; then
    git_dirty='*'
  else
    git_dirty_count=''
  fi
  # TODO: For consistency with ahead/behind variables, git_dirty could be renamed git_dirty_mark
  #       and s/mark/marker/ why not?

  git_staged_count=$(grep -c '^[AM].' "$gs_porc_file")
  if [[ "$git_staged_count" > 0 ]]; then
    git_staged_mark='+'
  else
    git_staged_count=''
  fi

  'rm' -f "$gs_porc_file"
}

find_git_ahead_behind() {
  git_ahead_count=''
  git_ahead_mark=''
  git_behind_count=''
  git_behind_mark=''
  if [[ -z "$git_branch" ]]; then
    return
  fi
  local local_branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null)
  if [[ -n "$local_branch" ]] && [[ "$local_branch" != "HEAD" ]]; then
    local upstream_branch=$(git rev-parse --abbrev-ref "@{upstream}" 2> /dev/null)
    # If we get back what we put in, then that means the upstream branch was not found.  (This was observed on git 1.7.10.4 on Ubuntu)
    [[ "$upstream_branch" = "@{upstream}" ]] && upstream_branch=''
    # If the branch is not tracking a specific remote branch, then assume we are tracking origin/[this_branch_name]
    [[ -z "$upstream_branch" ]] && upstream_branch="origin/$local_branch"
    if [[ -n "$upstream_branch" ]]; then
      git_ahead_count=$(git rev-list --left-right ${local_branch}...${upstream_branch} 2> /dev/null | grep -c '^<')
      git_behind_count=$(git rev-list --left-right ${local_branch}...${upstream_branch} 2> /dev/null | grep -c '^>')
      if [[ "$git_ahead_count" = 0 ]]; then
        git_ahead_count=''
      else
        git_ahead_mark='>'
      fi
      if [[ "$git_behind_count" = 0 ]]; then
        git_behind_count=''
      else
        git_behind_mark='<'
      fi
    fi
  fi
}

find_git_stash_status() {
  git_stash_mark=''
  if [[ -z "$git_branch" ]]; then
    return
  fi
  local stashed_commit=$(git stash list -n 1 | cut -d ':' -f 3 | cut -d ' ' -f 2)
  local current_commit=$(git rev-parse --short HEAD 2> /dev/null)
  local stashed_branch=$(git stash list -n 1 | cut -d ':' -f 2 | sed 's+.* ++')
  local current_branch=$(git symbolic-ref --short HEAD 2> /dev/null)
  # CONSIDER: Alternatively we could have just grepped `git stast list` for either the commit_id or the branch_name.  This would also indicate older matching stashes.
  if [[ "$stashed_commit" = "$current_commit" ]] || [[ -n "$current_branch" ]] && [[ "$stashed_branch" = "$current_branch" ]]
  then git_stash_mark='(s)'
  fi
}

PROMPT_COMMAND="find_git_branch; find_git_dirty; find_git_ahead_behind; find_git_stash_status; $PROMPT_COMMAND"

# Default Git enabled prompt with dirty state
# export PS1="\u@\h \w\[$txtcyn\]\$git_branch\[$txtred\]\$git_ahead_mark\$git_behind_mark\$git_dirty\[$txtrst\]\$ "

# Another variant, which displays counts after each mark, the number of staged files, and the stash status:
# export PS1="\[$bldgrn\]\u@\h\[$txtrst\] \w\[$txtcyn\]\$git_branch\[$bldgrn\]\$git_ahead_mark\$git_ahead_count\[$txtrst\]\[$bldred\]\$git_behind_mark\$git_behind_count\[$txtrst\]\[$bldyellow\]\$git_stash_mark\[$txtrst\]\[$txtylw\]\$git_dirty\$git_dirty_count\[$txtcyn\]\$git_staged_mark\$git_staged_count\[$txtrst\]\$ "

# Default Git enabled root prompt (for use with "sudo -s")
# export SUDO_PS1="\[$bakred\]\u@\h\[$txtrst\] \w\$ "
