import {
  app,
  protocol,
  nativeImage,
  Tray,
  Menu,
  BrowserWindow,
  ipcMain,
} from "electron";
import path from "path";
import started from "electron-squirrel-startup";

// Restrict app to a single instance
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

  // Handle creating/removing shortcuts on Windows during installation/uninstallation
  if (started) {
    app.quit();
  }

  app.setAboutPanelOptions({
    applicationName: "Open WebUI",
    iconPath: path.join(__dirname, "assets/icon.png"),
    applicationVersion: app.getVersion(),
    version: app.getVersion(),
    website: "https://openwebui.com",
    copyright: `© ${new Date().getFullYear()} Open WebUI (Timothy Jaeryang Baek)`,
  });

  // Main application logic
  let mainWindow: BrowserWindow | null = null;
  let tray: Tray | null = null;

  const onReady = () => {
    console.log(process.resourcesPath);
    console.log(app.getName());
    console.log(app.getPath("userData"));
    console.log(app.getPath("appData"));
    mainWindow = new BrowserWindow({
      width: 800,
      height: 600,
      icon: path.join(__dirname, "assets/icon.png"),
      webPreferences: {
        preload: path.join(__dirname, "preload.js"),
      },
    });

    mainWindow.setIcon(path.join(__dirname, "assets/icon.png"));

    // Load index.html or dev server URL
    if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
      mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
    } else {
      mainWindow.loadFile(
        path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`)
      );
    }

    // Create a system tray icon
    const image = nativeImage.createFromPath(
      path.join(__dirname, "assets/tray.png")
    );
    tray = new Tray(image.resize({ width: 16, height: 16 }));

    const trayMenu = Menu.buildFromTemplate([
      {
        label: "Show Application",
        click: () => {
          mainWindow.show(); // Show the main window when clicked
        },
      },
      {
        label: "Quit",
        click: () => {
          app.isQuiting = true; // Mark as quitting
          app.quit(); // Quit the application
        },
      },
    ]);

    tray.setToolTip("Open WebUI");
    tray.setContextMenu(trayMenu);

    // Handle the close event
    mainWindow.on("close", (event) => {
      if (!app.isQuiting) {
        event.preventDefault(); // Prevent the default close behavior
        mainWindow.hide(); // Hide the window instead of closing it
      }
    });
  };

  ipcMain.on("load-webui", (event, arg) => {
    console.log(arg); // prints "ping"
    mainWindow.loadURL("http://localhost:8080");

    mainWindow.webContents.once("did-finish-load", () => {
      mainWindow.webContents.send("main:data", {
        type: "ping", // This is the same type you're listening for in the renderer
      });
    });

    ipcMain.on("send-ping", (event) => {
      console.log("Received PING from renderer process");
      mainWindow.webContents.send("ping-reply", "PONG from Main Process!");
    });
  });

  // Quit when all windows are closed, except on macOS
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") {
      app.quit();
    }
  });

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      onReady();
    } else {
      mainWindow?.show();
    }
  });

  app.on("ready", onReady);
}
