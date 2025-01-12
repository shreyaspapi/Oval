<script lang="ts">
	import { onMount } from 'svelte';

	import Spinner from './common/Spinner.svelte';
	import ListView from './ListView.svelte';
</script>

<div class="flex flex-row w-full h-full relative dark:text-gray-100">
	<div class="absolute top-0 left-0 w-full h-6 bg-transparent draggable"></div>

	<ListView />

	<div class="flex-1 w-full flex justify-center">
		<div class="my-auto flex flex-col max-w-xs w-full">
			<div class=" flex justify-center mb-3">
				<!-- <img
                    src="./assets/images/splash.png"
                    class=" size-24 dark:invert"
                    alt="hero"
                /> -->
			</div>

			<!-- <div class=" text-2xl text-gray-50 font-secondary">Install Open WebUI</div> -->

			<div class=" text-gray-500 hover:text-white transition">
				<div class="flex justify-center items-center gap-2">
					<div>Loading...</div>
					<div>
						<Spinner className="size-4" />
					</div>
				</div>
			</div>

			<!-- <button
                        class="    hover:text-white transition font-medium cursor-pointer"
                        onclick={() => {
                            console.log("install clicked");
                            if (window?.electronAPI) {
                                window.electronAPI.installPackage();
                            }
                        }}
                    >
                        <div class="flex justify-center items-center gap-2">
                            <div>Install</div>
                            <div>
                                <Spinner className="size-4" />
                            </div>
                        </div>
                    </button> -->

			<!--
            
                    <button
                        class=" text-gray-100 hover:text-white transition font-medium cursor-pointer"
                        onclick={() => {
                            console.log("start clicked");
                            if (window?.electronAPI) {
                                window.electronAPI.startServer();
                            }
                        }}>Start Open WebUI</button
                    >
            
                    <button
                        class=" text-gray-100 hover:text-white transition font-medium cursor-pointer"
                        onclick={() => {
                            console.log("stop clicked");
                            if (window?.electronAPI) {
                                window.electronAPI.stopServer();
                            }
                        }}>Stop Open WebUI</button
                    > -->
		</div>
	</div>
</div>

<style>
	.draggable {
		-webkit-app-region: drag;
	}
</style>
