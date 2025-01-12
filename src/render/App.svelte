<script lang="ts">
	import { onMount } from 'svelte';
	import { serverUrl } from './lib/stores.ts';

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
					case 'electron:server:url':
						console.log('Setting server URL:', event.data.data);
						// Set the server URL
						serverUrl.set(event.data.data);
						break;

					default:
						console.warn('Unhandled message type:', event.data.type);
				}
			}
		});

		if (!$serverUrl) {
			const url = await window.electronAPI.getServerUrl();
			serverUrl.set(url);
		}
	});
</script>

<main class="w-screen h-screen bg-gray-900">
	<Main />
</main>
