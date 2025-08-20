# Enhanced Agent Activation Guide

## Quick Start Commands

### Activate Enhanced PostgreSQL Agent
```bash
claude --task "Use the postgresql-finance-specialist-plus agent to review current database implementation and add DevOps monitoring capabilities"
```

### Activate Enhanced Requirements Agent  
```bash
claude --task "Use the requirements-analyst-plus agent to validate current implementation against business requirements v1.2"
```

### Activate Security Reviewer Agent
```bash
claude --task "Use the security-reviewer-agent to audit database security and compliance controls"
```

### Activate Senior Developer Agent
```bash
claude --task "Use the senior-developer-agent to coordinate system architecture and integration patterns"
```

## Agent Capability Matrix

| Agent | Core Domain | DevOps | Security | Validation | Coordination |
|-------|-------------|--------|----------|------------|--------------|
| postgresql-finance-specialist-plus | ✅ | ✅ | ✅ | ✅ | - |
| requirements-analyst-plus | ✅ | - | - | ✅ | - |
| security-reviewer-agent | - | - | ✅ | ✅ | - |
| senior-developer-agent | - | ✅ | - | ✅ | ✅ |

## Implementation Sequence

1. **PostgreSQL Agent Enhancement** - Add monitoring, backup, security
2. **Requirements Agent Enhancement** - Add validation, compliance checking  
3. **Security Agent Deployment** - Independent security review
4. **Senior Developer Coordination** - System integration oversight

## Quality Gate Triggers

### Automatic Triggers
- Database schema changes → Security review required
- New stored procedures → Performance validation required
- Requirements changes → Implementation validation required
- Cross-system integration → Senior developer coordination required

### Manual Triggers
```bash
# Trigger full system validation
claude --task "Run complete quality gate validation across all enhanced agents"

# Trigger compliance audit
claude --task "Execute SOX compliance validation using security-reviewer-agent"
```