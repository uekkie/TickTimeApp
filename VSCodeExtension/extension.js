'use strict';

const vscode = require('vscode');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { execFile } = require('node:child_process');
const {
  shouldRecord,
  heartbeatPeriod,
  contextForElapsedPeriod,
  trackingContextPath,
  interactionSourceChanged,
  relativeEntity,
  parseSystemIdleSeconds
} = require('./heartbeat-core');

const dataDirectory = path.join(
  os.homedir(),
  'Library',
  'Application Support',
  'TickTime'
);
const inboxPath = path.join(dataDirectory, 'inbox');
const controlStatePath = path.join(dataDirectory, 'control.json');

let lastHeartbeatAt = Date.now();
let lastContext = null;
let timer;
let writingHeartbeat = false;
let pendingHeartbeat = false;
let pendingForce = false;
let interactionSource = 'editor';
let terminalCwd = null;
const branchCache = new Map();
const repositoryCache = new Map();

function activate(context) {
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 90);
  status.text = '$(clock) TickTime';
  status.tooltip = 'リポジトリの作業時間をローカルに記録中';
  status.command = 'TickTime.openDashboard';
  status.show();
  context.subscriptions.push(status);

  const noteEditorInteraction = () => {
    const sourceChanged = interactionSourceChanged(interactionSource, 'editor');
    interactionSource = 'editor';
    return sourceChanged;
  };
  const noteTerminalInteraction = (terminal = vscode.window.activeTerminal) => {
    interactionSource = 'terminal';
    terminalCwd = fileSystemPath(terminal?.shellIntegration?.cwd);
  };

  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(() => {
      noteEditorInteraction();
      writeHeartbeat(false);
    }),
    vscode.window.onDidChangeTextEditorSelection(() => {
      if (noteEditorInteraction()) writeHeartbeat(false);
    }),
    vscode.workspace.onDidChangeTextDocument((event) => {
      if (event.document === vscode.window.activeTextEditor?.document
          && noteEditorInteraction()) {
        writeHeartbeat(false);
      }
    }),
    vscode.window.onDidChangeActiveTerminal((terminal) => {
      noteTerminalInteraction(terminal);
      writeHeartbeat(false);
    }),
    vscode.commands.registerCommand('TickTime.sendHeartbeat', async () => {
      await writeHeartbeat(true);
      vscode.window.setStatusBarMessage('$(check) TickTimeに記録しました', 2000);
    }),
    vscode.commands.registerCommand('TickTime.openDashboard', openDashboard),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('TickTime.heartbeatIntervalSeconds')) {
        restartTimer();
      }
    })
  );

  if (vscode.window.onDidChangeTerminalShellIntegration) {
    context.subscriptions.push(
      vscode.window.onDidChangeTerminalShellIntegration((event) => {
        if (event.terminal === vscode.window.activeTerminal) {
          noteTerminalInteraction(event.terminal);
        }
      })
    );
  }
  if (vscode.window.onDidStartTerminalShellExecution) {
    context.subscriptions.push(
      vscode.window.onDidStartTerminalShellExecution((event) => {
        interactionSource = 'terminal';
        terminalCwd = fileSystemPath(event.execution.cwd)
          || fileSystemPath(event.shellIntegration.cwd);
        writeHeartbeat(false);
      })
    );
  }

  restartTimer();
  setTimeout(() => writeHeartbeat(false), 1500);
}

function restartTimer() {
  if (timer) clearInterval(timer);
  timer = setInterval(
    () => writeHeartbeat(false),
    configuration().heartbeatIntervalSeconds * 1000
  );
}

function configuration() {
  const config = vscode.workspace.getConfiguration('TickTime');
  return {
    enabled: config.get('enabled', true),
    heartbeatIntervalSeconds: config.get('heartbeatIntervalSeconds', 15),
    idleTimeoutSeconds: config.get('idleTimeoutSeconds', 120)
  };
}

async function writeHeartbeat(force) {
  if (writingHeartbeat) {
    pendingHeartbeat = true;
    pendingForce = pendingForce || force;
    return;
  }
  writingHeartbeat = true;

  const now = Date.now();
  try {
    const config = configuration();
    const editor = vscode.window.activeTextEditor;
    const document = editor?.document;
    const folder = document
      ? vscode.workspace.getWorkspaceFolder(document.uri)
      : vscode.workspace.workspaceFolders?.[0];
    const isTerminalContext = interactionSource === 'terminal';
    if (isTerminalContext) {
      terminalCwd = fileSystemPath(vscode.window.activeTerminal?.shellIntegration?.cwd)
        || terminalCwd;
    }
    const contextPath = trackingContextPath({
      interactionSource,
      terminalCwd,
      documentPath: document?.uri.scheme === 'file' ? document.uri.fsPath : null,
      workspacePath: folder?.uri.scheme === 'file' ? folder.uri.fsPath : null
    });
    const controlState = await readControlState(config);
    const systemIdleSeconds = await readSystemIdleSeconds();
    const canRecord = controlState.trackingEnabled && config.enabled && (
      force || shouldRecord({
        enabled: true,
        focused: vscode.window.state.focused,
        hasWorkspace: Boolean(contextPath),
        systemIdleSeconds,
        idleTimeoutSeconds: controlState.idleTimeoutSeconds
      })
    );

    if (!canRecord || !contextPath) {
      lastHeartbeatAt = now;
      lastContext = null;
      return;
    }

    const repository = await repositoryRoot(contextPath);
    if (!repository) {
      lastHeartbeatAt = now;
      lastContext = null;
      return;
    }

    const currentContext = {
      editor: 'Visual Studio Code',
      project: path.basename(repository),
      repository,
      branch: await currentBranch(repository),
      language: isTerminalContext ? null : document?.languageId || null,
      entity: !isTerminalContext && document?.uri.scheme === 'file'
        ? relativeEntity(repository, document.uri.fsPath)
        : null
    };

    if (!lastContext && !force) {
      lastContext = currentContext;
      lastHeartbeatAt = now;
      return;
    }
    if (!lastContext) {
      lastContext = currentContext;
      lastHeartbeatAt = now - 2_000;
    }

    const period = heartbeatPeriod({
      now,
      lastHeartbeatAt,
      intervalSeconds: config.heartbeatIntervalSeconds
    });
    if (period.durationSeconds >= 2) {
      await emitHeartbeat(
        contextForElapsedPeriod(lastContext, currentContext),
        period
      );
    }
    lastHeartbeatAt = now;
    lastContext = currentContext;
  } catch (error) {
    console.error('TickTime heartbeat error:', error);
  } finally {
    writingHeartbeat = false;
    if (pendingHeartbeat) {
      const forcePendingHeartbeat = pendingForce;
      pendingHeartbeat = false;
      pendingForce = false;
      setImmediate(() => writeHeartbeat(forcePendingHeartbeat));
    }
  }
}

function fileSystemPath(uri) {
  return uri?.scheme === 'file' ? uri.fsPath : null;
}

async function emitHeartbeat(context, period) {
  const id = crypto.randomUUID();
  const heartbeat = {
    id,
    ...context,
    occurredAt: period.occurredAt,
    durationSeconds: period.durationSeconds
  };
  await fs.mkdir(inboxPath, { recursive: true });
  const temporaryPath = path.join(inboxPath, `.${id}.tmp`);
  const finalPath = path.join(inboxPath, `${id}.json`);
  await fs.writeFile(temporaryPath, JSON.stringify(heartbeat), 'utf8');
  await fs.rename(temporaryPath, finalPath);
}

async function readControlState(config) {
  try {
    const state = JSON.parse(await fs.readFile(controlStatePath, 'utf8'));
    return {
      trackingEnabled: state.trackingEnabled !== false,
      idleTimeoutSeconds: Number(state.idleTimeoutSeconds) || config.idleTimeoutSeconds
    };
  } catch {
    return {
      trackingEnabled: true,
      idleTimeoutSeconds: config.idleTimeoutSeconds
    };
  }
}

function readSystemIdleSeconds() {
  return new Promise((resolve) => {
    execFile('/usr/sbin/ioreg', ['-c', 'IOHIDSystem'], { timeout: 2000 }, (error, stdout) => {
      resolve(error ? 0 : parseSystemIdleSeconds(stdout));
    });
  });
}

function repositoryRoot(contextPath) {
  const cached = repositoryCache.get(contextPath);
  if (cached && Date.now() - cached.savedAt < 30_000) {
    return Promise.resolve(cached.repository);
  }

  return new Promise((resolve) => {
    execFile(
      '/usr/bin/git',
      ['-C', contextPath, 'rev-parse', '--show-toplevel'],
      { timeout: 2000 },
      (error, stdout) => {
        const repository = error ? null : stdout.trim() || null;
        repositoryCache.set(contextPath, { repository, savedAt: Date.now() });
        resolve(repository);
      }
    );
  });
}

function currentBranch(repository) {
  const cached = branchCache.get(repository);
  if (cached && Date.now() - cached.savedAt < 30_000) {
    return Promise.resolve(cached.branch);
  }

  return new Promise((resolve) => {
    execFile(
      '/usr/bin/git',
      ['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
      { timeout: 2000 },
      (error, stdout) => {
        const branch = error ? null : stdout.trim() || null;
        branchCache.set(repository, { branch, savedAt: Date.now() });
        resolve(branch);
      }
    );
  });
}

function openDashboard() {
  execFile('/usr/bin/open', ['-b', 'dev.TickTime.TickTime'], (error) => {
    if (error) {
      vscode.window.showWarningMessage(
        'TickTimeアプリを開けませんでした。TickTime.appを先に起動してください。'
      );
    }
  });
}

function deactivate() {
  if (timer) clearInterval(timer);
}

module.exports = { activate, deactivate };
