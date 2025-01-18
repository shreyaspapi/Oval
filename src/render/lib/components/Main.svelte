<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { fly } from 'svelte/transition';

	import { installStatus, serverStatus, serverStartedAt, serverLogs } from '../stores';

	import Logs from './setup/Logs.svelte';
	import Spinner from './common/Spinner.svelte';
	import ArrowRightCircle from './icons/ArrowRightCircle.svelte';

	import backgroundImage from '../assets/images/green.jpg';

	let mounted = false;
	let currentTime = Date.now();

	let showLogs = false;

	let installing = false;
	const continueHandler = async () => {
		if (window?.electronAPI) {
			window.electronAPI.installPackage();
			installing = true;
		}
	};

	onMount(() => {
		installStatus.subscribe(async (value) => {
			if (value !== null) {
				await tick();
				mounted = true;
			}
		});

		const interval = setInterval(() => {
			currentTime = Date.now();
		}, 1000); // Update every second

		return () => {
			clearInterval(interval); // Cleanup interval on destroy
		};
	});
</script>

{#if $installStatus === null}
	<div class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 drag-region">
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
	<div class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 p-1">
		<div class="fixed right-0 m-10 z-50">
			<div class="flex space-x-2">
				<button
					class=" self-center cursor-pointer outline-none"
					onclick={() => (showLogs = !showLogs)}
				>
					<img
						src="./assets/images/splash.png"
						class=" w-6 rounded-full dark:invert"
						alt="logo"
					/>
				</button>
			</div>
		</div>

		<div
			class="image w-full h-full absolute top-0 left-0 bg-cover bg-center transition-opacity duration-1000"
			style="opacity: 1; background-image: url({backgroundImage})"
		></div>

		<div
			class="w-full h-full absolute top-0 left-0 bg-gradient-to-t from-20% from-white dark:from-black to-transparent"
		></div>

		<div
			class="w-full h-full absolute top-0 left-0 backdrop-blur-sm bg-white/50 dark:bg-black/50"
		></div>

		<div class=" absolute w-full top-0 left-0 right-0 z-10">
			<div class="h-6 drag-region"></div>
		</div>

		<div class="flex-1 w-full flex justify-center relative">
			{#if $installStatus === false}
				<div class="m-auto flex flex-col justify-center text-center">
					{#if mounted}
						<div
							class=" font-medium text-5xl xl:text-7xl text-center mb-4 xl:mb-5 font-secondary"
							in:fly={{ duration: 750, y: 20 }}
						>
							Open WebUI
						</div>

						<div
							class=" text-sm xl:text-lg text-center mb-3"
							in:fly={{ delay: 250, duration: 750, y: 10 }}
						>
							To install Open WebUI, click Continue.
						</div>
					{/if}

					<Logs show={showLogs} logs={$serverLogs} />
				</div>

				<div class="absolute bottom-0 pb-10">
					<div class="flex justify-center mt-8">
						<div class="flex flex-col justify-center items-center">
							{#if installing}
								<div class="flex flex-col gap-3 text-center">
									<Spinner className="size-5" />

									<div class=" font-secondary xl:text-lg -mt-0.5">
										Installing...
									</div>

									<div
										class=" font-default text-xs"
										in:fly={{ delay: 100, duration: 500, y: 10 }}
									>
										This might take a few minutes, We’ll notify you when it’s
										ready.
									</div>

									{#if $serverLogs.length > 0}
										<div
											class="text-[0.5rem] text-gray-500 font-mono text-center line-clamp-1 px-10"
										>
											{$serverLogs.at(-1)}
										</div>
									{/if}
								</div>
							{:else if mounted}
								<button
									class="relative z-20 flex p-1 rounded-full bg-black/5 hover:bg-black/10 dark:bg-white/5 dark:hover:bg-white/10 transition font-medium text-sm cursor-pointer"
									onclick={() => {
										continueHandler();
									}}
									in:fly={{ delay: 500, duration: 750, y: 10 }}
								>
									<ArrowRightCircle className="size-6" />
								</button>
								<div
									class="mt-1.5 font-primary text-base font-medium"
									in:fly={{ delay: 500, duration: 750, y: 10 }}
								>
									{`Continue`}
								</div>

								<button
									class="text-xs mt-3 text-gray-500 cursor-pointer"
									in:fly={{ delay: 500, duration: 750, y: 10 }}
									onclick={() => {
										console.log('hi');
									}}
								>
									To connect to an existing server, click here.
								</button>
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

							<Logs show={showLogs} logs={$serverLogs} />
						</div>
					</div>
				</div>
			{/if}
		</div>
	</div>
{/if}
