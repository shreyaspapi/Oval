<script lang="ts">
	import { Toaster, toast } from 'svelte-sonner';

	import { onMount } from 'svelte';
	import { installStatus, serverStatus, serverStartedAt, serverLogs } from './lib/stores';

	import Main from './lib/components/Main.svelte';

	let logs = [];

	onMount(async () => {
		window.addEventListener('message', (event) => {
			// Ensure the message is coming from a trusted origin
			if (event.origin !== window.location.origin) {
				console.warn('Received message from untrusted origin:', event.origin);
				return;
			}

			// Check the type of the message
			if (event.data && event.data.type && event.data.type.startsWith('electron:')) {
				console.log('Received message:', event.data);

				// Perform actions based on the `type` or the `data`
				switch (event.data.type) {
					case 'electron:install:status':
						console.log('Install status:', event.data.data);
						installStatus.set(event.data.data);

						break;

					case 'electron:server:status':
						console.log('Server status:', event.data.data);
						serverStatus.set(event.data.data);

						if ($serverStatus) {
							serverStartedAt.set(Date.now());
						}
						break;

					default:
						console.warn('Unhandled message type:', event.data.type);
				}
			}
		});

		if (window.electronAPI) {
			installStatus.set(await window.electronAPI.getInstallStatus());
			serverStatus.set(await window.electronAPI.getServerStatus());

			if ($installStatus && $serverStatus === 'stopped') {
				window.electronAPI.startServer();
			}

			window.electronAPI.onLog((log) => {
				console.log('Electron log:', log);
				logs.push(log);
				serverLogs.set(logs);
			});
		}
	});
</script>

<main class="w-screen h-screen bg-gray-900">
	<Main />
</main>

<Toaster
	theme={window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'}
	richColors
	position="top-center"
/>
