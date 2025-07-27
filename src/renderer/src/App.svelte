<script lang="ts">
    import Spinner from "./lib/components/common/Spinner.svelte";
    import Landing from "./lib/components/Landing.svelte";
    import Versions from "./lib/components/Versions.svelte";

    import splashImage from "./lib/assets/images/splash.png";
    import { Toaster } from "svelte-sonner";

    const installed = $state(false);

    const ipcHandle = (): void => window.electron.ipcRenderer.send("ping");
</script>

<main class="w-screen h-screen bg-gray-900">
    {#if installed === null}
        <div
            class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 drag-region"
        >
            <div class="flex-1 w-full flex justify-center relative">
                <div class="m-auto">
                    <img
                        src={splashImage}
                        class="size-18 rounded-full dark:invert"
                        alt="logo"
                    />
                </div>
            </div>
        </div>
    {:else if installed === false}
        <Landing />
    {:else}
        <div class="flex-1 w-full flex justify-center relative">
            <div class="m-auto max-w-2xl w-full">
                <div class="flex flex-col gap-3 text-center">
                    <Spinner className="size-5" />

                    <div class=" font-secondary xl:text-lg">
                        Launching Open WebUI...
                    </div>

                    <Versions />

                    <!-- {#if $serverStartedAt}
                    {#if currentTime - $serverStartedAt > 10000}
                        <div
                            class=" font-default text-xs"
                            in:fly={{ duration: 500, y: 10 }}
                        >
                            If it's your first time, it might take a few minutes
                            to start.
                        </div>
                    {/if}
                {/if}

                <Logs show={showLogs} logs={$serverLogs} /> -->
                </div>
            </div>
        </div>
    {/if}
</main>

<Toaster
    theme={window.matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark"
        : "light"}
    richColors
    position="top-center"
/>
