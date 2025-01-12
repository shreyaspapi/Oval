<script lang="ts">
	import { onMount } from 'svelte';

	import { serverUrl } from '../stores.ts';

	import Spinner from './common/Spinner.svelte';
	import ListView from './ListView.svelte';
</script>

<div class="flex flex-row w-full h-full relative dark:text-gray-100">
	<div class="absolute top-0 left-0 w-full h-7 bg-transparent draggable"></div>

	<ListView />

	<div class="flex-1 w-full flex justify-center">
		{#if !$serverUrl}
			<div class="m-auto">
				<Spinner className="size-5" />
			</div>
		{:else}
			<iframe
				src={$serverUrl}
				class="w-full h-full"
				allow="accelerometer; ambient-light-sensor; autoplay; battery; camera; display-capture; document-domain; encrypted-media; fullscreen; geolocation; gyroscope; layout-animations; legacy-image-formats; magnetometer; microphone; midi; navigation-override; oversized-images; payment; picture-in-picture; publickey-credentials-get; sync-script; sync-xhr; usb; screen-wake-lock; web-share; unoptimized-images; unsized-media; xr-spatial-tracking"
			/>
		{/if}
	</div>
</div>

<style>
	.draggable {
		-webkit-app-region: drag;
	}
</style>
