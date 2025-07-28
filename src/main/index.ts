import {
    app,
    shell,
    session,
    clipboard,
    nativeImage,
    desktopCapturer,
    BrowserWindow,
    globalShortcut,
    Notification,
    Menu,
    ipcMain,
    Tray,
} from "electron";
import path, { join } from "path";
import { electronApp, optimizer, is } from "@electron-toolkit/utils";

import icon from "../../resources/icon.png?asset";
import trayIconImage from "../../resources/assets/tray.png?asset";

import {
    installPackage,
    installPython,
    isPackageInstalled,
    isPythonInstalled,
    isUvInstalled,
    startServer,
    stopAllServers,
    uninstallPython,
} from "./utils";

// Main application logic
let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;

let SERVER_URL: string | null = null;
let SERVER_STATUS: string | null = null;
let SERVER_STARTED_AT: number | null = null;

function createWindow(): void {
    // Create the browser window.
    mainWindow = new BrowserWindow({
        width: 700,
        height: 500,
        minWidth: 400,
        minHeight: 400,
        icon: path.join(__dirname, "assets/icon.png"),
        show: false,
        ...(process.platform === "win32"
            ? {
                  frame: false,
              }
            : {}),
        ...(process.platform === "linux" ? { icon } : {}),
        titleBarStyle: process.platform === "win32" ? "default" : "hidden",
        trafficLightPosition: { x: 20, y: 20 },
        webPreferences: {
            preload: join(__dirname, "../preload/index.js"),
            sandbox: false,
        },
    });
    mainWindow.setIcon(icon);
    // Enables navigator.mediaDevices.getUserMedia API. See https://www.electronjs.org/docs/latest/api/desktop-capturer
    session.defaultSession.setDisplayMediaRequestHandler(
        (request, callback) => {
            desktopCapturer
                .getSources({ types: ["screen"] })
                .then((sources) => {
                    // Grant access to the first screen found.
                    callback({ video: sources[0], audio: "loopback" });
                });
        },
        { useSystemPicker: true }
    );

    if (!app.isPackaged) {
        mainWindow.webContents.openDevTools();
    }

    mainWindow.on("ready-to-show", () => {
        mainWindow?.show();
    });

    mainWindow.webContents.setWindowOpenHandler((details) => {
        shell.openExternal(details.url);
        return { action: "deny" };
    });

    globalShortcut.register("Alt+CommandOrControl+O", () => {
        mainWindow?.show();

        if (mainWindow?.isMinimized()) mainWindow?.restore();
        mainWindow?.focus();
    });

    const defaultMenu = Menu.getApplicationMenu();
    let menuTemplate = defaultMenu ? defaultMenu.items.map((item) => item) : [];
    menuTemplate.push({
        label: "Action",
        submenu: [
            {
                label: "Uninstall",
                click: () => {
                    uninstallPython();
                },
            },
        ],
    });
    const updatedMenu = Menu.buildFromTemplate(menuTemplate);
    Menu.setApplicationMenu(updatedMenu);

    // Create a system tray icon
    const image = nativeImage.createFromPath(trayIconImage);
    tray = new Tray(image.resize({ width: 16, height: 16 }));
    const trayMenu = Menu.buildFromTemplate([
        {
            label: "Show Open WebUI",
            accelerator: "CommandOrControl+Alt+O",

            click: () => {
                mainWindow?.show(); // Show the main window when clicked
            },
        },
        {
            type: "separator",
        },
        {
            label: "Quit Open WebUI",
            accelerator: "CommandOrControl+Q",
            click: async () => {
                await stopServerHandler(); // Stop the server before quitting
                app.isQuiting = true; // Mark as quitting
                app.quit(); // Quit the application
            },
        },
    ]);

    tray.setToolTip("Open WebUI");
    tray.setContextMenu(trayMenu);

    // HMR for renderer base on electron-vite cli.
    // Load the remote URL for development or the local html file for production.
    if (is.dev && process.env["ELECTRON_RENDERER_URL"]) {
        mainWindow.loadURL(process.env["ELECTRON_RENDERER_URL"]);
    } else {
        mainWindow.loadFile(join(__dirname, "../renderer/index.html"));
    }

    // Handle the close event
    mainWindow.on("close", (event) => {
        if (!(app?.isQuiting ?? false)) {
            event.preventDefault(); // Prevent the default close behavior
            mainWindow?.hide(); // Hide the window instead of closing it
        }
    });
}

const updateTrayMenu = (status: string, url: string | null) => {
    const trayMenuTemplate = [
        {
            label: "Show Open WebUI",
            accelerator: "CommandOrControl+Alt+O",
            click: () => {
                mainWindow?.show(); // Show the main window when clicked
            },
        },
        {
            type: "separator",
        },
        {
            label: status, // Dynamic status message
            enabled: !!url,
            click: () => {
                if (url) {
                    shell.openExternal(url); // Open the URL in the default browser
                }
            },
        },

        ...(SERVER_STATUS === "started"
            ? [
                  {
                      label: "Stop Server",
                      click: async () => {
                          await stopServerHandler();
                      },
                  },
              ]
            : SERVER_STATUS === "starting"
              ? [
                    {
                        label: "Starting Server...",
                        enabled: false,
                    },
                ]
              : [
                    {
                        label: "Start Server",
                        click: async () => {
                            await startServerHandler();
                        },
                    },
                ]),

        {
            type: "separator",
        },
        {
            label: "Copy Server URL",
            enabled: !!url, // Enable if URL exists
            click: () => {
                if (url) {
                    clipboard.writeText(url); // Copy the URL to clipboard
                }
            },
        },
        {
            type: "separator",
        },
        {
            label: "Quit Open WebUI",
            accelerator: "CommandOrControl+Q",
            click: () => {
                app.isQuiting = true; // Mark as quitting
                app.quit(); // Quit the application
            },
        },
    ];

    const trayMenu = Menu.buildFromTemplate(trayMenuTemplate);
    tray?.setContextMenu(trayMenu);
};

const startServerHandler = async () => {
    SERVER_STATUS = "starting";
    mainWindow?.webContents.send("main:data", {
        type: "status:server",
        data: SERVER_STATUS,
    });
    updateTrayMenu("Open WebUI: Starting...", null);

    try {
        SERVER_URL = await startServer();
        SERVER_STATUS = "started";
        SERVER_STARTED_AT = Date.now(); // Store the start time
        mainWindow?.webContents.send("main:data", {
            type: "status:server",
            data: SERVER_STATUS,
        });

        // // Load the server URL in the main window
        // if (SERVER_URL.startsWith("http://0.0.0.0")) {
        //     SERVER_URL = SERVER_URL.replace(
        //         "http://0.0.0.0",
        //         "http://localhost"
        //     );
        // }
        // mainWindow.loadURL(SERVER_URL);

        const urlObj = new URL(SERVER_URL);
        const port = urlObj.port || "8080"; // Fallback to port 8080 if not provided
        updateTrayMenu(`Open WebUI: Running on port ${port}`, SERVER_URL); // Update tray menu with running status

        return true; // Indicate success
    } catch (error) {
        console.error("Failed to start server:", error);
        SERVER_STATUS = "failed";
        mainWindow?.webContents.send("main:data", {
            type: "status:server",
            data: SERVER_STATUS,
        });

        mainWindow?.webContents.send(
            "main:log",
            `Failed to start server: ${error}`
        );
        updateTrayMenu("Open WebUI: Failed to Start", null); // Update tray menu with failure status

        return false; // Indicate failure
    }
};

const stopServerHandler = async () => {
    try {
        await stopAllServers();

        SERVER_STATUS = "stopped";
        SERVER_URL = null; // Clear the server URL
        SERVER_STARTED_AT = null; // Reset the start time

        mainWindow?.webContents.send("main:data", {
            type: "status:server",
            data: SERVER_STATUS,
        });

        updateTrayMenu("Open WebUI: Stopped", null); // Update tray menu with stopped status
        return true; // Indicate success
    } catch (error) {
        console.error("Failed to stop server:", error);
        return false; // Indicate failure
    }
};

const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
    app.quit(); // Quit if another instance is already running
} else {
    // Handle second-instance logic
    app.on("second-instance", (event, argv, workingDirectory) => {
        // This event happens if a second instance is launched
        if (mainWindow) {
            if (mainWindow.isMinimized()) mainWindow.restore(); // Restore if minimized
            mainWindow.show(); // Show existing window
            mainWindow.focus(); // Focus the existing window
        }
    });

    app.setAboutPanelOptions({
        applicationName: "Open WebUI",
        iconPath: icon,
        applicationVersion: app.getVersion(),
        version: app.getVersion(),
        website: "https://openwebui.com",
        copyright: `© ${new Date().getFullYear()} Open WebUI (Timothy Jaeryang Baek)`,
    });

    // This method will be called when Electron has finished
    // initialization and is ready to create browser windows.
    // Some APIs can only be used after this event occurs.
    app.whenReady().then(() => {
        // Set app user model id for windows
        electronApp.setAppUserModelId("com.openwebui.desktop");

        // Default open or close DevTools by F12 in development
        // and ignore CommandOrControl + R in production.
        app.on("browser-window-created", (_, window) => {
            optimizer.watchWindowShortcuts(window);
        });

        // IPC test
        ipcMain.on("ping", () => console.log("pong"));

        ipcMain.handle("install:python", async (event) => {
            console.log("Installing package...");
            try {
                const res = await installPython();
                if (res) {
                    mainWindow?.webContents.send("main:data", {
                        type: "status:python",
                        data: true,
                    });
                }
            } catch (error) {
                mainWindow?.webContents.send("main:data", {
                    type: "status:python",
                    data: false,
                });
            }
        });

        ipcMain.handle("install:package", async (event) => {
            console.log("Installing package...");
            try {
                const res = await installPackage("open-webui");
                if (res) {
                    mainWindow?.webContents.send("main:data", {
                        type: "status:package",
                        data: true,
                    });
                }
            } catch (error) {
                mainWindow?.webContents.send("main:data", {
                    type: "status:package",
                    data: false,
                });
            }
        });

        ipcMain.handle("status:python", async (event) => {
            return (await isPythonInstalled()) && (await isUvInstalled());
        });

        ipcMain.handle("status:package", async (event) => {
            const packageStatus = await isPackageInstalled("open-webui");

            console.log("Package Status:", packageStatus);
            return packageStatus;
        });

        ipcMain.handle("server:start", async (event) => {
            return await startServerHandler();
        });

        ipcMain.handle("server:stop", async (event) => {
            return await stopServerHandler();
        });

        ipcMain.handle("server:info", async (event) => {
            return {
                url: SERVER_URL,
                status: SERVER_STATUS,
            };
        });

        ipcMain.handle("status:server", async (event) => {
            return SERVER_STATUS;
        });

        ipcMain.handle("notification", async (event, { title, body }) => {
            console.log("Received notification:", title, body);
            const notification = new Notification({
                title: title,
                body: body,
            });
            notification.show();
        });

        createWindow();

        app.on("activate", function () {
            // On macOS it's common to re-create a window in the app when the
            // dock icon is clicked and there are no other windows open.
            if (BrowserWindow.getAllWindows().length === 0) createWindow();
        });
    });

    // Quit when all windows are closed, except on macOS. There, it's common
    // for applications and their menu bar to stay active until the user quits
    // explicitly with Cmd + Q.
    app.on("window-all-closed", () => {
        if (process.platform !== "darwin") {
            app.quit();
        }
    });

    app.on("before-quit", async () => {
        app.isQuiting = true; // Mark as quitting
        await stopServerHandler(); // Stop the server before quitting
        globalShortcut.unregisterAll(); // Unregister all shortcuts
        mainWindow = null; // Clear the main window reference
        tray?.destroy(); // Destroy the tray icon
        tray = null; // Clear the tray reference
    });
}
