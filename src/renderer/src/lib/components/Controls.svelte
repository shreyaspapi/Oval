<script lang="ts">
    import { onMount } from "svelte";

    import logoImage from "../assets/images/splash.png";
    import Spinner from "./common/Spinner.svelte";
    import Launching from "./Launching.svelte";

    let { running = $bindable() } = $props();

    let info = null;

    let startTime = $state(null);
    let currentTime = $state(null);

    onMount(async () => {
        const status = await window.electronAPI.startServer();

        if (status) {
            info = await window.electronAPI.getServerInfo();
            console.log("Server started successfully:", info);
        } else {
            info = false;
        }

        startTime = Date.now();
        currentTime = Date.now();
        setInterval(() => {
            currentTime = Date.now();
        }, 1000);
    });
</script>

{#if running}
    <div
        class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 p-1"
    >
        <div class="fixed right-0 my-5 mx-6 z-50">
            <div class="flex space-x-2">
                <button class=" self-center cursor-pointer outline-none">
                    <img
                        src={logoImage}
                        class=" w-6 rounded-full dark:invert"
                        alt="logo"
                    />
                </button>
            </div>
        </div>

        <div class=" absolute w-full top-0 left-0 right-0 z-10">
            <div class="h-6 drag-region"></div>
        </div>

        <div class="flex-1 w-full flex justify-center relative">
            <div
                class="m-auto flex flex-col justify-center text-center max-w-2xl w-full"
            >
                <div class="flex-1 w-full flex justify-center relative">
                    <div class="m-auto max-w-2xl w-full">
                        <div class="flex flex-col gap-3 text-center">
                            <Spinner className="size-5" />

                            <div class=" font-secondary xl:text-lg">
                                Launching Open WebUI...
                            </div>

                            <!-- <Versions /> -->
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
{:else}
    <Launching timeElapsed={currentTime - startTime} />
{/if}
