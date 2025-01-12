import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
	exec,
	execFile,
	ExecFileOptions,
	execFileSync,
	execSync,
	spawn,
	ChildProcess
} from 'child_process';
import net from 'net';

import * as tar from 'tar';
import log from 'electron-log';

import { app } from 'electron';

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
	return app.getPath('home');
}

export function getUserDataPath(): string {
	const userDataDir = app.getPath('userData');

	if (!fs.existsSync(userDataDir)) {
		try {
			fs.mkdirSync(userDataDir, { recursive: true });
		} catch (error) {
			log.error(error);
		}
	}

	return userDataDir;
}

export function getOpenWebUIDataPath(): string {
	const openWebUIDataDir = path.join(getUserDataPath(), 'data');

	if (!fs.existsSync(openWebUIDataDir)) {
		try {
			fs.mkdirSync(openWebUIDataDir, { recursive: true });
		} catch (error) {
			log.error(error);
		}
	}

	return openWebUIDataDir;
}

export async function portInUse(port: number, host: string = '127.0.0.1'): Promise<boolean> {
	return new Promise((resolve) => {
		const client = new net.Socket();

		// Attempt to connect to the port
		client
			.setTimeout(1000) // Timeout for the connection attempt
			.once('connect', () => {
				// If connection succeeds, port is in use
				client.destroy();
				resolve(true);
			})
			.once('timeout', () => {
				// If no connection after the timeout, port is not in use
				client.destroy();
				resolve(false);
			})
			.once('error', (err: any) => {
				if (err.code === 'ECONNREFUSED') {
					// Port is not in use or no listener is accepting connections
					resolve(false);
				} else {
					// Unexpected error
					resolve(false);
				}
			})
			.connect(port, host);
	});
}

////////////////////////////////////////////////
//
// Python Utils
//
////////////////////////////////////////////////

export function getBundledPythonTarPath(): string {
	const appPath = getAppPath();
	return path.join(appPath, 'resources', 'python.tar.gz');
}

export function getBundledPythonInstallationPath(): string {
	const installDir = path.join(app.getPath('userData'), 'python');

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
	return fs.existsSync(path.join(envPath, 'conda-meta'));
}

export function getPythonPath(envPath: string, isConda?: boolean) {
	if (process.platform === 'win32') {
		return (isConda ?? isCondaEnv(envPath))
			? path.join(envPath, 'python.exe')
			: path.join(envPath, 'Scripts', 'python.exe');
	} else {
		return path.join(envPath, 'bin', 'python');
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
		'resources',
		`sign-osx-${process.arch === 'arm64' ? 'arm64' : '64'}.txt`
	);
	const fileContents = fs.readFileSync(signListFile, 'utf-8');
	const signList: string[] = [];

	fileContents.split(/\r?\n/).forEach((line) => {
		if (line) {
			signList.push(`"${line}"`);
		}
	});

	// sign all binaries with ad-hoc signature
	return `cd ${envPath} && codesign -s - -o 0x2 -f ${signList.join(' ')} && cd -`;
}

export async function installOpenWebUI(installationPath: string) {
	console.log(installationPath);
	let unpackCommand =
		process.platform === 'win32'
			? `${installationPath}\\Scripts\\activate.bat && uv pip install open-webui -U`
			: `source "${installationPath}/bin/activate" && uv pip install open-webui -U`;

	// only unsign when installing from bundled installer
	// if (platform === "darwin") {
	//     unpackCommand = `${createAdHocSignCommand(installationPath)}\n${unpackCommand}`;
	// }

	console.log(unpackCommand);

	const commandProcess = exec(unpackCommand, {
		shell: process.platform === 'win32' ? 'cmd.exe' : '/bin/bash'
	});

	commandProcess.stdout?.on('data', (data) => {
		console.log(data);
	});

	commandProcess.stderr?.on('data', (data) => {
		console.error(data);
	});

	commandProcess.on('exit', (code) => {
		console.log(`Child exited with code ${code}`);
	});
}

export async function installBundledPython(installationPath?: string) {
	installationPath = installationPath || getBundledPythonInstallationPath();

	const pythonTarPath = getBundledPythonTarPath();

	console.log(installationPath, pythonTarPath);
	if (!fs.existsSync(pythonTarPath)) {
		log.error('Python tarball not found');
		return;
	}

	try {
		fs.mkdirSync(installationPath, { recursive: true });
		await tar.x({
			cwd: installationPath,
			file: pythonTarPath
		});
	} catch (error) {
		log.error(error);
	}

	// Get the path to the installed Python binary
	const bundledPythonPath = getBundledPythonPath();

	if (!fs.existsSync(bundledPythonPath)) {
		log.error('Python binary not found in install path');
		return;
	}

	try {
		// Execute the Python binary to print the version
		const pythonVersion = execFileSync(bundledPythonPath, ['--version'], {
			encoding: 'utf-8'
		});
		console.log('Installed Python Version:', pythonVersion.trim());
	} catch (error) {
		log.error('Failed to execute Python binary', error);
	}
}

export async function installPackage(installationPath?: string) {
	installationPath = installationPath || getBundledPythonInstallationPath();

	// if (!isBundledPythonInstalled()) {
	//     try {
	//         await installBundledPython(installationPath);
	//     } catch (error) {
	//         log.error("Failed to install bundled Python", error);
	//         return Promise.reject("Failed to install bundled Python");
	//     }
	// }

	try {
		await installBundledPython(installationPath);
	} catch (error) {
		log.error('Failed to install bundled Python', error);
		return Promise.reject('Failed to install bundled Python');
	}

	try {
		await installOpenWebUI(installationPath);
	} catch (error) {
		log.error('Failed to install open-webui', error);
		return Promise.reject('Failed to install open-webui');
	}
}

export async function removePackage(installationPath?: string) {
	await stopAllServers();
	installationPath = installationPath || getBundledPythonInstallationPath();

	// remove the python env entirely
	if (fs.existsSync(installationPath)) {
		fs.rmSync(installationPath, { recursive: true });
	}
}

////////////////////////////////////////////////
//
// Server Manager
//
////////////////////////////////////////////////

/**
 * Validates that Python is installed and the `open-webui` package is present
 * within the specified virtual environment.
 */
export async function validateInstallation(installationPath?: string): Promise<boolean> {
	installationPath = installationPath || getBundledPythonInstallationPath();
	const pythonPath = getPythonPath(installationPath);
	if (!fs.existsSync(pythonPath)) {
		return false;
	}

	try {
		const checkCommand =
			process.platform === 'win32'
				? `${installationPath}\\Scripts\\activate.bat && pip show open-webui`
				: `source "${installationPath}/bin/activate" && pip show open-webui`;
		execSync(checkCommand, { stdio: 'ignore' });
	} catch (error) {
		return false;
	}

	return true;
}

// Tracks all spawned server process PIDs
const serverPIDs: Set<number> = new Set();

/**
 * Spawn the Open-WebUI server process.
 */
export async function startServer(installationPath?: string, port?: number): Promise<string> {
	installationPath = path.normalize(installationPath || getBundledPythonInstallationPath());

	if (!(await validateInstallation(installationPath))) {
		console.error('Failed to validate installation');
		return;
	}

	let startCommand =
		process.platform === 'win32'
			? `${installationPath}\\Scripts\\activate.bat && set DATA_DIR="${path.join(
					app.getPath('userData'),
					'data'
				)}" && open-webui serve`
			: `source "${installationPath}/bin/activate" && export DATA_DIR="${path.join(
					app.getPath('userData'),
					'data'
				)}" && open-webui serve`;

	port = port || 8080;
	while (await portInUse(port)) {
		port++;
	}

	startCommand += ` --port ${port}`;

	console.log('Starting Open-WebUI server...');
	const childProcess = spawn(startCommand, {
		shell: true,
		detached: true,
		stdio: ['ignore', 'pipe', 'pipe'] // Let us capture logs via stdout/stderr
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
			childProcess.stdout?.on('data', handleLog);
			childProcess.stderr?.on('data', handleLog);

			childProcess.on('close', (code) => {
				serverCrashed = true;
				if (!detectedURL) {
					reject(
						new Error(`Process exited unexpectedly with code ${code}. No server URL detected.`)
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
		throw new Error('Failed to start server: No PID available');
	}

	// Wait until the server log confirms it's started
	try {
		await monitorServerLogs();
	} catch (error) {
		if (serverCrashed) {
			throw new Error('Server crashed unexpectedly.');
		}
		throw error;
	}

	if (!detectedURL) {
		throw new Error('Failed to detect server URL from logs.');
	}

	console.log(`Server is now running at ${detectedURL}`);
	return detectedURL; // Return the detected URL
}

/**
 * Terminates all server processes.
 */
export async function stopAllServers(): Promise<void> {
	console.log('Stopping all servers...');
	for (const pid of serverPIDs) {
		try {
			terminateProcessTree(pid);
			serverPIDs.delete(pid); // Remove from tracking set after termination
		} catch (error) {
			console.error(`Error stopping server with PID ${pid}:`, error);
		}
	}
	console.log('All servers stopped successfully.');
}

/**
 * Kills a process tree by PID.
 */
function terminateProcessTree(pid: number): void {
	if (process.platform === 'win32') {
		// Use `taskkill` on Windows to recursively kill the process and its children
		try {
			execSync(`taskkill /PID ${pid} /T /F`); // /T -> terminate child processes, /F -> force termination
			console.log(`Terminated server process tree (PID: ${pid}) on Windows.`);
		} catch (error) {
			log.error(`Failed to terminate process tree (PID: ${pid}):`, error);
		}
	} else {
		// Use `kill` on Unix-like platforms to terminate the process group (-pid)
		try {
			process.kill(-pid, 'SIGKILL'); // Negative PID (-pid) kills the process group
			console.log(`Terminated server process tree (PID: ${pid}) on Unix-like OS.`);
		} catch (error) {
			log.error(`Failed to terminate process tree (PID: ${pid}):`, error);
		}
	}
}
