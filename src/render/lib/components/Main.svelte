<script lang="ts">
	import { onMount } from 'svelte';
	import { installStatus } from '../stores';

	import Spinner from './common/Spinner.svelte';
	import ArrowRightCircle from './icons/ArrowRightCircle.svelte';

	const continueHandler = async () => {
		if (window?.electronAPI) {
			window.electronAPI.installPackage();
		}
	};
</script>

{#if $installStatus === null}
	<div class="flex flex-row w-full h-full relative dark:text-gray-100">
		<div class="absolute top-0 left-0 w-full h-7 bg-transparent draggable"></div>

		<div class="flex-1 w-full flex justify-center relative">
			<div class="m-auto">
				<Spinner className="size-5" />
			</div>
		</div>
	</div>
{:else if $installStatus === false}
	<div class="flex flex-row w-full h-full relative dark:text-gray-100">
		<div class="absolute top-0 left-0 w-full h-7 bg-transparent draggable"></div>

		<div class="fixed right-0 m-10 z-50">
			<div class="flex space-x-2">
				<div class=" self-center">
					<img
						crossorigin="anonymous"
						src="./assets/images/splash.png"
						class=" w-6 rounded-full dark:invert"
						alt="logo"
					/>
				</div>
			</div>
		</div>

		<div
			class="image w-full h-full absolute top-0 left-0 bg-cover bg-center transition-opacity duration-1000"
			style="opacity: 1; background-image: url('./assets/images/green.jpg')"
		></div>

		<div
			class="w-full h-full absolute top-0 left-0 bg-gradient-to-t from-20% from-black to-transparent"
		></div>

		<div class="w-full h-full absolute top-0 left-0 backdrop-blur-sm bg-black/50"></div>

		<div class="flex-1 w-full flex justify-center relative">
			<div class="m-auto flex flex-col justify-center text-center max-w-md">
				<div class=" font-medium text-5xl text-center mb-4 font-secondary">Open WebUI</div>

				<div class=" text-sm text-center mb-3">To install Open WebUI, click Continue.</div>
			</div>

			<div class="absolute bottom-0 pb-10">
				<div class="flex justify-center mt-8">
					<div class="flex flex-col justify-center items-center">
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
					</div>
				</div>
			</div>
		</div>
	</div>
{:else}
	<div class="flex flex-row w-full h-full relative dark:text-gray-100">
		<div class="absolute top-0 left-0 w-full h-7 bg-transparent draggable"></div>

		<div class="flex-1 w-full flex justify-center relative">
			<div class="m-auto">
				<div class="flex flex-col gap-3">
					<Spinner className="size-5" />

					<div class=" font-secondary">Launching Open WebUI...</div>
				</div>
			</div>
		</div>
	</div>
{/if}

<style>
	.draggable {
		-webkit-app-region: drag;
	}
</style>
