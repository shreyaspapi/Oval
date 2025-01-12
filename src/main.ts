import {
	app,
	nativeImage,
	desktopCapturer,
	session,
	Tray,
	Menu,
	MenuItem,
	BrowserWindow,
	globalShortcut,
	ipcMain
} from 'electron';
import path from 'path';
import started from 'electron-squirrel-startup';

import {
	installPackage,
	removePackage,
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

	const loadDefaultView = () => {
		// Load index.html or dev server URL
		if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
			mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
		} else {
			mainWindow.loadFile(path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`));
		}
	};

	const onReady = async () => {
		console.log(process.resourcesPath);
		console.log(app.getName());
		console.log(app.getPath('userData'));
		console.log(app.getPath('appData'));

		mainWindow = new BrowserWindow({
			width: 800,
			height: 600,
			icon: path.join(__dirname, 'assets/icon.png'),
			webPreferences: {
				preload: path.join(__dirname, 'preload.js')
			},
			titleBarStyle: 'hidden',
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
		});

		// Check installation and start the server
		if (validateInstallation()) {
			try {
				SERVER_URL = await startServer();
				mainWindow.loadURL(SERVER_URL);
			} catch (error) {
				console.error('Failed to start server:', error);
			}
		}

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
				{
					label: 'Home',
					accelerator: process.platform === 'darwin' ? 'Cmd+H' : 'Ctrl+H',
					click: () => {
						loadDefaultView();
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
				label: 'Show Application',
				click: () => {
					mainWindow.show(); // Show the main window when clicked
				}
			},
			{
				label: 'Quit Open WebUI',
				accelerator: 'CommandOrControl+Q',
				click: () => {
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
		installPackage();
	});

	ipcMain.handle('remove', async (event) => {
		console.log('Resetting package...');
		removePackage();
	});

	ipcMain.handle('server:start', async (event) => {
		console.log('Starting server...');

		startServer();
	});

	ipcMain.handle('server:stop', async (event) => {
		console.log('Stopping server...');

		stopAllServers();
	});

	ipcMain.handle('server:url', async (event) => {
		return SERVER_URL;
	});

	ipcMain.handle('load-webui', async (event, arg) => {
		console.log(arg); // prints "ping"
		mainWindow.loadURL('http://localhost:8080');

		mainWindow.webContents.once('did-finish-load', () => {
			mainWindow.webContents.send('main:data', {
				type: 'ping' // This is the same type you're listening for in the renderer
			});
		});

		ipcMain.on('send-ping', (event) => {
			console.log('Received PING from renderer process');
			mainWindow.webContents.send('ping-reply', 'PONG from Main Process!');
		});
	});

	app.on('before-quit', () => {
		app.isQuiting = true; // Ensure quit flag is set
		stopAllServers();
	});

	// Quit when all windows are closed, except on macOS
	app.on('window-all-closed', () => {
		if (process.platform !== 'darwin') {
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
