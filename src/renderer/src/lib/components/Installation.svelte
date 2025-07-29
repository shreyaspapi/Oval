<script lang="ts">
    import { onMount, tick } from "svelte";
    import { fly } from "svelte/transition";

    import Logs from "./setup/Logs.svelte";
    import Spinner from "./common/Spinner.svelte";
    import ArrowRightCircle from "./icons/ArrowRightCircle.svelte";

    import logoImage from "../assets/images/splash.png";

    import galaxyImage from "../assets/images/galaxy.jpg";
    import greenImage from "../assets/images/green.jpg";
    import adamImage from "../assets/images/adam.jpg";
    import nasaImage from "../assets/images/nasa.jpg";
    import neomImage from "../assets/images/neom.jpg";

    let { installed = $bindable() } = $props();

    let images = [galaxyImage, greenImage, adamImage, nasaImage, neomImage];

    let mounted = $state(false);
    let currentTime = Date.now();

    let showLogs = $state(false);
    let installing = $state(false);

    const continueHandler = async () => {
        if (window?.electronAPI) {
            installing = true;

            const pythonStatus = await window.electronAPI.getPythonStatus();
            console.log("Python Status:", pythonStatus);

            if (!pythonStatus) {
                await window.electronAPI.installPython();
            }

            const packageStatus = await window.electronAPI.getPackageStatus();
            console.log("Package Status:", packageStatus);

            if (!packageStatus) {
                await window.electronAPI.installPackage();
            }

            // Wait for the installation to complete
            await tick();

            if (
                (await window.electronAPI.getPythonStatus()) &&
                (await window.electronAPI.getPackageStatus())
            ) {
                // Start the server if it's not already running
                if (!(await window.electronAPI.getServerStatus())) {
                    await window.electronAPI.startServer();
                }

                // Notify the user that the installation is complete
                await window.electronAPI.notification(
                    "Installation Complete",
                    "Open WebUI is now ready to use."
                );

                installed = true; // Update the installed state
            } else {
                // Handle the case where installation failed
                await window.electronAPI.notification(
                    "Installation Failed",
                    "There was an error during the installation process."
                );
            }

            installing = false;
        }
    };

    let selectedImageIdx = $state(0);

    onMount(() => {
        mounted = true;

        const imageInterval = setInterval(() => {
            selectedImageIdx = (selectedImageIdx + 1) % 5;
        }, 10000);

        const interval = setInterval(() => {
            currentTime = Date.now();
        }, 1000); // Update every second

        return () => {
            clearInterval(interval); // Cleanup interval on destroy
        };
    });
</script>

<div
    class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 p-1"
>
    <div class="fixed right-0 my-5 mx-6 z-50">
        <div class="flex space-x-2">
            <button
                class=" self-center cursor-pointer outline-none"
                onclick={() => (showLogs = !showLogs)}
            >
                <img
                    src={logoImage}
                    class=" w-6 rounded-full dark:invert"
                    alt="logo"
                />
            </button>
        </div>
    </div>

    {#each images as image, index (index)}
        <div
            class="image w-full h-full absolute top-0 left-0 bg-cover bg-center transition-opacity duration-1000"
            style="opacity: {selectedImageIdx === index
                ? 1
                : 0}; background-image: url({image})"
        ></div>
    {/each}

    <div
        class="w-full h-full absolute top-0 left-0 bg-gradient-to-t from-20% from-white dark:from-black to-transparent"
    ></div>

    <div
        class="w-full h-full absolute top-0 left-0 backdrop-blur-sm bg-white dark:bg-black opacity-50"
    ></div>

    <div class=" absolute w-full top-0 left-0 right-0 z-10">
        <div class="h-6 drag-region"></div>
    </div>

    <div class="flex-1 w-full flex justify-center relative">
        <div
            class="m-auto flex flex-col justify-center text-center max-w-2xl w-full"
        >
            {#if mounted}
                <div
                    class=" font-medium text-5xl md:text-6xl xl:text-7xl text-center mb-4 xl:mb-5 font-secondary"
                    in:fly={{ duration: 750, y: 20 }}
                >
                    Open WebUI
                </div>

                <div
                    class=" text-sm xl:text-base text-center mb-3"
                    in:fly={{ delay: 250, duration: 750, y: 10 }}
                >
                    To get started with Open WebUI, click Continue.
                </div>
            {/if}

            {#if showLogs}
                <Logs />
            {/if}
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
                                in:fly={{
                                    delay: 100,
                                    duration: 500,
                                    y: 10,
                                }}
                            >
                                This might take a few minutes, We’ll notify you
                                when it’s ready.
                            </div>

                            <!-- {#if $serverLogs.length > 0}
                                <div
                                    class="text-[0.5rem] text-gray-500 font-mono text-center line-clamp-1 px-10"
                                >
                                    {$serverLogs.at(-1)}
                                </div>
                            {/if} -->
                        </div>
                    {:else if mounted}
                        <button
                            class="relative z-20 flex p-1 rounded-full bg-black/5 hover:bg-black/10 dark:bg-white/5 dark:hover:bg-white/10 transition font-medium text-sm cursor-pointer"
                            onclick={() => {
                                continueHandler();
                            }}
                            in:fly={{
                                delay: 500,
                                duration: 750,
                                y: 10,
                            }}
                        >
                            <ArrowRightCircle className="size-6" />
                        </button>
                        <div
                            class="mt-1.5 font-primary text-base font-medium"
                            in:fly={{
                                delay: 500,
                                duration: 750,
                                y: 10,
                            }}
                        >
                            {`Continue`}
                        </div>

                        <div
                            class="text-xs mt-3 text-gray-500 cursor-pointer"
                            in:fly={{
                                delay: 500,
                                duration: 750,
                                y: 10,
                            }}
                        >
                            By continuing, you agree to our
                            <button
                                class="underline"
                                onclick={() => {
                                    window.electronAPI.openInBrowser(
                                        "https://github.com/open-webui/desktop/blob/main/LICENSE"
                                    );
                                }}>license agreement</button
                            >.
                        </div>
                    {/if}
                </div>
            </div>
        </div>
    </div>
</div>
