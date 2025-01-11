import { ipcRenderer, contextBridge } from "electron";

window.addEventListener("DOMContentLoaded", () => {
  // Listen for messages from the main process
  ipcRenderer.on("main:data", (event, data) => {
    // Forward the message to the renderer using window.postMessage
    window.postMessage(
      {
        type: `electron:${data.type}`,
        data: data,
      },
      window.location.origin
    );
  });
});

contextBridge.exposeInMainWorld("electronAPI", {
  sendPing: async () => {
    console.log("Sending PING to main process...");
    await ipcRenderer.invoke("send-ping"); // Send the ping back to the main process
  },

  installPackage: async () => {
    await ipcRenderer.invoke("install-package");
  },

  loadWebUI: async (arg) => {
    await ipcRenderer.invoke("load-webui", arg);
  },
});
