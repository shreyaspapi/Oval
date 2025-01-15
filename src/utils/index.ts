import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import net from 'net';
import crypto from 'crypto';

import {
	exec,
	execFile,
	ExecFileOptions,
	execFileSync,
	execSync,
	spawn,
	ChildProcess
} from 'child_process';
import { EventEmitter } from 'events';

import * as tar from 'tar';
import log from 'electron-log';

import { app } from 'electron';

// Create and export a global event emitter specifically for logs
export const logEmitter = new EventEmitter();

////////////////////////////////////////////////
//
// General Utils
//
////////////////////////////////////////////////

export function getAppPath(): string {
	let appPath = app.getAppPath();
	if (app.isPackaged) {
		appPath = path.dirname(appPath);
	}

	return path.normalize(appPath);
}

export function getUserHomePath(): string {
	return path.normalize(app.getPath('home'));
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

	return path.normalize(userDataDir);
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

	return path.normalize(openWebUIDataDir);
}

export function getSecretKey(keyPath?: string, key?: string): string {
	keyPath = keyPath || path.join(getOpenWebUIDataPath(), '.key');

	if (fs.existsSync(keyPath)) {
		return fs.readFileSync(keyPath, 'utf-8');
	}

	key = key || crypto.randomBytes(64).toString('hex');
	fs.writeFileSync(keyPath, key);
	return key;
}

export async function portInUse(port: number, host: string = '0.0.0.0'): Promise<boolean> {
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
	return path.normalize(path.join(appPath, 'resources', 'python.tar.gz'));
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
	return path.normalize(installDir);
}

export function isCondaEnv(envPath: string): boolean {
	return fs.existsSync(path.join(envPath, 'conda-meta'));
}

export function getPythonPath(envPath: string, isConda?: boolean) {
	if (process.platform === 'win32') {
		return path.normalize(
			(isConda ?? isCondaEnv(envPath))
				? path.join(envPath, 'python.exe')
				: path.join(envPath, 'Scripts', 'python.exe')
		);
	} else {
		return path.normalize(path.join(envPath, 'bin', 'python'));
	}
}

export function getBundledPythonPath() {
	return path.normalize(getPythonPath(getBundledPythonInstallationPath()));
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

export async function installOpenWebUI(
	installationPath: string,
	version?: string
): Promise<boolean> {
	console.log(installationPath);

	// Build the appropriate unpack command based on the platform
	let unpackCommand =
		process.platform === 'win32'
			? `"${installationPath}\\Scripts\\activate.bat" && pip install open-webui${version ? `==${version}` : ' -U'}`
			: `source "${installationPath}/bin/activate" && pip install open-webui${version ? `==${version}` : ' -U'}`;

	// only unsign when installing from bundled installer
	// if (platform === "darwin") {
	//     unpackCommand = `${createAdHocSignCommand(installationPath)}\n${unpackCommand}`;
	// }

	// Wrap the logic in a Promise to properly handle async execution and return a boolean
	return new Promise((resolve, reject) => {
		const commandProcess = exec(unpackCommand, {
			shell: process.platform === 'win32' ? 'cmd.exe' : '/bin/bash'
		});

		// Function to handle logging output
		const onLog = (data: any) => {
			console.log(data);
			logEmitter.emit('log', data);
		};

		// Listen to stdout and stderr for logging
		commandProcess.stdout?.on('data', onLog);
		commandProcess.stderr?.on('data', onLog);

		// Handle the exit event
		commandProcess.on('exit', (code) => {
			console.log(`Child exited with code ${code}`);
			logEmitter.emit('log', `Child exited with code ${code}`);

			if (code !== 0) {
				log.error(`Failed to install open-webui: ${code}`);
				logEmitter.emit('log', `Failed to install open-webui: ${code}`);
				resolve(false); // Resolve the Promise with `false` if the command fails
			} else {
				logEmitter.emit('log', 'open-webui installed successfully');
				resolve(true); // Resolve the Promise with `true` if the command succeeds
			}
		});

		// Handle errors during execution
		commandProcess.on('error', (error) => {
			log.error(`Error occurred while installing open-webui: ${error.message}`);
			logEmitter.emit('log', `Error occurred while installing open-webui: ${error.message}`);
			reject(error); // Reject the Promise if an unexpected error occurs
		});
	});
}

export async function installBundledPython(installationPath?: string): Promise<boolean> {
	installationPath = installationPath || getBundledPythonInstallationPath();

	const pythonTarPath = getBundledPythonTarPath();

	console.log(installationPath, pythonTarPath);
	logEmitter.emit('log', `Installing bundled Python to: ${installationPath}`); // Emit log
	logEmitter.emit('log', `Python tarball path: ${pythonTarPath}`); // Emit log

	if (!fs.existsSync(pythonTarPath)) {
		log.error('Python tarball not found');
		logEmitter.emit('log', 'Python tarball not found'); // Emit log
		return false;
	}

	try {
		fs.mkdirSync(installationPath, { recursive: true });
		await tar.x({
			cwd: installationPath,
			file: pythonTarPath
		});
	} catch (error) {
		log.error(error);
		logEmitter.emit('log', error); // Emit log
		return false; // Return false to indicate failure
	}

	// Get the path to the installed Python binary
	const bundledPythonPath = getBundledPythonPath();

	if (!fs.existsSync(bundledPythonPath)) {
		log.error('Python binary not found in install path');
		logEmitter.emit('log', 'Python binary not found in install path'); // Emit log
		return false; // Return false to indicate failure
	}

	try {
		// Execute the Python binary to print the version
		const pythonVersion = execFileSync(bundledPythonPath, ['--version'], {
			encoding: 'utf-8'
		});
		console.log('Installed Python Version:', pythonVersion.trim());
		logEmitter.emit('log', `Installed Python Version: ${pythonVersion.trim()}`); // Emit log

		return true; // Return true to indicate success
	} catch (error) {
		log.error('Failed to execute Python binary', error);

		return false; // Return false to indicate failure
	}
}

export async function installPackage(installationPath?: string): Promise<boolean> {
	// Resolve the installation path or use the default bundled Python installation path
	installationPath = installationPath || getBundledPythonInstallationPath();

	// if (!isBundledPythonInstalled()) {
	//     try {
	//         await installBundledPython(installationPath);
	//     } catch (error) {
	//         log.error("Failed to install bundled Python", error);
	//         return Promise.reject("Failed to install bundled Python");
	//     }
	// }

	// Log the status for installation steps
	console.log('Installing Python...');

	try {
		// Install the bundled Python
		const res = await installBundledPython(installationPath);
		if (!res) {
			throw new Error('Failed to install bundled Python');
		}
	} catch (error) {
		throw new Error('Failed to install bundled Python');
	}

	console.log('Installing open-webui...');
	try {
		// Install the Open-WebUI package
		const success = await installOpenWebUI(installationPath);
		if (!success) {
			// Handle a scenario where `installOpenWebUI` returns `false`
			log.error('Failed to install open-webui');
			throw new Error('Failed to install open-webui');
		}
	} catch (error) {
		// Log and throw an error if the Open-WebUI installation fails
		log.error('Failed to install open-webui', error);
		throw new Error('Failed to install open-webui');
	}

	// Return true if all installations are successful
	return true;
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
				? `"${installationPath}\\Scripts\\activate.bat" && pip show open-webui`
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
		logEmitter.emit('log', 'Failed to validate installation'); // Emit log
		return;
	}

	try {
		const bundledPythonPath = getBundledPythonPath();

		// Execute the Python binary to print the version
		const pythonVersion = execFileSync(bundledPythonPath, ['--version'], {
			encoding: 'utf-8'
		});
		console.log('Installed Python Version:', pythonVersion.trim());
		logEmitter.emit('log', `Installed Python Version: ${pythonVersion.trim()}`); // Emit log
	} catch (error) {
		log.error('Failed to execute Python binary', error);
	}


	// Windows HATES Typer-CLI used to create the CLI for Open-WebUI
	// So we have to manually create the command to start the server
	let startCommand =
		process.platform === 'win32'
			? `"${installationPath}\\Scripts\\activate.bat" && uvicorn open_webui.main:app --host "0.0.0.0" --forwarded-allow-ips '*'`
			: `source "${installationPath}/bin/activate" && open-webui serve`;


	if (process.platform === 'win32') {
		process.env.FROM_INIT_PY = 'true';
	}

	// Set environment variables in a platform-agnostic way
	process.env.DATA_DIR = path.join(app.getPath('userData'), 'data');
	process.env.WEBUI_SECRET_KEY = getSecretKey();

	port = port || 8080;
	while (await portInUse(port)) {
		port++;
	}

	startCommand += ` --port ${port}`;

	console.log('Starting Open-WebUI server...', startCommand);
	logEmitter.emit('log', `${startCommand}`); // Emit log
	logEmitter.emit('log', 'Starting Open-WebUI server...'); // Emit log

	const childProcess = spawn(startCommand, {
		shell: true,
		detached: process.platform !== 'win32', // Detach the child process on Unix-like platforms
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
				logEmitter.emit('log', logLine);

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
		logEmitter.emit('log', `Server started with PID: ${childProcess.pid}`); // Emit PID log
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
	logEmitter.emit('log', `Server is now running at ${detectedURL}`); // Emit server URL log
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
