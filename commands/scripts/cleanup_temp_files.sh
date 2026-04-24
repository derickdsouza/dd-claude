#!/bin/bash

# Claude Directory Cleanup Script
# Safely removes temporary files while preserving important data

set -e  # Exit on any error

CLAUDE_DIR="/Users/derickdsouza/.claude"
BACKUP_DIR="${CLAUDE_DIR}/cleanup_backup_$(date +%Y%m%d_%H%M%S)"

echo "🧹 Claude Directory Cleanup Script"
echo "=================================="
echo ""

# Create backup directory for safety
echo "📦 Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

cd "${CLAUDE_DIR}"

echo ""
echo "🔍 Analyzing temporary files..."

# Count files before cleanup
PROJECT_STATE_COUNT=$(ls project-state-*.json 2>/dev/null | wc -l | tr -d ' ')
SESSION_ID_COUNT=$(ls session-*.id 2>/dev/null | wc -l | tr -d ' ')
SESSION_FLAG_COUNT=$(ls session-initialized-*.flag 2>/dev/null | wc -l | tr -d ' ')
DS_STORE_COUNT=$(find . -name ".DS_Store" 2>/dev/null | wc -l | tr -d ' ')

echo "  • Project state files: ${PROJECT_STATE_COUNT}"
echo "  • Session ID files: ${SESSION_ID_COUNT}"
echo "  • Session flag files: ${SESSION_FLAG_COUNT}"
echo "  • DS_Store files: ${DS_STORE_COUNT}"

echo ""
echo "💾 Creating backup of settings files..."
# Backup important files before cleanup
cp settings.json "${BACKUP_DIR}/" 2>/dev/null || echo "  ⚠️  settings.json not found"
cp .update.lock "${BACKUP_DIR}/" 2>/dev/null || echo "  ⚠️  .update.lock not found"

echo ""
echo "🗑️  Removing temporary files..."

# Remove project state files
if [ "${PROJECT_STATE_COUNT}" -gt 0 ]; then
    echo "  • Removing ${PROJECT_STATE_COUNT} project state files..."
    rm -f project-state-*.json
    echo "    ✅ Project state files removed"
fi

# Remove session ID files
if [ "${SESSION_ID_COUNT}" -gt 0 ]; then
    echo "  • Removing ${SESSION_ID_COUNT} session ID files..."
    rm -f session-*.id
    echo "    ✅ Session ID files removed"
fi

# Remove session flag files
if [ "${SESSION_FLAG_COUNT}" -gt 0 ]; then
    echo "  • Removing ${SESSION_FLAG_COUNT} session flag files..."
    rm -f session-initialized-*.flag
    echo "    ✅ Session flag files removed"
fi

# Remove DS_Store files
if [ "${DS_STORE_COUNT}" -gt 0 ]; then
    echo "  • Removing ${DS_STORE_COUNT} .DS_Store files..."
    find . -name ".DS_Store" -delete 2>/dev/null
    echo "    ✅ .DS_Store files removed"
fi

# Remove update lock file
if [ -f ".update.lock" ]; then
    echo "  • Removing update lock file..."
    rm -f .update.lock
    echo "    ✅ Update lock file removed"
fi

echo ""
echo "📊 Cleanup Summary:"
echo "=================="

# Calculate space saved
TOTAL_REMOVED=$((PROJECT_STATE_COUNT + SESSION_ID_COUNT + SESSION_FLAG_COUNT + DS_STORE_COUNT + 1))
echo "  • Total files removed: ${TOTAL_REMOVED}"

# Show remaining important files
echo ""
echo "📋 Important files preserved:"
echo "  • CLAUDE.md ✅"
echo "  • git_commit_protocol.md ✅"
echo "  • context_monitor.md ✅"
echo "  • settings.json ✅"
echo "  • settings.json.backup ✅"

echo ""
echo "💾 Backup created at: ${BACKUP_DIR}"
echo ""
echo "✨ Cleanup completed successfully!"
echo ""
echo "🔍 Disk space analysis:"
du -sh . 2>/dev/null && echo "  Current directory size: $(du -sh . 2>/dev/null | cut -f1)"

echo ""
echo "⚠️  Note: Large .jsonl files in ./projects/ were preserved"
echo "   These may contain valuable project history"
echo "   Review manually if cleanup is needed"