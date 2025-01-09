import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import {
  exec,
  execFile,
  ExecFileOptions,
  execFileSync,
  execSync,
} from "child_process";

import * as tar from "tar";
import log from "electron-log";

import { app } from "electron";

////////////////////////////////////////////////
//
// General Utils
//
////////////////////////////////////////////////

export function getAppDir(): string {
  let appDir = app.getAppPath();
  if (!app.isPackaged) {
    appDir = path.dirname(appDir);
  }
  return appDir;
}

export function getUserHomeDir(): string {
  return app.getPath("home");
}

export function getUserDataDir(): string {
  const userDataDir = app.getPath("userData");

  if (!fs.existsSync(userDataDir)) {
    try {
      fs.mkdirSync(userDataDir, { recursive: true });
    } catch (error) {
      log.error(error);
    }
  }

  return userDataDir;
}

////////////////////////////////////////////////
//
// Python Utils
//
////////////////////////////////////////////////

export function getPackagedPythonTarPath(): string {
  const appDir = getAppDir();
  return path.join(appDir, "resources", "python.tar.gz");
}

export function getBundledPythonEnvDir(): string {
  const installDir =
    process.platform === "darwin"
      ? path.normalize(path.join(app.getPath("home"), "Library", app.getName()))
      : app.getPath("userData");

  if (!fs.existsSync(installDir)) {
    try {
      fs.mkdirSync(installDir, { recursive: true });
    } catch (error) {
      log.error(error);
    }
  }
  return installDir;
}

export function getBundledPythonEnvPath(): string {
  const userDataDir = getBundledPythonEnvDir();

  return path.join(userDataDir, "python");
}

export function isCondaEnv(envPath: string): boolean {
  return fs.existsSync(path.join(envPath, "conda-meta"));
}

export function getPythonPath(envPath: string, isConda?: boolean) {
  if (process.platform === "win32") {
    return isConda ?? isCondaEnv(envPath)
      ? path.join(envPath, "python.exe")
      : path.join(envPath, "Scripts", "python.exe");
  } else {
    return path.join(envPath, "bin", "python");
  }
}
