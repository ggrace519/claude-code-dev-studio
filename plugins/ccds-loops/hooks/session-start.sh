#!/usr/bin/env bash
# ccds-loops SessionStart hook — inject the loop index as context.
# Plain stdout on exit 0 is added to the session's context (hooks reference).
# The injection is what makes the loops load-bearing instead of routing luck:
# descriptions alone under-trigger when the model is mid-task.
set -u
cat <<'EOF'
The ccds-loops process skills are installed. When one applies, using it is not
optional:
- About to claim done/fixed/working/passing -> loop-verify (fresh evidence from the real system first)
- Bug or failing test with an unproven cause -> loop-debug (no fix without a proven root cause)
- Implementation ready for pre-merge review -> loop-review (fresh-context reviewer; never grade your own work)
- Work splits into 3+ independent pieces -> loop-parallel (written file ownership; one build/test lane)
- Task will outlive one context window / unattended run -> loop-long-horizon (state in files; ONE task per iteration)
- User correction, review finding, or repeated mistake -> loop-compound (write the rule where the next session reads it)
Optional stop gate: put one command in .claude/loop-gate.cmd — the session cannot
end while it fails (remove the file to disarm).
EOF
exit 0
