<script lang="ts">
	import { onMount } from 'svelte';
	import { fly } from 'svelte/transition';

	import { installStatus, serverStatus, serverStartedAt } from '../stores';

	import Spinner from './common/Spinner.svelte';
	import ArrowRightCircle from './icons/ArrowRightCircle.svelte';

	import backgroundImage from '../assets/images/green.jpg';

	let currentTime = Date.now();

	let installing = false;
	const continueHandler = async () => {
		if (window?.electronAPI) {
			window.electronAPI.installPackage();
			installing = true;
		}
	};

	onMount(() => {
		const interval = setInterval(() => {
			currentTime = Date.now();
		}, 1000); // Update every second

		return () => {
			clearInterval(interval); // Cleanup interval on destroy
		};
	});
</script>

{#if $installStatus === null}
	<div class="flex flex-row w-full h-full relative dark:text-gray-100">
		<div class="absolute top-0 left-0 w-full h-7 bg-transparent draggable"></div>

		<div class="flex-1 w-full flex justify-center relative">
			<div class="m-auto">
				<img
					src="./assets/images/splash.png"
					class="size-18 rounded-full dark:invert"
					alt="logo"
				/>
			</div>
		</div>
	</div>
{:else}
	<div class="flex flex-row w-full h-full relative dark:text-gray-100">
		<div class="absolute top-0 left-0 w-full h-7 bg-transparent draggable"></div>

		<div class="fixed right-0 m-10 z-50">
			<div class="flex space-x-2">
				<div class=" self-center">
					<img
						src="./assets/images/splash.png"
						class=" w-6 rounded-full dark:invert"
						alt="logo"
					/>
				</div>
			</div>
		</div>

		<div
			class="image w-full h-full absolute top-0 left-0 bg-cover bg-center transition-opacity duration-1000"
			style="opacity: 1; background-image: url({backgroundImage})"
		></div>

		<div
			class="w-full h-full absolute top-0 left-0 bg-gradient-to-t from-20% from-black to-transparent"
		></div>

		<div class="w-full h-full absolute top-0 left-0 backdrop-blur-sm bg-black/50"></div>

		<div class="flex-1 w-full flex justify-center relative">
			{#if $installStatus === false}
				<div class="m-auto flex flex-col justify-center text-center max-w-md">
					<div
						class=" font-medium text-5xl xl:text-7xl text-center mb-4 xl:mb-5 font-secondary"
					>
						Open WebUI
					</div>

					<div class=" text-sm xl:text-lg text-center mb-3">
						To install Open WebUI, click Continue.
					</div>
				</div>

				<div class="absolute bottom-0 pb-10">
					<div class="flex justify-center mt-8">
						<div class="flex flex-col justify-center items-center">
							{#if installing}
								<div class="flex flex-col gap-3 text-center">
									<Spinner className="size-5" />

									<div class=" font-secondary xl:text-lg">Installing...</div>

									<div
										class=" font-default text-xs"
										in:fly={{ duration: 500, y: 10 }}
									>
										This might take a few minutes, We’ll notify you when it’s
										ready.
									</div>
								</div>
							{:else}
								<button
									class="relative z-20 flex p-1 rounded-full bg-white/5 hover:bg-white/10 transition font-medium text-sm cursor-pointer"
									on:click={() => {
										continueHandler();
									}}
								>
									<ArrowRightCircle className="size-6" />
								</button>
								<div class="mt-1.5 font-primary text-base font-medium">
									{`Continue`}
								</div>
							{/if}
						</div>
					</div>
				</div>
			{:else if $installStatus === true}
				<div class="flex-1 w-full flex justify-center relative">
					<div class="m-auto">
						<div class="flex flex-col gap-3 text-center">
							<Spinner className="size-5" />

							<div class=" font-secondary xl:text-lg">Launching Open WebUI...</div>

							{#if $serverStartedAt}
								{#if currentTime - $serverStartedAt > 10000}
									<div
										class=" font-default text-xs"
										in:fly={{ duration: 500, y: 10 }}
									>
										If it's your first time, it might take a few minutes to
										start.
									</div>
								{/if}
							{/if}
						</div>
					</div>
				</div>
			{/if}
		</div>
	</div>
{/if}

<style>
	.draggable {
		-webkit-app-region: drag;
	}
</style>
