<script lang="ts">
	import { onMount } from 'svelte';
	import { installStatus, serverStatus } from './lib/stores';

	import Main from './lib/components/Main.svelte';

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
			});
		}
	});
</script>

<main class="w-screen h-screen bg-gray-900">
	<Main />
</main>
