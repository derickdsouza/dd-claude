# Process Management Safety Protocol

## CRITICAL RULE: Never Kill Unrelated Processes

AI agents must follow strict protocols when managing system processes to prevent accidental termination of unrelated work.

---

## FORBIDDEN Commands (Never Use These)

These commands kill ALL matching processes system-wide and are **PROHIBITED**:

```bash
pkill node          # Kills ALL Node.js processes
pkill dotnet        # Kills ALL .NET processes
pkill python        # Kills ALL Python processes
killall <name>      # Kills ALL processes by name
pkill -f <pattern>  # Too broad, kills unrelated processes
```

---

## REQUIRED Safe Practices

### 1. Port-Based Process Identification (Preferred Method)

Always identify processes by the specific port they're listening on:

```bash
# Identify by port
lsof -ti:3000      # Get PID for process on port 3000
lsof -ti:6000      # Get PID for process on port 6000
lsof -ti:5432      # Get PID for process on port 5432

# Kill by port
kill $(lsof -ti:3000)
```

### 2. PID-Based Termination (Safest Method)

```bash
# Find the specific PID first
PID=$(lsof -ti:3000)

# Verify it's the correct process
ps -p $PID -o pid,comm,args

# Kill the specific PID
kill $PID

# Force kill if needed
kill -9 $PID
```

### 3. Project-Specific Process Filtering

When port-based identification isn't available:

```bash
# Filter by working directory (current project only)
ps aux | grep "/path/to/current/project" | grep "node\|dotnet\|python" | awk '{print $2}' | xargs kill

# Verify before killing
ps aux | grep "/Users/username/Projects/myproject"
```

---

## Safe Process Management Workflow

### Before Killing ANY Process:

1. **Identify the specific port or PID**
   ```bash
   lsof -ti:PORT_NUMBER
   ```

2. **Verify the process details**
   ```bash
   ps -p $PID -o pid,ppid,comm,args,cwd
   ```

3. **Check the working directory matches the project**
   ```bash
   lsof -p $PID | grep cwd
   ```

4. **Kill only the verified process**
   ```bash
   kill $PID
   ```

---

## Terminal Management

### VS Code Integrated Terminals:
- Track terminal IDs when starting background processes
- Send interrupts to specific terminals, not system-wide
- Use terminal ID to target specific processes

### Background Process Tracking:

```bash
# When starting a background process, note its PID
dotnet run &  # Returns PID
echo $!       # Last background PID

# Kill that specific PID later
kill $!
```

---

## Emergency Recovery

If you accidentally killed unrelated processes:

1. **Apologize immediately**
2. **Inform the user what was killed**
3. **Provide commands to check what's still running**
4. **Suggest recovery steps if applicable**

---

## Quick Reference Card

### Safe Kill Patterns

```bash
# By port (BEST)
kill $(lsof -ti:PORT)

# By PID with verification (SAFEST)
PID=$(lsof -ti:PORT)
ps -p $PID
kill $PID

# Multiple ports
kill $(lsof -ti:3000) $(lsof -ti:6000)

# Force kill by port
kill -9 $(lsof -ti:PORT)
```

### Forbidden Patterns

```bash
# NEVER USE THESE
pkill node
pkill dotnet
pkill python
killall anything
pkill -f pattern
```

---

## Summary

**Golden Rule**: Always be surgical, never be broad.

- **DO**: Use ports, PIDs, and project paths
- **DON'T**: Use `pkill`, `killall`, or broad patterns
- **UNCERTAIN**: Ask the user before killing anything
- **VERIFY**: Always verify before executing kill commands

**Impact**: Killing the wrong process can destroy hours of work, corrupt data, and break unrelated systems.
