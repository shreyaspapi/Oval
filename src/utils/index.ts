import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import {
  exec,
  execFile,
  ExecFileOptions,
  execFileSync,
  execSync,
  spawn,
  ChildProcess,
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

export function getBundledPythonInstallationPath(): string {
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
  return getPythonPath(getBundledPythonInstallationPath());
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

export async function installOpenWebUI(installationPath: string) {
  console.log(installationPath);
  let unpackCommand =
    process.platform === "win32"
      ? `${installationPath}\\Scripts\\activate.bat && pip install open-webui -U`
      : `source "${installationPath}/bin/activate" && pip install open-webui -U`;

  // only unsign when installing from bundled installer
  // if (platform === "darwin") {
  //   unpackCommand = `${createAdHocSignCommand(installationPath)}\n${unpackCommand}`;
  // }

  console.log(unpackCommand);

  const commandProcess = exec(unpackCommand, {
    shell: process.platform === "win32" ? "cmd.exe" : "/bin/bash",
  });

  // once the environment is activated, print the python version
  commandProcess.stdout?.on("data", (data) => {
    console.log(data);
  });

  commandProcess.stderr?.on("data", (data) => {
    console.error(data);
  });

  commandProcess.on("exit", (code) => {
    console.log(`Child exited with code ${code}`);
  });
}

export async function installBundledPython(installationPath?: string) {
  installationPath = installationPath || getBundledPythonInstallationPath();

  const pythonTarPath = getBundledPythonTarPath();

  console.log(installationPath, pythonTarPath);
  if (!fs.existsSync(pythonTarPath)) {
    log.error("Python tarball not found");
    return;
  }

  try {
    fs.mkdirSync(installationPath, { recursive: true });
    await tar.x({
      cwd: installationPath,
      file: pythonTarPath,
    });
  } catch (error) {
    log.error(error);
  }

  // Get the path to the installed Python binary
  const bundledPythonPath = getBundledPythonPath();

  if (!fs.existsSync(bundledPythonPath)) {
    log.error("Python binary not found in install path");
    return;
  }

  try {
    // Execute the Python binary to print the version
    const pythonVersion = execFileSync(bundledPythonPath, ["--version"], {
      encoding: "utf-8",
    });
    console.log("Installed Python Version:", pythonVersion.trim());
  } catch (error) {
    log.error("Failed to execute Python binary", error);
  }
}

export async function installPackage(installationPath?: string) {
  installationPath = installationPath || getBundledPythonInstallationPath();

  if (!isBundledPythonInstalled()) {
    try {
      await installBundledPython(installationPath);
    } catch (error) {
      log.error("Failed to install bundled Python", error);
      return Promise.reject("Failed to install bundled Python");
    }
  }

  try {
    await installOpenWebUI(installationPath);
  } catch (error) {
    log.error("Failed to install open-webui", error);
    return Promise.reject("Failed to install open-webui");
  }
}

/**
 * Validates that Python is installed and the `open-webui` package is present
 * within the specified virtual environment.
 *
 * @param installationPath - The path to the virtual environment installation
 * @returns Promise<void> - Resolves if all prerequisites are valid; rejects otherwise
 */
export async function validateInstallation(
  installationPath: string
): Promise<void> {
  const pythonPath = getPythonPath(installationPath);

  // Check if Python binary exists
  if (!fs.existsSync(pythonPath)) {
    return Promise.reject(
      `Python binary not found in environment: ${pythonPath}`
    );
  }

  try {
    // Check if `open-webui` is installed
    const checkCommand =
      process.platform === "win32"
        ? `${installationPath}\\Scripts\\activate.bat && pip show open-webui`
        : `source "${installationPath}/bin/activate" && pip show open-webui`;

    execSync(checkCommand, { stdio: "ignore", shell: true });
  } catch (error) {
    return Promise.reject(
      `The 'open-webui' package is not installed in the virtual environment at ${installationPath}. Install it first.`
    );
  }

  // All validation passed
  return Promise.resolve();
}

// Map to track running processes by installation path
const activeProcesses: Map<string, ChildProcess> = new Map();

/**
 * Starts the Open-WebUI server.
 *
 * @param installationPath - The path to the virtual environment installation
 * @param port - The port on which the server will run
 */
export async function startOpenWebUIServer(
  installationPath: string,
  port: number
): Promise<void> {
  try {
    await validateInstallation(installationPath);
  } catch (validationError) {
    console.error(validationError);
    return Promise.reject(validationError); // Abort if validation fails
  }

  // Construct the command based on the platform
  let startCommand =
    process.platform === "win32"
      ? `${installationPath}\\Scripts\\activate.bat && open-webui serve`
      : `source "${installationPath}/bin/activate" && open-webui serve`;

  if (port) {
    startCommand += ` --port ${port}`;
  }

  // Spawn the process
  console.log("Starting Open-WebUI server...");
  const childProcess = spawn(startCommand, [], { shell: true });

  // Log process output
  childProcess.stdout?.on("data", (data) => {
    console.log(`[Open-WebUI]: ${data.toString().trim()}`);
  });

  childProcess.stderr?.on("data", (data) => {
    console.error(`[Open-WebUI Error]: ${data.toString().trim()}`);
  });

  childProcess.on("exit", (exitCode) => {
    console.log(`Open-WebUI server exited with code ${exitCode}`);
  });

  // Keep track of the process for later termination
  activeProcesses.set(installationPath, childProcess);
}

/**
 * Stops the running Open-WebUI server.
 *
 * @param installationPath - The path to the virtual environment installation
 */
export async function stopOpenWebUIServer(
  installationPath: string
): Promise<void> {
  const processToStop = activeProcesses.get(installationPath);

  if (!processToStop) {
    console.error(
      "No active server found for the specified installation path."
    );
    return;
  }

  console.log("Stopping Open-WebUI server...");

  // Terminate the process
  processToStop.kill();

  // Remove from the active processes map
  activeProcesses.delete(installationPath);

  console.log("Open-WebUI server stopped successfully.");
}
