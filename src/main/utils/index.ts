// @ts-nocheck

import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import net from "net";
import crypto from "crypto";

import * as tar from "tar";

import { app, shell, Notification } from "electron";
import { execFileSync, exec, spawn, execSync, execFile } from "child_process";

import log from "electron-log";
log.transports.file.resolvePathFn = () => getLogFilePath("main");

const serverLogger = log.create({ logId: "server" });
serverLogger.transports.file.resolvePath = () => getLogFilePath(`server`);

export const getLogFilePath = (name: string = "main"): string => {
    const logDir = path.join(getUserDataPath(), "logs");
    if (!fs.existsSync(logDir)) {
        fs.mkdirSync(logDir, { recursive: true });
    }
    return path.join(logDir, `${name}.log`);
};

export const getAppPath = (): string => {
    let appPath = app.getAppPath();
    if (app.isPackaged) {
        appPath = path.dirname(appPath);
    }

    return path.normalize(appPath);
};

export const getUserHomePath = (): string => {
    return path.normalize(app.getPath("home"));
};

export const getUserDataPath = (): string => {
    const userDataDir = app.getPath("userData");

    if (!fs.existsSync(userDataDir)) {
        try {
            fs.mkdirSync(userDataDir, { recursive: true });
        } catch (error) {
            log.error(error);
        }
    }

    return path.normalize(userDataDir);
};

export const getOpenWebUIDataPath = (): string => {
    const openWebUIDataDir = path.join(getUserDataPath(), "data");

    if (!fs.existsSync(openWebUIDataDir)) {
        try {
            fs.mkdirSync(openWebUIDataDir, { recursive: true });
        } catch (error) {
            log.error(error);
        }
    }

    return path.normalize(openWebUIDataDir);
};

export const openUrl = (url: string) => {
    if (!url) {
        throw new Error("No URL provided to open in browser.");
    }

    log.info("Opening URL in browser:", url);
    if (url.startsWith("http://0.0.0.0")) {
        url = url.replace("http://0.0.0.0", "http://localhost");
    }

    shell.openExternal(url);
};

export const getSystemInfo = () => {
    const currentPlatform = os.platform();
    const currentArch = os.arch();

    return {
        platform: currentPlatform,
        architecture: currentArch,
    };
};

export const getSecretKey = (keyPath?: string, key?: string): string => {
    keyPath = keyPath || path.join(getOpenWebUIDataPath(), ".key");

    if (fs.existsSync(keyPath)) {
        return fs.readFileSync(keyPath, "utf-8");
    }

    key = key || crypto.randomBytes(64).toString("hex");
    fs.writeFileSync(keyPath, key);
    return key;
};

export const portInUse = async (
    port: number,
    host: string = "0.0.0.0"
): Promise<boolean> => {
    return new Promise((resolve) => {
        const client = new net.Socket();

        // Attempt to connect to the port
        client
            .setTimeout(1000) // Timeout for the connection attempt
            .once("connect", () => {
                // If connection succeeds, port is in use
                client.destroy();
                resolve(true);
            })
            .once("timeout", () => {
                // If no connection after the timeout, port is not in use
                client.destroy();
                resolve(false);
            })
            .once("error", (err: any) => {
                if (err.code === "ECONNREFUSED") {
                    // Port is not in use or no listener is accepting connections
                    resolve(false);
                } else {
                    // Unexpected error
                    resolve(false);
                }
            })
            .connect(port, host);
    });
};

/**
 * Maps Node.js platform names to Python build platform names
 */
const getPlatformString = () => {
    const platformMap = {
        darwin: "apple-darwin",
        win32: "pc-windows-msvc",
        linux: "unknown-linux-gnu",
    };

    const currentPlatform = os.platform();
    return platformMap[currentPlatform] || "unknown-linux-gnu";
};

/**
 * Maps Node.js architecture names to Python build architecture names
 */
const getArchString = () => {
    const archMap = {
        x64: "x86_64",
        arm64: "aarch64",
        ia32: "i686",
    };

    const currentArch = os.arch();
    return archMap[currentArch] || "x86_64";
};

/**
 * Generates the download URL based on system architecture and platform
 */
const generateDownloadUrl = () => {
    // const baseUrl =
    //     "https://desktop.openwebui.com/astral-sh/python-build-standalone/releases/download";
    const baseUrl =
        "https://github.com/astral-sh/python-build-standalone/releases/download";

    const releaseDate = "20250723";
    const pythonVersion = "3.11.13";

    const archString = getArchString();
    const platformString = getPlatformString();

    const filename = `cpython-${pythonVersion}+${releaseDate}-${archString}-${platformString}-install_only.tar.gz`;

    return `${baseUrl}/${releaseDate}/${filename}`;
};

export const downloadFileWithProgress = async (
    url,
    downloadPath,
    onProgress
) => {
    try {
        const response = await fetch(url);

        if (response) {
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const totalSize = parseInt(
                response.headers.get("content-length"),
                10
            );
            let downloadedSize = 0;

            const reader = response.body.getReader();
            const chunks = [];

            while (true) {
                const { done, value } = await reader.read();

                if (done) break;

                chunks.push(value);
                downloadedSize += value.length;

                // Report progress
                if (onProgress && totalSize) {
                    const progress = (downloadedSize / totalSize) * 100;
                    onProgress(progress, downloadedSize, totalSize);
                }
            }

            // Combine all chunks
            const buffer = Buffer.concat(
                chunks.map((chunk) => Buffer.from(chunk))
            );

            // Write to file
            fs.writeFileSync(downloadPath, buffer);

            log.info("File downloaded successfully:", downloadPath);
            return downloadPath;
        }
    } catch (error) {
        log.error("Download failed:", error);
        throw error;
    }
};

////////////////////////////////////////////////
//
// Python Utils
//
////////////////////////////////////////////////

export const getPythonDownloadPath = (): string => {
    const downloadDir = getUserDataPath();
    const downloadPath = path.join(downloadDir, "py.tar.gz");

    return downloadPath;
};

export const getPythonInstallationDir = (): string => {
    const installDir = path.join(app.getPath("userData"), "python");

    if (!fs.existsSync(installDir)) {
        try {
            fs.mkdirSync(installDir, { recursive: true });
        } catch (error) {
            log.error(error);
        }
    }
    return path.normalize(installDir);
};

/**
 * Downloads Python to AppData with progress tracking
 */
const downloadPython = async (onProgress = null) => {
    const url = generateDownloadUrl();
    const downloadPath = getPythonDownloadPath();

    log.info(`🔍 Detected system: ${os.platform()} ${os.arch()}`);
    log.info(`📁 Download path: ${downloadPath}`);
    log.info(`🔗 URL: ${url}`);

    // Check if file already exists
    if (fs.existsSync(downloadPath)) {
        log.info(`✅ File already exists: ${downloadPath}`);
        return downloadPath;
    }

    try {
        const result = await downloadFileWithProgress(
            url,
            downloadPath,
            onProgress
        );
        log.info(`✅ Python downloaded successfully to: ${result}`);
        return result;
    } catch (error) {
        log.error(`❌ Download failed: ${error?.message}`);
        throw error;
    }
};

const isPythonDownloaded = () => {
    const downloadPath = getPythonDownloadPath();

    return fs.existsSync(downloadPath);
};

const checkInternet = async () => {
    try {
        const response = await fetch("https://api.openwebui.com", {
            method: "GET",
        });
        return true;
    } catch (error) {
        return false;
    }
};

export const installPython = async (
    installationDir?: string
): Promise<boolean> => {
    let pythonDownloadPath = getPythonDownloadPath();
    if (!isPythonDownloaded()) {
        // check if connection is available
        if (!(await checkInternet())) {
            throw new Error(
                "An active internet connection is required to start the installation. Please connect to the internet and try again."
            );
        }

        await downloadPython((progress, downloaded, total) => {
            log.info(
                `Downloading Python: ${progress.toFixed(2)}% (${downloaded} of ${total} bytes)`
            );
        });
    }
    if (!fs.existsSync(pythonDownloadPath)) {
        log.error("Python download not found");
        return false;
    }

    installationDir = installationDir || getPythonInstallationDir();
    log.info(installationDir, pythonDownloadPath);

    try {
        const userDataPath = getUserDataPath();
        await tar.x({
            cwd: userDataPath,
            file: pythonDownloadPath,
        });
    } catch (error) {
        log.error(error);
        return false; // Return false to indicate failure
    }

    // Get the path to the installed Python binary
    if (isPythonInstalled(installationDir)) {
        const pythonPath = getPythonPath(installationDir);

        execFileSync(pythonPath, ["-m", "pip", "install", "uv"], {
            encoding: "utf-8",
            env: {
                ...process.env,
                ...(process.platform === "win32"
                    ? { PYTHONIOENCODING: "utf-8" }
                    : {}),
            },
        });
        log.info("Successfully installed uv package");

        return true; // Return true to indicate success
    } else {
        log.error(
            "Python installation failed or not found in the specified path"
        );
        return false; // Return false to indicate failure
    }
};

export const getPythonExecutablePath = (envPath: string) => {
    if (process.platform === "win32") {
        return path.normalize(path.join(envPath, "python.exe"));
    } else {
        return path.normalize(path.join(envPath, "bin", "python"));
    }
};

export const getPythonPath = (installationDir?: string) => {
    return path.normalize(
        getPythonExecutablePath(installationDir || getPythonInstallationDir())
    );
};

export const isPythonInstalled = (installationDir?: string) => {
    const pythonPath = getPythonPath(installationDir);

    if (!fs.existsSync(pythonPath)) {
        log.error("Python binary not found in install path");
        return false; // Return false to indicate failure
    }

    try {
        // Execute the Python binary to print the version
        const pythonVersion = execFileSync(pythonPath, ["--version"], {
            encoding: "utf-8",
            env: {
                ...process.env,
                ...(process.platform === "win32"
                    ? { PYTHONIOENCODING: "utf-8" }
                    : {}),
            },
        });
        log.info("Installed Python Version:", pythonVersion.trim());

        return true; // Return true to indicate success
    } catch (error) {
        log.error("Failed to execute Python binary", error);
        return false; // Return false to indicate failure
    }
};

export const isUvInstalled = (installationDir?: string) => {
    const pythonPath = getPythonPath(installationDir);
    try {
        // Check if uv is installed by running the command
        const result = execFileSync(pythonPath, ["-m", "uv", "--version"], {
            encoding: "utf-8",
            env: {
                ...process.env,
                ...(process.platform === "win32"
                    ? { PYTHONIOENCODING: "utf-8" }
                    : {}),
            },
        });

        log.info("Installed uv Version:", result.trim());
        return true; // Return true if uv is installed
    } catch (error) {
        log.error(
            "uv is not installed or not found in the specified path",
            error
        );
        return false; // Return false to indicate failure
    }
};

export const uninstallPython = (installationDir?: string): boolean => {
    installationDir = installationDir || getPythonInstallationDir();

    if (!fs.existsSync(installationDir)) {
        log.error("Python installation not found");
        return false;
    }

    try {
        fs.rmSync(installationDir, { recursive: true, force: true });
        log.info("Python installation removed successfully:", installationDir);
    } catch (error) {
        log.error("Failed to remove Python installation", error);
        return false;
    }

    try {
        const pythonDownloadPath = getPythonDownloadPath();
        fs.rmSync(pythonDownloadPath, { recursive: true });
    } catch (error) {
        log.error("Failed to remove Python download", error);
        return false;
    }

    return true;
};

export const resetApp = async (): Promise<void> => {
    await uninstallPython();
    log.info("Uninstalled Python environment");

    // remove config file
    const configPath = path.join(getUserDataPath(), "config.json");
    if (fs.existsSync(configPath)) {
        try {
            fs.unlinkSync(configPath);
            log.info("Removed config file:", configPath);
        } catch (error) {
            log.error("Failed to remove config file:", error);
        }
    }

    // remove secret key file
    const secretKeyPath = path.join(getOpenWebUIDataPath(), ".key");
    if (fs.existsSync(secretKeyPath)) {
        try {
            fs.unlinkSync(secretKeyPath);
            log.info("Removed secret key file:", secretKeyPath);
        } catch (error) {
            log.error("Failed to remove secret key file:", error);
        }
    }

    // remove /data folder
    const dataPath = getOpenWebUIDataPath();
    if (fs.existsSync(dataPath)) {
        try {
            fs.rmSync(dataPath, { recursive: true, force: true });
            log.info("Removed data directory:", dataPath);
        } catch (error) {
            log.error("Failed to remove data directory:", error);
        }
    }
};

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

export const createAdHocSignCommand = (envPath: string): string => {
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
    return `cd ${envPath} && codesign -s - -o 0x2 -f ${signList.join(" ")} && cd -`;
};

export const installPackage = (
    packageName: string,
    version?: string
): Promise<boolean> => {
    // Wrap the logic in a Promise to properly handle async execution and return a boolean
    return new Promise((resolve, reject) => {
        if (!isPythonInstalled()) {
            log.error(
                "Python is not installed or not found in the specified path"
            );
            return reject(false); // Return false to indicate failure
        }
        // Build the appropriate unpack command based on the platform
        let pythonPath = getPythonPath();

        // only unsign when installing from bundled installer
        // if (platform === "darwin") {
        //     unpackCommand = `${createAdHocSignCommand()}\n${unpackCommand}`;
        // }
        const commandProcess = execFile(
            pythonPath,
            [
                "-m",
                "uv",
                "pip",
                "install",
                ...(version
                    ? [`${packageName}==${version}`]
                    : [packageName, "-U"]),
            ],
            {
                env: {
                    ...process.env,
                    ...(process.platform === "win32"
                        ? { PYTHONIOENCODING: "utf-8" }
                        : {}),
                },
            }
        );

        // Function to handle logging output
        const onLog = (data: any) => {
            log.info(data);
        };

        // Listen to stdout and stderr for logging
        commandProcess.stdout?.on("data", onLog);
        commandProcess.stderr?.on("data", onLog);

        // Handle the exit event
        commandProcess.on("exit", (code) => {
            log.info(`Child exited with code ${code}`);

            if (code !== 0) {
                log.error(`Failed to install open-webui: ${code}`);
                resolve(false); // Resolve the Promise with `false` if the command fails
            } else {
                resolve(true); // Resolve the Promise with `true` if the command succeeds
            }
        });

        // Handle errors during execution
        commandProcess.on("error", (error) => {
            log.error(
                `Error occurred while installing open-webui: ${error.message}`
            );
            reject(error); // Reject the Promise if an unexpected error occurs
        });
    });
};

export const isPackageInstalled = (packageName: string): boolean => {
    const pythonPath = getPythonPath();
    if (!fs.existsSync(pythonPath)) {
        return false;
    }

    try {
        // Execute the Python binary to print the version
        const info = execFileSync(
            pythonPath,
            ["-m", "uv", "pip", "show", packageName],
            {
                encoding: "utf-8",
                env: {
                    ...process.env,
                    ...(process.platform === "win32"
                        ? { PYTHONIOENCODING: "utf-8" }
                        : {}),
                },
            }
        );

        if (info.includes(`Name: ${packageName}`)) {
            log.info(`Package ${packageName} is installed.`);
            return true; // Return true to indicate success
        } else {
            log.info(`Package ${packageName} is not installed.`);
            return false; // Return false to indicate failure
        }
    } catch (error) {
        log.info("Failed to execute Python binary");
        return false; // Return false to indicate failure
    }
};

// Tracks all spawned server process PIDs
// Tracks all spawned server process PIDs and their logs
const serverPIDs: Set<number> = new Set();
const serverLogs: Map<number, string[]> = new Map(); // Map PID to log lines

export const getServerPIDs = (): number[] => {
    return Array.from(serverPIDs);
};

/**
 * Spawn the Open-WebUI server process.
 */
export const startServer = async (
    expose = false,
    port = null
): Promise<{ url: string; pid: number }> => {
    await stopAllServers(); // Stop any existing servers before starting a new one
    const host = expose ? "0.0.0.0" : "127.0.0.1";
    if (!isPythonInstalled()) throw new Error("Python is not installed");
    if (!isPackageInstalled("open-webui"))
        throw new Error("open-webui package is not installed");

    const pythonPath = getPythonPath();
    log.info(`Using Python at: ${pythonPath}`);

    let commandArgs: string[];
    commandArgs = ["-m", "uv", "run", "open-webui", "serve", "--host", host];

    const dataDir = getOpenWebUIDataPath();
    const secretKey = getSecretKey();
    if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
    }

    process.env.DATA_DIR = dataDir;
    process.env.WEBUI_SECRET_KEY = secretKey;

    // Find available port
    let desiredPort = port || 8080;
    let availablePort = desiredPort;

    log.info(`Checking port availability starting from ${availablePort}...`);
    while (await portInUse(availablePort, host)) {
        availablePort++;

        log.info(`Port ${availablePort} is in use, trying next port...`);
        if (availablePort > desiredPort + 100) {
            throw new Error("No available ports found");
        }
    }
    commandArgs.push("--port", availablePort.toString());
    log.info(
        "Starting Open-WebUI server...",
        pythonPath,
        commandArgs.join(" ")
    );
    const childProcess = spawn(pythonPath, commandArgs, {
        detached: process.platform !== "win32",
        stdio: ["ignore", "pipe", "pipe"],
        env: {
            ...process.env,
            ...(process.platform === "win32"
                ? { PYTHONIOENCODING: "utf-8" }
                : {}),
        },
    });

    if (!childProcess.pid) {
        throw new Error("Failed to start server: No PID available");
    }
    // Setup real-time log accumulation
    const logLines: string[] = [];
    serverPIDs.add(childProcess.pid);
    serverLogs.set(childProcess.pid, logLines);

    const appendLog = (source: string) => (data: Buffer) => {
        const logLine = data.toString().trim();
        const line = `[${source}][PID:${childProcess.pid}]: ${logLine}`;
        logLines.push(line);
        serverLogger.info(line); // Log to console
    };
    childProcess.stdout?.on("data", appendLog("stdout"));
    childProcess.stderr?.on("data", appendLog("stderr"));
    childProcess.on("close", (code, signal) => {
        const line = `[process][PID:${childProcess.pid}] Exited with code ${code} signal ${signal}`;
        serverLogger.info(line);
        logLines.push(line);
        serverPIDs.delete(childProcess.pid);
        // Note: we keep the logs available until manually cleared
    });
    childProcess.on("error", (err) => {
        const line = `[process][PID:${childProcess.pid}] Error: ${err.message}`;
        serverLogger.error(line);
        logLines.push(line);
    });

    // Compute URL directly, do not try to parse logs
    let effectiveHost = host;
    if (!expose && host === "0.0.0.0") effectiveHost = "127.0.0.1";
    const url = `http://${effectiveHost}:${availablePort}`;
    log.info(`Server started with PID: ${childProcess.pid}, URL: ${url}`);

    return { url, pid: childProcess.pid };
};

/**
 * Terminates all server processes with maximum reliability.
 */
export async function stopAllServers(): Promise<void> {
    log.info("Stopping all servers...");

    const pidsToStop = Array.from(serverPIDs);
    if (pidsToStop.length === 0) {
        log.info("No servers to stop.");
        return;
    }

    // First pass: attempt graceful termination
    for (const pid of pidsToStop) {
        await terminateProcessTree(pid, false);
    }

    // Wait a moment for graceful shutdown
    await sleep(2000);

    // Second pass: force kill any remaining processes
    for (const pid of pidsToStop) {
        await terminateProcessTree(pid, true);
    }

    // Final verification and cleanup
    for (const pid of pidsToStop) {
        if (!isProcessRunning(pid)) {
            serverPIDs.delete(pid);
            serverLogs.delete(pid);
        } else {
            log.warn(
                `Process ${pid} may still be running after termination attempts`
            );
        }
    }

    log.info(
        `Stopped ${pidsToStop.length - serverPIDs.size}/${pidsToStop.length} servers successfully.`
    );
}

/**
 * Kills a process tree by PID with retry logic.
 */
async function terminateProcessTree(
    pid: number,
    forceKill: boolean = false
): Promise<void> {
    const maxRetries = 3;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            if (process.platform === "win32") {
                await terminateWindows(pid, forceKill);
            } else {
                await terminateUnix(pid, forceKill);
            }

            // Verify termination
            if (!isProcessRunning(pid)) {
                log.info(`Successfully terminated process tree (PID: ${pid})`);
                return;
            }
        } catch (error) {
            log.warn(
                `Attempt ${attempt}/${maxRetries} failed for PID ${pid}:`,
                error
            );
        }

        if (attempt < maxRetries) {
            await sleep(1000); // Wait before retry
        }
    }

    log.error(
        `Failed to terminate process tree (PID: ${pid}) after ${maxRetries} attempts`
    );
}

/**
 * Terminate process on Windows.
 */
async function terminateWindows(
    pid: number,
    forceKill: boolean
): Promise<void> {
    const commands = forceKill
        ? [`taskkill /PID ${pid} /T /F`]
        : [`taskkill /PID ${pid} /T`, `taskkill /PID ${pid} /T /F`];

    for (const cmd of commands) {
        try {
            execSync(cmd, { timeout: 5000, stdio: "ignore" });
            await sleep(500); // Brief pause between commands
        } catch (error) {
            log.error(`Failed to terminate process (PID: ${pid}):`, error);
        }
    }
}

/**
 * Terminate process on Unix-like systems.
 */
async function terminateUnix(pid: number, forceKill: boolean): Promise<void> {
    const signals = forceKill ? ["SIGKILL"] : ["SIGTERM", "SIGKILL"];

    for (const signal of signals) {
        try {
            // Kill process group (negative PID)
            process.kill(-pid, signal);
            await sleep(500);

            // Also try individual process if group kill fails
            if (isProcessRunning(pid)) {
                process.kill(pid, signal);
                await sleep(500);
            }
        } catch (error) {
            log.error(`Failed to terminate process (PID: ${pid}):`, error);
        }
    }
}

/**
 * Check if a process is still running.
 */
function isProcessRunning(pid: number): boolean {
    try {
        // Sending signal 0 checks if process exists without killing it
        process.kill(pid, 0);
        return true;
    } catch (error) {
        return false;
    }
}

/**
 * Simple sleep utility.
 */
function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Returns the live log for a running or stopped server process.
 */
export function getServerLog(pid: number): string[] {
    return serverLogs.get(pid) || [];
}

// Helper function to check URL availability and auto-open
export const checkUrlAndOpen = async (
    url: string,
    callback: Function = async () => {}
) => {
    const maxAttempts = 1800; // 60 minutes with 2-second intervals
    const interval = 2000; // 2 seconds
    let attempts = 0;

    const checkUrl = async (): Promise<boolean> => {
        try {
            const response = await fetch(url, {
                method: "HEAD",
                timeout: 5000, // 5 second timeout per request
            });
            return response.ok;
        } catch (error) {
            return false;
        }
    };

    const pollUrl = async () => {
        while (attempts < maxAttempts) {
            attempts++;
            log.info(
                `Checking URL availability (attempt ${attempts}/${maxAttempts}): ${url}`
            );

            try {
                const isAvailable = await checkUrl();
                if (isAvailable) {
                    log.info("URL is now available, opening browser...");
                    await openUrl(url);
                    await callback(); // Call the provided callback function
                    return; // Exit the polling loop
                }
            } catch (error) {
                log.info(`Error checking URL: ${error}`);
            }

            // Wait before next attempt
            await new Promise((resolve) => setTimeout(resolve, interval));
        }

        // If we exit the loop without success
        if (attempts >= maxAttempts) {
            log.info("URL check timed out after 5 minutes");
        }
    };

    // Start polling in the background (don't await)
    pollUrl().catch((error) => {
        log.error("Error in URL polling:", error);
    });
};

export const getConfig = async (): Promise<Record<string, any>> => {
    const configPath = path.join(getUserDataPath(), "config.json");
    try {
        if (fs.existsSync(configPath)) {
            const data = await fs.promises.readFile(configPath, "utf8");
            return JSON.parse(data);
        }
        return {};
    } catch (error) {
        log.error("Error reading config:", error);
        throw error;
    }
};

export const setConfig = async (config: Record<string, any>): Promise<void> => {
    const configPath = path.join(getUserDataPath(), "config.json");
    try {
        await fs.promises.writeFile(
            configPath,
            JSON.stringify(config, null, 2)
        );
    } catch (error) {
        log.error("Error writing config:", error);
        throw error;
    }
};
