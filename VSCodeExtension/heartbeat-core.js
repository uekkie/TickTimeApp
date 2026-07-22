'use strict';

const path = require('node:path');

function shouldRecord({
  enabled,
  focused,
  hasWorkspace,
  systemIdleSeconds,
  idleTimeoutSeconds
}) {
  return Boolean(
    enabled
      && focused
      && hasWorkspace
      && systemIdleSeconds <= idleTimeoutSeconds
  );
}

function heartbeatPeriod({ now, lastHeartbeatAt, intervalSeconds }) {
  const elapsedSeconds = Math.max(0, (now - lastHeartbeatAt) / 1000);
  const durationSeconds = Math.min(intervalSeconds, elapsedSeconds);
  return {
    occurredAt: new Date(now - durationSeconds * 1000).toISOString(),
    durationSeconds
  };
}

function contextForElapsedPeriod(previousContext, currentContext) {
  return previousContext ?? currentContext;
}

function trackingContextPath({
  interactionSource,
  terminalCwd,
  documentPath,
  workspacePath
}) {
  if (interactionSource === 'terminal') {
    return terminalCwd || null;
  }
  if (documentPath) return path.dirname(documentPath);
  return workspacePath || null;
}

function interactionSourceChanged(previousSource, nextSource) {
  return previousSource !== nextSource;
}

function relativeEntity(repository, filePath) {
  return path.relative(repository, filePath).split(path.sep).join('/');
}

function parseSystemIdleSeconds(ioregOutput) {
  const match = ioregOutput.match(/"HIDIdleTime"\s*=\s*(\d+)/);
  return match ? Number(match[1]) / 1_000_000_000 : 0;
}

module.exports = {
  shouldRecord,
  heartbeatPeriod,
  contextForElapsedPeriod,
  trackingContextPath,
  interactionSourceChanged,
  relativeEntity,
  parseSystemIdleSeconds
};
