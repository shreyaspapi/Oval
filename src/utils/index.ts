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

export function getAppPath(): string {
  let appDir = app.getAppPath();
  if (!app.isPackaged) {
    appDir = path.dirname(appDir);
  }
  return appDir;
}

export function getUserHomePath(): string {
  return app.getPath("home");
}

export function getUserDataPath(): string {
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

export function getBundledPythonTarPath(): string {
  const appPath = getAppPath();
  return path.join(appPath, "resources", "python.tar.gz");
}

export function getBundledPythonInstallPath(): string {
  const installDir = path.join(app.getPath("userData"), "python");

  if (!fs.existsSync(installDir)) {
    try {
      fs.mkdirSync(installDir, { recursive: true });
    } catch (error) {
      log.error(error);
    }
  }
  return installDir;
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

export function getBundledPythonPath() {
  return getPythonPath(getBundledPythonInstallPath());
}

export function isBundledPythonInstalled() {
  return fs.existsSync(getBundledPythonPath());
}

////////////////////////////////////////////////
//
// Fixes code-signing issues in macOS by applying ad-hoc signatures to extracted environment files.
//
// Unpacking a Conda environment on macOS may break the signatures of binaries, causing macOS
// Gatekeeper to block them. This script assigns an ad-hoc signature (`-s -`), making the binaries
// executable while bypassing macOS's strict validation without requiring trusted certificates.
//
// It reads an architecture-specific file (`sign-osx-arm64.txt` or `sign-osx-64.txt`), which lists
// files requiring re-signing, and generates a `codesign` command to fix them all within the `envPath`.
//
////////////////////////////////////////////////

export function createAdHocSignCommand(envPath: string): string {
  const appPath = getAppPath();

  const signListFile = path.join(
    appPath,
    "resources",
    `sign-osx-${process.arch === "arm64" ? "arm64" : "64"}.txt`
  );
  const fileContents = fs.readFileSync(signListFile, "utf-8");
  const signList: string[] = [];

  fileContents.split(/\r?\n/).forEach((line) => {
    if (line) {
      signList.push(`"${line}"`);
    }
  });

  // sign all binaries with ad-hoc signature
  return `cd ${envPath} && codesign -s - -o 0x2 -f ${signList.join(
    " "
  )} && cd -`;
}

export async function installBundledPython(installPath?: string) {
  const platform = process.platform;
  const isWin = platform === "win32";
  installPath = installPath || getBundledPythonInstallPath();

  const pythonTarPath = getBundledPythonTarPath();
  if (!fs.existsSync(pythonTarPath)) {
    log.error("Python tarball not found");
    return;
  }

  try {
    fs.mkdirSync(installPath, { recursive: true });
    await tar.x({
      cwd: installPath,
      file: pythonTarPath,
    });
  } catch (error) {
    log.error(error);
  }

  let unpackCommand = isWin
    ? `${installPath}\\Scripts\\activate.bat && conda-unpack`
    : `source "${installPath}/bin/activate" && conda-unpack`;

  // only unsign when installing from bundled installer
  if (platform === "darwin") {
    unpackCommand = `${createAdHocSignCommand(installPath)}\n${unpackCommand}`;
  }

  const commandProcess = exec(unpackCommand, {
    shell: isWin ? "cmd.exe" : "/bin/bash",
  });
}
