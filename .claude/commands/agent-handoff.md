# Agent Handoff Commands

## Quick Handoff Commands

### Check Agent Status
```bash
claude --read "docs/agent-status.md" --prompt "Show current agent status and next handoffs"
```

### Execute Agent Handoff
```bash
claude --task "Execute handoff from @requirements-analyst-plus to @postgresql-finance-specialist-plus based on status in docs/agent-status.md"
```

### Update Agent Status
```bash
claude --task "Update agent status in docs/agent-status.md for @{agent-name} with status {status} and deliverables {list}"
```

### Check Dependencies
```bash
claude --read "docs/agent-status.md" --prompt "Validate all dependencies are satisfied for @{target-agent}"
```

## Handoff Validation

### Pre-Handoff Checklist
```bash
claude --task "Validate handoff readiness from @{source-agent} to @{target-agent} using docs/agent-status.md protocol"
```

### Post-Handoff Verification
```bash
claude --task "Verify successful handoff completion and update agent-status.md with new status"
```

## Emergency Commands

### Block Agent
```bash
claude --task "Mark @{agent-name} as BLOCKED in docs/agent-status.md with reason: {blocker-description}"
```

### Escalate Issue
```bash
claude --task "Escalate blocking issue to @senior-developer-agent via docs/agent-status.md protocol"
```

### Find Alternative Path
```bash
claude --task "Analyze dependency failure and identify alternative work streams in docs/agent-status.md"
```