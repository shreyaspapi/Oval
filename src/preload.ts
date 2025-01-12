import { ipcRenderer, contextBridge, desktopCapturer } from 'electron';

const isLocalSource = () => {
	// Check if the execution environment is local
	const origin = window.location.origin;

	// Allow local sources: file protocol, localhost, or 0.0.0.0
	return (
		origin.startsWith('file://') ||
		origin.includes('localhost') ||
		origin.includes('127.0.0.1') ||
		origin.includes('0.0.0.0')
	);
};

window.addEventListener('DOMContentLoaded', () => {
	// Listen for messages from the main process
	ipcRenderer.on('main:data', (event, data) => {
		// Forward the message to the renderer using window.postMessage
		window.postMessage(
			{
				...data,
				type: `electron:${data.type}`
			},
			window.location.origin
		);
	});
});

contextBridge.exposeInMainWorld('electronAPI', {
	sendPing: async () => {
		console.log('Sending PING to main process...');
		await ipcRenderer.invoke('send-ping'); // Send the ping back to the main process
	},

	installPackage: async () => {
		if (!isLocalSource()) {
			throw new Error('Access restricted: This operation is only allowed in a local environment.');
		}

		await ipcRenderer.invoke('install');
	},

	removePackage: async () => {
		if (!isLocalSource()) {
			throw new Error('Access restricted: This operation is only allowed in a local environment.');
		}

		await ipcRenderer.invoke('remove');
	},

	startServer: async () => {
		if (!isLocalSource()) {
			throw new Error('Access restricted: This operation is only allowed in a local environment.');
		}

		await ipcRenderer.invoke('server:start');
	},

	stopServer: async () => {
		if (!isLocalSource()) {
			throw new Error('Access restricted: This operation is only allowed in a local environment.');
		}

		await ipcRenderer.invoke('server:stop');
	},

	getServerUrl: async () => {
		return await ipcRenderer.invoke('server:url');
	}
});
