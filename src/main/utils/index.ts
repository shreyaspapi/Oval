import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import net from "net";
import crypto from "crypto";

import * as tar from "tar";

import { app } from "electron";
import log from "electron-log";
import { execFileSync, exec, spawn, execSync } from "child_process";

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
    const baseUrl =
        "https://desktop.openwebui.com/astral-sh/python-build-standalone/releases/download";
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

            console.log("File downloaded successfully:", downloadPath);
            return downloadPath;
        }
    } catch (error) {
        console.error("Download failed:", error);
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

export const getPythonInstallationPath = (): string => {
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

    console.log(`🔍 Detected system: ${os.platform()} ${os.arch()}`);
    console.log(`📁 Download path: ${downloadPath}`);
    console.log(`🔗 URL: ${url}`);

    // Check if file already exists
    if (fs.existsSync(downloadPath)) {
        console.log(`✅ File already exists: ${downloadPath}`);
        return downloadPath;
    }

    try {
        const result = await downloadFileWithProgress(
            url,
            downloadPath,
            onProgress
        );
        console.log(`✅ Python downloaded successfully to: ${result}`);
        return result;
    } catch (error) {
        console.error(`❌ Download failed: ${error?.message}`);
        throw error;
    }
};

const isPythonDownloaded = () => {
    const downloadPath = getPythonDownloadPath();

    return fs.existsSync(downloadPath);
};

export const installPython = async (
    installationPath?: string
): Promise<boolean> => {
    installationPath = installationPath || getPythonInstallationPath();

    let pythonDownloadPath = getPythonDownloadPath();
    if (!isPythonDownloaded()) {
        await downloadPython((progress, downloaded, total) => {
            console.log(
                `Downloading Python: ${progress.toFixed(2)}% (${downloaded} of ${total} bytes)`
            );
            log.info(
                `Downloading Python: ${progress.toFixed(2)}% (${downloaded} of ${total} bytes)`
            );
        });
    }
    console.log(installationPath, pythonDownloadPath);

    if (!fs.existsSync(pythonDownloadPath)) {
        log.error("Python download not found");
        return false;
    }

    try {
        fs.mkdirSync(installationPath, { recursive: true });
        await tar.x({
            cwd: installationPath,
            file: pythonDownloadPath,
        });
    } catch (error) {
        log.error(error);
        return false; // Return false to indicate failure
    }

    // Get the path to the installed Python binary
    if (isPythonInstalled(installationPath)) {
        const pythonPath = getPythonPath(installationPath);
        // install uv using pip

        execFileSync(pythonPath, ["-m", "pip", "install", "uv"], {
            encoding: "utf-8",
        });
        console.log("Successfully installed uv package");

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
        return path.normalize(path.join(envPath, "Scripts", "python.exe"));
    } else {
        return path.normalize(path.join(envPath, "bin", "python"));
    }
};

export const getPythonPath = (installationPath?: string) => {
    return path.normalize(
        getPythonExecutablePath(installationPath || getPythonInstallationPath())
    );
};

export const isPythonInstalled = (installationPath?: string) => {
    const pythonPath = getPythonPath(installationPath);

    if (!fs.existsSync(pythonPath)) {
        log.error("Python binary not found in install path");
        return false; // Return false to indicate failure
    }

    try {
        // Execute the Python binary to print the version
        const pythonVersion = execFileSync(pythonPath, ["--version"], {
            encoding: "utf-8",
        });
        console.log("Installed Python Version:", pythonVersion.trim());

        return true; // Return true to indicate success
    } catch (error) {
        log.error("Failed to execute Python binary", error);
        return false; // Return false to indicate failure
    }
};

export const isUvInstalled = (installationPath?: string) => {
    const pythonPath = getPythonPath(installationPath);
    try {
        // Check if uv is installed by running the command
        const result = execFileSync(pythonPath, ["-m", "uv", "--version"], {
            encoding: "utf-8",
        });

        console.log("Installed uv Version:", result.trim());
        return true; // Return true if uv is installed
    } catch (error) {
        log.error(
            "uv is not installed or not found in the specified path",
            error
        );
        return false; // Return false to indicate failure
    }
};

export const uninstallPython = (installationPath?: string): boolean => {
    installationPath = installationPath || getPythonInstallationPath();

    if (!fs.existsSync(installationPath)) {
        log.error("Python installation not found");
        return false;
    }

    try {
        fs.rmSync(installationPath, { recursive: true });
    } catch (error) {
        log.error("Failed to remove Python installation", error);
        return false;
    }

    return true;
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
        let unpackCommand = `${pythonPath} -m uv pip install ${packageName}${
            version ? `==${version}` : " -U"
        }`;

        // only unsign when installing from bundled installer
        // if (platform === "darwin") {
        //     unpackCommand = `${createAdHocSignCommand()}\n${unpackCommand}`;
        // }

        const commandProcess = exec(unpackCommand, {
            shell: process.platform === "win32" ? "cmd.exe" : "/bin/bash",
        });

        // Function to handle logging output
        const onLog = (data: any) => {
            console.log(data);
        };

        // Listen to stdout and stderr for logging
        commandProcess.stdout?.on("data", onLog);
        commandProcess.stderr?.on("data", onLog);

        // Handle the exit event
        commandProcess.on("exit", (code) => {
            console.log(`Child exited with code ${code}`);

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
            }
        );

        if (info.includes(`Name: ${packageName}`)) {
            console.log(`Package ${packageName} is installed.`);
            return true; // Return true to indicate success
        } else {
            console.log(`Package ${packageName} is not installed.`);
            return false; // Return false to indicate failure
        }
    } catch (error) {
        log.error("Failed to execute Python binary", error);
        return false; // Return false to indicate failure
    }
};

// Tracks all spawned server process PIDs
const serverPIDs: Set<number> = new Set();

/**
 * Spawn the Open-WebUI server process.
 */
export async function startServer(
    expose = false,
    port = 8080
): Promise<string> {
    const host = expose ? "0.0.0.0" : "127.0.0.1";

    // Windows HATES Typer-CLI used to create the CLI for Open-WebUI
    // So we have to manually create the command to start the server
    let startCommand =
        process.platform === "win32"
            ? `uvicorn open_webui.main:app --host "${host}" --forwarded-allow-ips '*'`
            : `open-webui serve --host "${host}"`;

    if (process.platform === "win32") {
        process.env.FROM_INIT_PY = "true";
    }

    // Set environment variables in a platform-agnostic way
    process.env.DATA_DIR = path.join(app.getPath("userData"), "data");
    process.env.WEBUI_SECRET_KEY = getSecretKey();

    port = port || 8080;
    while (await portInUse(port)) {
        port++;
    }

    startCommand += ` --port ${port}`;
    console.log("Starting Open-WebUI server...", startCommand);

    const childProcess = spawn(startCommand, {
        shell: true,
        detached: process.platform !== "win32", // Detach the child process on Unix-like platforms
        stdio: ["ignore", "pipe", "pipe"], // Let us capture logs via stdout/stderr
    });

    let serverCrashed = false;
    let detectedURL: string | null = null;

    // Wait for log output to confirm the server has started
    async function monitorServerLogs(): Promise<void> {
        return new Promise<void>((resolve, reject) => {
            const handleLog = (data: Buffer) => {
                const logLine = data.toString().trim();
                console.log(`[Open-WebUI Log]: ${logLine}`);

                // Look for "Uvicorn running on http://<hostname>:<port>"
                const match = logLine.match(
                    /Uvicorn running on (http:\/\/[^\s]+) \(Press CTRL\+C to quit\)/
                );
                if (match) {
                    detectedURL = match[1]; // e.g., "http://0.0.0.0:8081"
                    resolve();
                }
            };

            // Combine stdout and stderr streams as a unified log source
            childProcess.stdout?.on("data", handleLog);
            childProcess.stderr?.on("data", handleLog);

            childProcess.on("close", (code) => {
                serverCrashed = true;
                if (!detectedURL) {
                    reject(
                        new Error(
                            `Process exited unexpectedly with code ${code}. No server URL detected.`
                        )
                    );
                }
            });
        });
    }

    // Track the child process PID
    if (childProcess.pid) {
        serverPIDs.add(childProcess.pid);
        console.log(`Server started with PID: ${childProcess.pid}`);
    } else {
        throw new Error("Failed to start server: No PID available");
    }

    // Wait until the server log confirms it's started
    try {
        await monitorServerLogs();
    } catch (error) {
        if (serverCrashed) {
            throw new Error("Server crashed unexpectedly.");
        }
        throw error;
    }

    if (!detectedURL) {
        throw new Error("Failed to detect server URL from logs.");
    }

    console.log(`Server is now running at ${detectedURL}`);
    return detectedURL; // Return the detected URL
}

/**
 * Terminates all server processes.
 */
export async function stopAllServers(): Promise<void> {
    console.log("Stopping all servers...");
    for (const pid of serverPIDs) {
        try {
            terminateProcessTree(pid);
            serverPIDs.delete(pid); // Remove from tracking set after termination
        } catch (error) {
            console.error(`Error stopping server with PID ${pid}:`, error);
        }
    }
    console.log("All servers stopped successfully.");
}

/**
 * Kills a process tree by PID.
 */
function terminateProcessTree(pid: number): void {
    if (process.platform === "win32") {
        // Use `taskkill` on Windows to recursively kill the process and its children
        try {
            execSync(`taskkill /PID ${pid} /T /F`); // /T -> terminate child processes, /F -> force termination
            console.log(
                `Terminated server process tree (PID: ${pid}) on Windows.`
            );
        } catch (error) {
            log.error(`Failed to terminate process tree (PID: ${pid}):`, error);
        }
    } else {
        // Use `kill` on Unix-like platforms to terminate the process group (-pid)
        try {
            process.kill(-pid, "SIGKILL"); // Negative PID (-pid) kills the process group
            console.log(
                `Terminated server process tree (PID: ${pid}) on Unix-like OS.`
            );
        } catch (error) {
            log.error(`Failed to terminate process tree (PID: ${pid}):`, error);
        }
    }
}
