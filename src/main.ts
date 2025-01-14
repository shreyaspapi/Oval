import {
	app,
	nativeImage,
	desktopCapturer,
	session,
	clipboard,
	shell,
	Tray,
	Menu,
	MenuItem,
	BrowserWindow,
	globalShortcut,
	Notification,
	ipcMain,
	ipcRenderer
} from 'electron';
import path from 'path';
import started from 'electron-squirrel-startup';

import {
	installPackage,
	removePackage,
	logEmitter,
	startServer,
	stopAllServers,
	validateInstallation
} from './utils';

// Restrict app to a single instance
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
	app.quit(); // Quit if another instance is already running
} else {
	// Handle second-instance logic
	app.on('second-instance', (event, argv, workingDirectory) => {
		// This event happens if a second instance is launched
		if (mainWindow) {
			if (mainWindow.isMinimized()) mainWindow.restore(); // Restore if minimized
			mainWindow.show(); // Show existing window
			mainWindow.focus(); // Focus the existing window
		}
	});

	// Handle creating/removing shortcuts on Windows during installation/uninstallation
	if (started) {
		app.quit();
	}

	app.setAboutPanelOptions({
		applicationName: 'Open WebUI',
		iconPath: path.join(__dirname, 'assets/icon.png'),
		applicationVersion: app.getVersion(),
		version: app.getVersion(),
		website: 'https://openwebui.com',
		copyright: `© ${new Date().getFullYear()} Open WebUI (Timothy Jaeryang Baek)`
	});

	// Main application logic
	let mainWindow: BrowserWindow | null = null;
	let tray: Tray | null = null;

	let SERVER_URL = null;
	let SERVER_STATUS = 'stopped';

	logEmitter.on('log', (message) => {
		mainWindow?.webContents.send('main:log', message);
	});

	const loadDefaultView = () => {
		// Load index.html or dev server URL
		if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
			mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
		} else {
			mainWindow.loadFile(path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`));
		}
	};

	const updateTrayMenu = (status: string, url: string | null) => {
		const trayMenuTemplate = [
			{
				label: 'Show Open WebUI',
				accelerator: 'CommandOrControl+Alt+O',
				click: () => {
					mainWindow?.show(); // Show the main window when clicked
				}
			},
			{
				type: 'separator'
			},
			{
				label: status, // Dynamic status message
				enabled: !!url,
				click: () => {
					if (url) {
						shell.openExternal(url); // Open the URL in the default browser
					}
				}
			},

			...(SERVER_STATUS === 'started'
				? [
						{
							label: 'Stop Server',
							click: async () => {
								await stopAllServers();
								SERVER_STATUS = 'stopped';
								mainWindow.webContents.send('main:data', {
									type: 'server:status',
									data: SERVER_STATUS
								});
								updateTrayMenu('Open WebUI: Stopped', null); // Update tray menu with stopped status
							}
						}
					]
				: SERVER_STATUS === 'starting'
					? [
							{
								label: 'Starting Server...',
								enabled: false
							}
						]
					: [
							{
								label: 'Start Server',
								click: async () => {
									await startServerHandler();
								}
							}
						]),

			{
				type: 'separator'
			},
			{
				label: 'Copy Server URL',
				enabled: !!url, // Enable if URL exists
				click: () => {
					if (url) {
						clipboard.writeText(url); // Copy the URL to clipboard
					}
				}
			},
			{
				type: 'separator'
			},
			{
				label: 'Quit Open WebUI',
				accelerator: 'CommandOrControl+Q',
				click: () => {
					app.isQuiting = true; // Mark as quitting
					app.quit(); // Quit the application
				}
			}
		];

		const trayMenu = Menu.buildFromTemplate(trayMenuTemplate);
		tray?.setContextMenu(trayMenu);
	};

	const startServerHandler = async () => {
		SERVER_STATUS = 'starting';
		mainWindow.webContents.send('main:data', {
			type: 'server:status',
			data: SERVER_STATUS
		});
		updateTrayMenu('Open WebUI: Starting...', null);

		try {
			SERVER_URL = await startServer();
			// SERVER_URL = 'http://localhost:5050';

			SERVER_STATUS = 'started';
			mainWindow.webContents.send('main:data', {
				type: 'server:status',
				data: SERVER_STATUS
			});

			if (SERVER_URL.startsWith('http://0.0.0.0')) {
				SERVER_URL = SERVER_URL.replace('http://0.0.0.0', 'http://localhost');
			}

			mainWindow.loadURL(SERVER_URL);

			const urlObj = new URL(SERVER_URL);
			const port = urlObj.port || '8080'; // Fallback to port 8080 if not provided
			updateTrayMenu(`Open WebUI: Running on port ${port}`, SERVER_URL); // Update tray menu with running status
		} catch (error) {
			console.error('Failed to start server:', error);
			SERVER_STATUS = 'failed';
			mainWindow.webContents.send('main:data', {
				type: 'server:status',
				data: SERVER_STATUS
			});

			mainWindow.webContents.send('main:log', `Failed to start server: ${error}`);
			updateTrayMenu('Open WebUI: Failed to Start', null); // Update tray menu with failure status
		}
	};

	const onReady = async () => {
		console.log(process.resourcesPath);
		console.log(app.getName());
		console.log(app.getPath('userData'));
		console.log(app.getPath('appData'));

		mainWindow = new BrowserWindow({
			width: 1000,
			height: 600,
			minWidth: 425,
			minHeight: 600,
			icon: path.join(__dirname, 'assets/icon.png'),
			webPreferences: {
				preload: path.join(__dirname, 'preload.js')
			},
			titleBarStyle: process.platform === 'win32' ? 'default' : 'hidden',
			trafficLightPosition: { x: 10, y: 10 },
			// expose window controlls in Windows/Linux
			...(process.platform !== 'darwin' ? { titleBarOverlay: true } : {})
		});
		mainWindow.setIcon(path.join(__dirname, 'assets/icon.png'));

		// Enables navigator.mediaDevices.getUserMedia API. See https://www.electronjs.org/docs/latest/api/desktop-capturer
		session.defaultSession.setDisplayMediaRequestHandler(
			(request, callback) => {
				desktopCapturer.getSources({ types: ['screen'] }).then((sources) => {
					// Grant access to the first screen found.
					callback({ video: sources[0], audio: 'loopback' });
				});
			},
			{ useSystemPicker: true }
		);

		loadDefaultView();
		if (!app.isPackaged) {
			mainWindow.webContents.openDevTools();
		}

		// Wait for the renderer to finish loading
		mainWindow.webContents.once('did-finish-load', async () => {
			console.log('Renderer finished loading');

			// Check installation and start the server
			if (await validateInstallation()) {
				mainWindow.webContents.send('main:data', {
					type: 'install:status',
					data: true
				});
			} else {
				mainWindow.webContents.send('main:data', {
					type: 'install:status',
					data: false
				});
			}
		});

		globalShortcut.register('Alt+CommandOrControl+O', () => {
			mainWindow?.show();

			if (mainWindow?.isMinimized()) mainWindow?.restore();
			mainWindow?.focus();
		});

		const defaultMenu = Menu.getApplicationMenu();
		let menuTemplate = defaultMenu ? defaultMenu.items.map((item) => item) : [];
		menuTemplate.push({
			label: 'Action',
			submenu: [
				// {
				// 	label: 'Home',
				// 	accelerator: process.platform === 'darwin' ? 'Cmd+H' : 'Ctrl+H',
				// 	click: () => {
				// 		loadDefaultView();
				// 	}
				// },
				{
					label: 'Uninstall',
					click: () => {
						loadDefaultView();
						removePackage();
					}
				}
			]
		});
		const updatedMenu = Menu.buildFromTemplate(menuTemplate);
		Menu.setApplicationMenu(updatedMenu);

		// Create a system tray icon
		const image = nativeImage.createFromPath(path.join(__dirname, 'assets/tray.png'));
		tray = new Tray(image.resize({ width: 16, height: 16 }));

		const trayMenu = Menu.buildFromTemplate([
			{
				label: 'Show Open WebUI',
				accelerator: 'CommandOrControl+Alt+O',

				click: () => {
					mainWindow.show(); // Show the main window when clicked
				}
			},
			{
				type: 'separator'
			},
			{
				label: 'Quit Open WebUI',
				accelerator: 'CommandOrControl+Q',
				click: async () => {
					await stopAllServers();
					app.isQuiting = true; // Mark as quitting
					app.quit(); // Quit the application
				}
			}
		]);

		tray.setToolTip('Open WebUI');
		tray.setContextMenu(trayMenu);

		// Handle the close event
		mainWindow.on('close', (event) => {
			if (!app.isQuiting) {
				event.preventDefault(); // Prevent the default close behavior
				mainWindow.hide(); // Hide the window instead of closing it
			}
		});
	};

	ipcMain.handle('install', async (event) => {
		console.log('Installing package...');

		try {
			const res = await installPackage();
			if (res) {
				mainWindow.webContents.send('main:data', {
					type: 'install:status',
					data: true
				});

				await startServerHandler();
			}
		} catch (error) {
			mainWindow.webContents.send('main:data', {
				type: 'install:status',
				data: false
			});
		}
	});

	ipcMain.handle('install:status', async (event) => {
		return await validateInstallation();
	});

	ipcMain.handle('remove', async (event) => {
		console.log('Resetting package...');
		removePackage();
	});

	ipcMain.handle('server:status', async (event) => {
		return SERVER_STATUS;
	});

	ipcMain.handle('server:start', async (event) => {
		console.log('Starting server...');

		await startServerHandler();
	});

	ipcMain.handle('server:stop', async (event) => {
		console.log('Stopping server...');

		await stopAllServers();
		SERVER_STATUS = 'stopped';
		mainWindow.webContents.send('main:data', {
			type: 'server:status',
			data: SERVER_STATUS
		});
		updateTrayMenu('Open WebUI: Stopped', null); // Update tray menu with stopped status
	});

	ipcMain.handle('server:url', async (event) => {
		return SERVER_URL;
	});

	ipcMain.handle('renderer:data', async (event, { type, data }) => {
		console.log('Received data from renderer:', type, data);

		if (type === 'version') {
			return {
				version: app.getVersion()
			};
		}

		if (type === 'window:isFocused') {
			return {
				isFocused: mainWindow?.isFocused()
			};
		}

		return { type, data };
	});

	ipcMain.handle('notification', async (event, { title, body }) => {
		console.log('Received notification:', title, body);
		const notification = new Notification({
			title: title,
			body: body
		});
		notification.show();
	});

	app.on('before-quit', async () => {
		await stopAllServers();
		app.isQuiting = true; // Ensure quit flag is set
	});

	// Quit when all windows are closed, except on macOS
	app.on('window-all-closed', async () => {
		if (process.platform !== 'darwin') {
			await stopAllServers();
			app.isQuitting = true;
			app.quit();
		}
	});

	app.on('activate', () => {
		if (BrowserWindow.getAllWindows().length === 0) {
			onReady();
		} else {
			mainWindow?.show();
		}
	});

	app.on('ready', onReady);
}
