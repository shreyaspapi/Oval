<script lang="ts">
    import { toast } from "svelte-sonner";
    import { onMount } from "svelte";

    import { copyToClipboard } from "../../utils";
    import Switch from "../common/Switch.svelte";
    import Spinner from "../common/Spinner.svelte";
    import ConfirmDialog from "../common/ConfirmDialog.svelte";

    let { info, installed = $bindable(false) } = $props();

    let config = $state(null);

    let serveOnLocalNetwork = $state(false);
    let autoUpdate = $state(true);

    let showConfirm = $state(false);

    const onOpen = async () => {
        try {
            await window.electronAPI.openInBrowser(info?.url);
        } catch (error) {
            toast.error("Failed to open URL in browser");
        }
    };

    const onUpdate = async () => {
        try {
            await window.electronAPI.setConfig({
                ...config,
                serveOnLocalNetwork: serveOnLocalNetwork,
                autoUpdate: autoUpdate,
            });
            toast.success("Configuration updated successfully");
        } catch (error) {
            toast.error("Failed to update configuration");
        }
    };

    const resetHandler = async () => {};

    onMount(async () => {
        config = await window.electronAPI.getConfig();

        serveOnLocalNetwork = config?.serveOnLocalNetwork ?? false;
        autoUpdate = config?.autoUpdate ?? true;
    });
</script>

<ConfirmDialog
    bind:show={showConfirm}
    title="Factory Reset"
    message="Are you sure you want to reset the app? This will remove all configurations, user data, and the bundled Python environment, restoring the app to its original state."
    confirmLabel="Reset"
    onConfirm={async () => {
        try {
            installed = null;
            config = null;
            await window.electronAPI.resetApp();
            toast.success("App has been reset successfully.");

            setTimeout(() => {
                window.location.reload();
            }, 1000);
        } catch (error) {
            toast.error("Failed to reset the app");
        }
    }}
/>

{#if config}
    <div class="text-sm">
        <div class="text-sm font-medium">Server Settings</div>

        <div class="flex flex-col space-y-1 mt-2">
            <div>
                <div class="flex flex-row items-center justify-between">
                    <div
                        class="flex flex-row items-center space-x-1.5 text-green-100"
                    >
                        <svg
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="2"
                            stroke="currentColor"
                            class="size-4"
                        >
                            <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M12 21a9.004 9.004 0 0 0 8.716-6.747M12 21a9.004 9.004 0 0 1-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 0 1 7.843 4.582M12 3a8.997 8.997 0 0 0-7.843 4.582m15.686 0A11.953 11.953 0 0 1 12 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0 1 21 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0 1 12 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 0 1 3 12c0-1.605.42-3.113 1.157-4.418"
                            />
                        </svg>

                        <div>Reachable at</div>
                    </div>

                    <div class="flex flex-row items-center">
                        <button
                            class="p-1 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-850 transition cursor-pointer flex items-center px-2.5 text-xs"
                            aria-label="copy"
                            onclick={() => {
                                copyToClipboard(info?.url || "");

                                toast.success("URL copied to clipboard");
                            }}
                        >
                            <div class=" flex items-center pr-2">
                                <span class="relative flex size-2">
                                    <span
                                        class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"
                                    />
                                    <span
                                        class="relative inline-flex rounded-full size-2 bg-green-500"
                                    />
                                </span>
                            </div>
                            <div class="">
                                {info?.url}
                            </div>
                        </button>

                        <button
                            class="p-1 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-850 transition cursor-pointer"
                            aria-label="copy"
                            onclick={() => {
                                onOpen();
                            }}
                        >
                            <svg
                                xmlns="http://www.w3.org/2000/svg"
                                viewBox="0 0 16 16"
                                fill="currentColor"
                                class="size-4"
                            >
                                <path
                                    d="M6.22 8.72a.75.75 0 0 0 1.06 1.06l5.22-5.22v1.69a.75.75 0 0 0 1.5 0v-3.5a.75.75 0 0 0-.75-.75h-3.5a.75.75 0 0 0 0 1.5h1.69L6.22 8.72Z"
                                />
                                <path
                                    d="M3.5 6.75c0-.69.56-1.25 1.25-1.25H7A.75.75 0 0 0 7 4H4.75A2.75 2.75 0 0 0 2 6.75v4.5A2.75 2.75 0 0 0 4.75 14h4.5A2.75 2.75 0 0 0 12 11.25V9a.75.75 0 0 0-1.5 0v2.25c0 .69-.56 1.25-1.25 1.25h-4.5c-.69 0-1.25-.56-1.25-1.25v-4.5Z"
                                />
                            </svg>
                        </button>
                    </div>
                </div>
            </div>

            <!-- <div>
            <div class="flex flex-row items-center justify-between">
                <div>Port</div>

                <div>
                    <input
                        type="text"
                        class="w-20 px-2 py-1 rounded text-right"
                        bind:value={port}
                        readonly
                    />
                </div>
            </div>
        </div> -->

            <div>
                <div class="flex flex-row items-center justify-between">
                    <div
                        class="flex flex-row items-center space-x-1.5 text-green-100"
                    >
                        <svg
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="2"
                            stroke="currentColor"
                            class="size-4"
                        >
                            <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z"
                            />
                        </svg>

                        <div>Serve on local network</div>
                    </div>

                    <div>
                        <Switch
                            id="network"
                            bind:state={serveOnLocalNetwork}
                            onChange={async () => {
                                await onUpdate();
                                await window.electronAPI.restartServer();
                            }}
                        />
                    </div>
                </div>

                <div class="text-xs text-gray-500 mt-0.5">
                    Allow other devices on your local network to access the
                    server.
                </div>
            </div>
        </div>

        <hr class="my-3 border-gray-300 dark:border-gray-850" />

        <div class="text-sm font-medium">App</div>

        <div class="flex flex-col space-y-1 mt-2">
            <div>
                <div class="flex flex-row items-center justify-between">
                    <div
                        class="flex flex-row items-center space-x-1.5 text-green-100"
                    >
                        <div>Automatic updates</div>
                    </div>

                    <div>
                        <Switch
                            id="auto-updates"
                            bind:state={autoUpdate}
                            onChange={() => {
                                onUpdate();
                            }}
                        />
                    </div>
                </div>

                <div class="text-xs text-gray-500 mt-0.5">
                    Turn off to disable automatic updates on startup.
                </div>
            </div>
        </div>

        <div class="flex flex-col space-y-1 mt-2">
            <div>
                <div class="flex flex-row items-center justify-between">
                    <div
                        class="flex flex-row items-center space-x-1.5 text-green-100"
                    >
                        <div>Factory Reset</div>
                    </div>

                    <div>
                        <button
                            class="text-xs cursor-pointer"
                            onclick={() => {
                                showConfirm = true;
                            }}
                        >
                            Reset
                        </button>
                    </div>
                </div>

                <div class="text-xs text-gray-500 mt-0.5">
                    Warning: Resetting the app will remove everything, including
                    all configurations, user data, and the bundled Python
                    environment. This action will fully restore the app to its
                    original state.
                </div>
            </div>
        </div>
    </div>
{:else}
    <div
        class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 drag-region"
    >
        <div class="flex-1 w-full flex justify-center relative">
            <div class="m-auto">
                <Spinner />
            </div>
        </div>
    </div>
{/if}
