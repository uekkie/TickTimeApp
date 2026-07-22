'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  shouldRecord,
  heartbeatPeriod,
  contextForElapsedPeriod,
  trackingContextPath,
  interactionSourceChanged,
  relativeEntity,
  parseSystemIdleSeconds
} = require('../heartbeat-core');

test('records only while focused and the Mac is active', () => {
  const base = {
    enabled: true,
    focused: true,
    hasWorkspace: true,
    systemIdleSeconds: 10,
    idleTimeoutSeconds: 120
  };

  assert.equal(shouldRecord(base), true);
  assert.equal(shouldRecord({ ...base, focused: false }), false);
  assert.equal(shouldRecord({ ...base, systemIdleSeconds: 121 }), false);
});

test('parses macOS HID idle time from ioreg output', () => {
  assert.equal(
    parseSystemIdleSeconds('    | |   "HIDIdleTime" = 12500000000\n'),
    12.5
  );
});

test('caps a heartbeat to the configured interval', () => {
  assert.deepEqual(
    heartbeatPeriod({ now: 20_000, lastHeartbeatAt: 1_000, intervalSeconds: 15 }),
    { occurredAt: new Date(5_000).toISOString(), durationSeconds: 15 }
  );
});

test('does not invent time when less than two seconds elapsed', () => {
  assert.equal(
    heartbeatPeriod({ now: 2_000, lastHeartbeatAt: 1_000, intervalSeconds: 15 })
      .durationSeconds,
    1
  );
});

test('attributes elapsed time to the repository active before a switch', () => {
  const previous = { project: 'repository-a' };
  const current = { project: 'repository-b' };

  assert.equal(contextForElapsedPeriod(previous, current), previous);
});

test('uses the active terminal cwd instead of the editor repository', () => {
  assert.equal(
    trackingContextPath({
      interactionSource: 'terminal',
      terminalCwd: '/code/repository-b',
      documentPath: '/code/repository-a/App.swift',
      workspacePath: '/code'
    }),
    '/code/repository-b'
  );
});

test('skips terminal attribution when shell integration has no cwd', () => {
  assert.equal(
    trackingContextPath({
      interactionSource: 'terminal',
      terminalCwd: null,
      documentPath: '/code/repository-a/App.swift',
      workspacePath: '/code'
    }),
    null
  );
});

test('detects returning from terminal to editor', () => {
  assert.equal(interactionSourceChanged('terminal', 'editor'), true);
  assert.equal(interactionSourceChanged('editor', 'editor'), false);
});

test('stores file paths relative to the repository', () => {
  assert.equal(
    relativeEntity('/code/TickTime', '/code/TickTime/Sources/App.swift'),
    'Sources/App.swift'
  );
});
