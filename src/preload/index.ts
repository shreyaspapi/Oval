import { ipcRenderer, contextBridge } from "electron";
import { electronAPI } from "@electron-toolkit/preload";

const isLocalSource = () => {
    // Check if the execution environment is local
    const origin = window.location.origin;

    // Allow local sources: file protocol, localhost, or 0.0.0.0
    return (
        origin.startsWith("file://") ||
        origin.includes("localhost") ||
        origin.includes("127.0.0.1") ||
        origin.includes("0.0.0.0")
    );
};

window.addEventListener("DOMContentLoaded", () => {
    // Listen for messages from the main process
    ipcRenderer.on("main:data", (event, data) => {
        // Forward the message to the renderer using window.postMessage
        window.postMessage(
            {
                ...data,
                type: `electron:${data.type}`,
            },
            window.location.origin
        );
    });
});

// Custom APIs for renderer
const api = {
    onLog: (callback: (message: string) => void) => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        ipcRenderer.on("main:log", (_, message: string) => callback(message));
    },

    send: async ({ type, data }: { type: string; data?: any }) => {
        return await ipcRenderer.invoke("renderer:data", { type, data });
    },

    installPython: async () => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("install:python");
    },

    installPackage: async () => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("install:package");
    },

    getPythonStatus: async () => {
        return await ipcRenderer.invoke("status:python");
    },

    getPackageStatus: async () => {
        return await ipcRenderer.invoke("status:package");
    },

    getServerStatus: async () => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("status:server");
    },

    getServerInfo: async () => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("server:info");
    },

    startServer: async () => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("server:start");
    },

    stopServer: async () => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("server:stop");
    },

    getServerUrl: async () => {
        return await ipcRenderer.invoke("server:url");
    },

    notification: async (title: string, body: string) => {
        if (!isLocalSource()) {
            throw new Error(
                "Access restricted: This operation is only allowed in a local environment."
            );
        }

        return await ipcRenderer.invoke("notification", { title, body });
    },
};

// Use `contextBridge` APIs to expose Electron APIs to
// renderer only if context isolation is enabled, otherwise
// just add to the DOM global.
if (process.contextIsolated) {
    try {
        contextBridge.exposeInMainWorld("electron", electronAPI);
        contextBridge.exposeInMainWorld("electronAPI", api);
    } catch (error) {
        console.error(error);
    }
} else {
    // @ts-ignore (define in dts)
    window.electron = electronAPI;
    // @ts-ignore (define in dts)
    window.electronAPI = api;
}
